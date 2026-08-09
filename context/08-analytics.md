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
    static func setExcluded(_ excluded: Bool)
    static var isExcluded: Bool
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
  Firebase is one event name filtered by its `name` param, not N separate
  per-screen event names.
- **`is_premium` rides on every single event**, automatically merged in by
  `Track.event`, sourced from a cached flag set by `Track.setPremium` (called
  from `Store.refreshEntitlement()` whenever entitlement changes). This is
  deliberately *redundant* with the Firebase user properties below — an
  explicit per-event param lets a funnel filter by premium status without
  joining against user-level data.
- **`Track.setPremium` also sets two Firebase user properties**:
  `user_type` (`"premium"`/`"free"`) and `premium_tier`
  (`"lifetime"`/`"1m"`/`"3m"`/`"6m"`/`"none"`, plus `"12m"` for a legacy
  subscriber who restored — that tier is no longer sold) — these attach to *every*
  subsequent event automatically via Firebase's own mechanism, independent of
  the per-event `is_premium` param above. Note `…premium.3M`'s tier label is the
  lowercased `"3m"`: the analytics tier and the product ID are not the same string
  (`06-monetization.md`).
- **Two device-level kill switches.** `#if DEBUG` in `AppBootstrap` disables both
  Analytics and Crashlytics collection, so Xcode/simulator runs never pollute
  production counts. `Pref.analyticsExcluded` does the same for a Release/TestFlight
  build on the developer's own device, toggled by tapping the Settings version footer
  7 times and applied immediately via `Track.setExcluded` as well as at next launch.
  `Survey` deliberately ignores both — see `09-intro-and-survey.md`.
- **Two-layer opt-in, both must be true for anything to fire**: (1) the
  `FirebaseAnalytics`/`FirebaseCrashlytics` Swift Packages must be added to the
  Xcode project (`#if canImport(...)` guards every call site — the whole
  `Track` API compiles to no-ops without the packages), and (2) a real
  `GoogleService-Info.plist` must be present in the bundle (`FirebaseApp.configure()`
  only runs if that file exists — see `config/README.md`). A fresh clone with
  neither has a fully-working, silently-no-op `Track`.

## Event catalog

Regenerate the literal names with:

```sh
grep -rhoE 'Track\.(event|screen)\("[a-z_]+"' nihongo --include="*.swift" | sort -u
```

That grep currently yields **15 screen names and 50 event names**, and it misses three
kinds of name — so treat the sections below as the grep's output *plus* the dynamic
additions called out under each:

1. Names built by interpolation (`"\(trackName)_grade"`).
2. `"screen"` and `"audio_missing"` themselves, because inside `Track` they're logged by
   the bare `event(...)` call, with no `Track.` prefix for the grep to match.

Don't quote a total: it moves with every feature, and a stale total is worse than none.

### Screens
All via `Track.screen`, i.e. `nihongo_2026_screen` filtered by its `name` param.

| `name` | Params |
|---|---|
| `today` | `lesson` |
| `lessons` | — |
| `select_mode` | `lesson` |
| `vocab_list` | `lesson` |
| `flashcards` | `lesson` |
| `train` | `lesson` |
| `learn` | `lesson` |
| `challenge` | `lesson`, `index` |
| `kana` | — |
| `kana_quiz_mode` | — |
| `kana_quiz_swipe` | — |
| `kana_flashcard` | — |
| `kana_write` | — |
| `settings` | — |
| `legal` | `doc` |

*Dynamic:* `kana_quiz_classic` / `kana_quiz_listening` — one `KanaQuizView`, name chosen
by its `listening:` flag.

**Gap worth knowing: the intro tour logs no screen.** `IntroView` fires `intro_card` per
card instead, which carries strictly more information, so a screen event would be
redundant — but a dashboard filtering `screen` will show first-launch users appearing
first on `today` or `kana` with no preceding row.

### First launch (`nihongo/Intro`, `nihongo/Survey.swift`)
| Event | Params |
|---|---|
| `intro_card` | `card` (1…5, the `Intro.Card` raw value) |
| `intro_skip` | `card` — where they bailed |
| `intro_mode_peek` | `mode` — the canonical English `titleKey`, never the localized title |
| `intro_done` | `knows_kana`, `textbook_lesson`, `goal` |
| `survey_failed` | `collection` |

