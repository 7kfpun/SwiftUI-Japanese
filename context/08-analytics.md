# 08 — Analytics

All analytics/crash reporting goes through one seam: `Track`
(`nihongo/Ads/AppBootstrap.swift`). Nothing else in the codebase imports
`FirebaseAnalytics` directly.

## The `Track` API

```swift
enum Track {
    static let prefix = "nihongo_2026_"
    static func event(_ name: String, _ params: [String: Any]? = nil)
    static func screen(_ name: String, _ params: [String: Any] = [:])
    static func setPremium(_ isPremium: Bool, tier: String)
    static func audioMissing(_ item: String)
}
```

- **Every event name is prefixed `nihongo_2026_`** — so `Track.event("kana_clear")`
  actually logs `nihongo_2026_kana_clear` in Firebase. The prefix is a version/
  cohort marker (this codebase's second analytics generation); don't drop it
  when cross-referencing event names against a Firebase console dashboard.
- **`Track.screen(name:params:)` is not a distinct Firebase event type** — it
  logs the *same* `event(_:)` path with the literal name `"screen"` (→
  `nihongo_2026_screen`) and merges in a `name` param. So every screen view in
  Firebase is one event name (`nihongo_2026_screen`) filtered by its `name`
  param, not N separate per-screen event names. Every top-level view in the
  app calls this once in `.onAppear`.
- **`is_premium` rides on every single event**, automatically merged in by
  `Track.event`, sourced from a cached flag set by `Track.setPremium` (called
  from `Store.refreshEntitlement()` whenever entitlement changes). This is
  deliberately *redundant* with the Firebase user properties below — an
  explicit per-event param lets a funnel filter by premium status without
  joining against user-level data.
- **`Track.setPremium` also sets two Firebase user properties**:
  `user_type` (`"premium"`/`"free"`) and `premium_tier`
  (`"lifetime"`/`"3m"`/`"6m"`/`"12m"`/`"none"`) — these attach to *every*
  subsequent event automatically via Firebase's own mechanism, independent of
  the per-event `is_premium` param above.
- **DEBUG builds never send real analytics** — `AppBootstrap.swift`'s
  `AppDelegate` calls `Analytics.setAnalyticsCollectionEnabled(false)` and
  `Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)` inside
  `#if DEBUG`, so Xcode/simulator runs during development don't pollute
  production analytics or crash counts. This only matters if Firebase is
  actually configured at all — see the two-layer opt-in below.
- **Two-layer opt-in, both must be true for anything to fire**: (1) the
  `FirebaseAnalytics`/`FirebaseCrashlytics` Swift Packages must be added to the
  Xcode project (`#if canImport(...)` guards every call site — the whole
  `Track` API compiles to no-ops without the packages), and (2) a real
  `GoogleService-Info.plist` must be present in the bundle (`FirebaseApp.configure()`
  only runs if that file exists — see `config/README.md`). A fresh clone with
  neither has a fully-working, silently-no-op `Track`.

## Event catalog

~60 names: 15 literal screens + 2 dynamic, 41 literal events + 4 dynamic.
Regenerate the literal ones with:

```sh
grep -rhoE 'Track\.(event|screen)\("[a-z_]+"' nihongo --include="*.swift" | sort -u
```

That grep **misses the dynamic names** (they're built from interpolation, so no
literal exists to match) — see the note under each group below.

### Screens
All via `Track.screen`, i.e. `nihongo_2026_screen` filtered by its `name` param.

`today`, `lessons`, `select_mode`, `vocab_list`, `flashcards`, `train`, `learn`,
`challenge` (params `lesson`, `index`), `kana`, `kana_quiz_mode`,
`kana_quiz_swipe`, `kana_flashcard`, `kana_write`, `settings`, `legal`.

*Dynamic:* `kana_quiz_classic` / `kana_quiz_listening` — one `KanaQuizView`,
name chosen by its `listening:` flag.

### Challenge ladder — the funnel that matters
| Event | Params |
|---|---|
| `challenge_start` | `lesson`, `index`, `questions` |
| `challenge_complete` | `lesson`, `index`, `score`, `stars`, `passed` |
| `challenge_abandon` | `lesson`, `index`, `question`, `of`, `correct` |
| `challenge_retry` | `lesson`, `index`, `previous_score` |
| `challenge_done_tapped` | `lesson`, `index`, `passed` |
| `locked_challenge` | `lesson`, `index` |

`challenge_abandon` fires from `onDisappear` when a run is left past question 1.
The count alone is `start − complete`; the point of the event is **`question`** —
*where* people bail. Bailing at Q2 is a difficulty wall, at Q9 it's fatigue or an
interruption, and those want opposite fixes.

### Learn-side practice (untested modes)
`train_answer` (`correct`, `lesson`), `train_form` (`from`, `to`, `lesson`),
`train_order_mode` (`ordered`), `learn_answer` (`correct`), `learn_order_mode`
(`ordered`), `read_all` (`lesson`), `play_vocab` (`lesson`), `search_vocab`
(`query_length`, `results`), `lesson_group` (`group`).

`train_form` matters because a switchable prompt/answer pair is Train's whole
premise — untracked, it's the one thing about the mode we'd know nothing about.

*Dynamic:* `flashcard_grade` / `flashcard_done` and `kana_flashcard_grade` /
`kana_flashcard_done` — built as `"\(trackName)_grade"` / `"_done"` from
`FlashcardScreen`'s `trackName` parameter.

### Kana
`kana_quiz_open`, `kana_quiz_answer` (`correct`, `mode` = classic/listening/swipe),
`kana_write_grade` (`pass`, `score`), `kana_write_template` (`shown`, `romaji`),
`kana_table` (`table`), `kana_tile_script` (`script`), `kana_clear`, `play_kana`
(`romaji`).

`kana_write_template` is the difficulty signal for Write mode: revealing the
stroke guide means the kana isn't learned yet.

### Today + widget
`today_swipe` (`lesson`, `depth`, `deck`, `for_challenge`), `today_lesson`
(`lesson`), `widget_open` (`lesson`).

`today_swipe` reports **depth** (furthest card reached this deck), not swipe
count — bouncing between cards 1 and 2 isn't engagement. `for_challenge` lets you
ask whether people who study Today go on to pass that rung. Today is the landing
tab, so a depth distribution stuck at 1 means the cards are wallpaper.

`widget_open` needs three cooperating pieces, all required: `.widgetURL` in
`TodayWidget.swift`, the `nihongo` scheme in `CFBundleURLTypes` (Info.plist), and
`onOpenURL` in `nihongoApp.swift`. Without all three a widget tap is
indistinguishable from any other cold launch.

### Monetization
`paywall_shown` / `paywall_dismissed` (`source`, plus `purchased` on dismiss),
`purchase_start` / `purchase_success` / `purchase_failed` (`tier`, plus `reason`
on failure), `restore` (`premium`), `manage_subscription`, `locked_mode`
(`mode`, `lesson`), `interstitial_shown`, `ad_failed` (`error`).

### Preferences & housekeeping
`toggle_sound` (`on`), `toggle_field` (`field`, `shown`), `set_app_language` /
`set_vocab_language` (`code`), `open_feedback`, `audio_missing` (`item`, via
`Track.audioMissing`).

### Deliberately not tracked
- **Per-question challenge answers** — ~10 events per run (2,780 across the whole
  ladder) to learn which *words* are hardest. You can't edit Minna no Nihongo's
  vocabulary, so it's high volume for near-zero actionability.
- **`Pref.analyticsExcluded` toggle** — tracking the control whose job is
  disabling tracking would be self-defeating.
- **`app_open` / `first_open` / `screen_view`** — Firebase logs these itself.

## Source-attribution pattern on paywall events

`PaywallView` takes a **`source: String`** it doesn't otherwise use except to
tag its own two events (`paywall_shown`, `paywall_dismissed`). Every call site
passes a distinct, purpose-named source so a funnel can tell which entry point
actually converts:

| Call site | `source` value |
|---|---|
| Lessons Learn, trial limit hit | `learn_trial_limit` |
| Lessons Flashcards, trial limit hit | `flashcard_trial_limit` |
| Lessons Quiz/Listening, trial limit hit | `quiz_trial_limit` |
| Today, locked-lesson menu tap | `today_lock` |
| Settings, "Unlock all lessons" | `settings` |

**Known gap**: this `source` does *not* propagate into the purchase events
(`purchase_start`/`purchase_success`/`purchase_failed`) — those only carry
`tier`. So today you can see *which entry point opened the paywall* and
*whether a purchase happened*, but not join them directly in one event; doing
so requires session-level correlation (e.g. by timestamp proximity) rather
than a shared param. Worth fixing if paywall-source ROI ever needs precise
attribution.

Separately, a `trial_limit` event (params `mode`, `lesson`) fires at the exact
moment a gate trips, *before* `showPaywall` flips true — this is finer-grained
than `paywall_shown` (which fires once the sheet is actually presented) and
lets you distinguish "hit the gate" from "the paywall UI rendered."

## `audioMissing` — coverage-gap detector, not just an error log

`Pronouncer`'s live-TTS fallback path (both `AudioPronouncer` and
`LessonPlayer`) calls `Track.audioMissing(item)` every time it falls back —
this doubles as a Crashlytics breadcrumb (`Crashlytics.crashlytics().log(...)`)
*and* an Analytics event, so a production spike in TTS fallback usage (e.g.
after a data regeneration accidentally drops a clip) is visible both in a
crash-adjacent log stream and in an analytics dashboard, without needing a
crash to actually happen.