`intro_done` always carries all three keys, using `"unanswered"` / `-1` sentinels
(`IntroAnswers.trackParams`), so a funnel can count "asked but not answered" rather than
finding a param missing. `intro_mode_peek` uses the English key because a param whose
value shifts with device language can't be grouped in a dashboard. `survey_failed` exists
because a Firestore rules rejection surfaces in the completion handler, not at the call
site — offline persistence applies the write locally first, so swallowing the error would
make a misconfigured rule look exactly like success. Full detail in `09-intro-and-survey.md`.

### Challenge ladder — the funnel that matters
| Event | Params |
|---|---|
| `challenge_start` | `lesson`, `index`, `questions` |
| `challenge_complete` | `lesson`, `index`, `score`, `stars`, `passed` |
| `challenge_abandon` | `lesson`, `index`, `question`, `of`, `correct` |
| `challenge_retry` | `lesson`, `index`, `previous_score` |
| `challenge_done_tapped` | `lesson`, `index`, `passed` |

`challenge_abandon` fires from `onDisappear` when a run is left past question 1.
The count alone is `start − complete`; the point of the event is **`question`** —
*where* people bail. Bailing at Q2 is a difficulty wall, at Q9 it's fatigue or an
interruption, and those want opposite fixes.

### Learn-side practice (untested modes)
| Event | Params |
|---|---|
| `train_answer` | `correct`, `lesson` |
| `train_form` | `from`, `to`, `lesson` |
| `train_order_mode` | `ordered` |
| `learn_answer` | `correct` |
| `learn_order_mode` | `ordered` |
| `read_all` | `lesson` |
| `play_vocab` | `lesson` |
| `search_vocab` | `query_length`, `results` |
| `lesson_group` | `group` |

`train_form` matters because a switchable prompt/answer pair is Train's whole
premise — untracked, it's the one thing about the mode we'd know nothing about.
`search_vocab` reports the query *length*, never the query.

*Dynamic:* `flashcard_grade` / `flashcard_done` and `kana_flashcard_grade` /
`kana_flashcard_done` — built as `"\(trackName)_grade"` / `"_done"` from
`FlashcardScreen`'s `trackName` (`"flashcard"` and `"kana_flashcard"` respectively).
`_grade` carries `known`.

### Kana
| Event | Params |
|---|---|
| `kana_quiz_open` | — |
| `kana_quiz_answer` | `correct`, `mode` (`classic`/`listening`/`swipe`) |
| `kana_write_grade` | `pass`, `score` |
| `kana_write_template` | `shown`, `romaji` |
| `kana_table` | `table` (`seion`/`dakuon`/`youon`) |
| `kana_tile_script` | `script` (0 hira · 1 kata · 2 romaji) |
| `kana_clear` | — |
| `play_kana` | `romaji` |

`kana_write_template` is the difficulty signal for Write mode: revealing the stroke guide
means the kana isn't learned yet. `kana_tile_script` reports the stored *index*, whose
order is a persisted contract (`03-kana.md`) — so the value is stable across releases as
long as nobody reorders that table.

### Today, widget & watch links
| Event | Params |
|---|---|
| `today_swipe` | `lesson`, `depth`, `deck`, `for_challenge` |
| `today_challenge_open` | `lesson`, `index` |
| `widget_open` | `lesson` |
| `widget_challenge_open` | `lesson`, `index` |

`today_swipe` reports **depth** (furthest card reached this deck), not swipe count —
bouncing between cards 1 and 2 isn't engagement. `for_challenge` lets you ask whether
people who study Today go on to pass that rung. Today is the landing tab, so a depth
distribution stuck at 1 means the cards are wallpaper.

`today_challenge_open` and `widget_challenge_open` are the *same promise on two surfaces*
— the "Ready for Challenge N?" call to action in the app and in the widget — kept as
separate names so the two can be compared. Both land on the lesson's mode list rather
than inside the rung, and both fall back to the Lessons list when the lesson is locked;
`widget_challenge_open` reports `index` purely for analytics, since nothing navigates by
it.

The widget events need three cooperating pieces, all required: `.widgetURL` in
`TodayWidget.swift`, the `nihongo` scheme in `CFBundleURLTypes` (Info.plist), and
`onOpenURL` in `nihongoApp.swift`. Without all three a widget tap is indistinguishable
from any other cold launch.

### Monetization
| Event | Params |
|---|---|
| `paywall_shown` | `source` |
| `paywall_dismissed` | `source`, `purchased` |
| `purchase_start` | `tier` |
| `purchase_success` | `tier` |
| `purchase_failed` | `tier`, `reason` (`error`/`cancelled`/`pending`/`unverified`) |
| `restore` | `premium` |
| `manage_subscription` | — |
| `locked_mode` | `mode`, `lesson` |
| `locked_challenge` | `lesson`, `index` |
| `interstitial_shown` | — |
| `ad_failed` | `error` |

`locked_mode` and `locked_challenge` are the two halves of hitting the paywall from a
lesson: a practice row versus a ladder rung. Both fire from `SelectModeView`, the single
place gating is enforced, and both immediately precede a `paywall_shown` with source
`select_mode_locked` — so the pair tells you *what* someone wanted, which `source` alone
can't.

### Rating
| Event | Params |
|---|---|
| `rating_shown` | `lesson`, `passed_total` |
| `rating_given` | `stars`, `lesson`, `index` |
| `rating_dismissed` | `lesson` |

The three are a complete funnel for the app's own star row, and `rating_given`'s `stars`
is the only sentiment signal the app collects at all — Apple's review sheet reports
nothing back. `rating_dismissed` (fired when the sheet closed with no pick) is
deliberately distinct from a low `rating_given`: "no opinion" and "unhappy" are different
populations and only one gets routed to the feedback form (`06-monetization.md`).
`passed_total` is there to check the 15-rung threshold is actually where people are.

### Preferences & housekeeping
| Event | Params |
|---|---|
| `toggle_sound` | `on` |
| `toggle_field` | `field`, `shown` |
| `set_app_language` | `code` |
| `set_vocab_language` | `code` |
| `open_feedback` | — |
| `audio_missing` | `item` (via `Track.audioMissing`) |

`set_vocab_language` fires from two places — Settings and the intro's first card — with
no flag distinguishing them; the surrounding `intro_card` events are how you tell.

### Deliberately not tracked
- **Per-question challenge answers** — ~10 events per run (2,780 across the whole
  ladder) to learn which *words* are hardest. You can't edit Minna no Nihongo's
  vocabulary, so it's high volume for near-zero actionability.
- **`Pref.analyticsExcluded` toggle** — tracking the control whose job is
  disabling tracking would be self-defeating.
- **Search query text** — only its length and result count.
- **`app_open` / `first_open` / `screen_view`** — Firebase logs these itself.

## Source-attribution pattern on paywall events

`PaywallView` takes a **`source: String`** it doesn't otherwise use except to
tag its own two events (`paywall_shown`, `paywall_dismissed`). Each call site
passes a distinct, purpose-named source so a funnel can tell which entry point
actually converts. There are currently **two**, which is the whole surface area of the
paywall:

| Call site | `source` value |
|---|---|
| `SelectModeView`, any locked mode row or locked rung | `select_mode_locked` |
| `SettingsView`, "Unlock all lessons" | `settings` |

The same pattern runs on the feedback form (`Feedback.url(source:)`), with `settings`
for someone choosing to write in and `rating` for someone a low star sent there — two
different populations that the Airtable form couldn't otherwise tell apart.

**Known gap**: `source` does *not* propagate into the purchase events
(`purchase_start`/`purchase_success`/`purchase_failed`) — those only carry
`tier`. So you can see *which entry point opened the paywall* and *whether a purchase
happened*, but not join them in one event; doing so requires session-level correlation
(e.g. timestamp proximity) rather than a shared param. Worth fixing if paywall-source ROI
ever needs precise attribution.

There is no longer a separate `trial_limit` event: the per-mode card/page/question quotas
it measured are gone, replaced by one whole-lesson rule (`06-monetization.md`), and
`locked_mode`/`locked_challenge` are the finer-grained events now.

## `audioMissing` — coverage-gap detector, not just an error log

`Pronouncer`'s live-TTS fallback path (both `AudioPronouncer` and
`LessonPlayer`, via the shared `Speech` policy) calls `Track.audioMissing(item)` every
time it falls back — this doubles as a Crashlytics breadcrumb
(`Crashlytics.crashlytics().log(...)`) *and* an Analytics event, so a production spike in
TTS fallback usage (e.g. after a data regeneration accidentally drops a clip) is visible
both in a crash-adjacent log stream and in an analytics dashboard, without needing a
crash to actually happen. The expected baseline is not zero: 2 of 2089 words have no clip
by design (`01-data-model.md`).
