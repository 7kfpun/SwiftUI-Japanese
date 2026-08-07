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

## Event catalog (as of this writing — grep `Track\.` to keep current)

**Screens** (all via `Track.screen`, i.e. `nihongo_2026_screen` with `name=`):
`today`, `kana`, `kana_quiz_mode`, `kana_quiz_classic` / `kana_quiz_listening`
(same `KanaQuizView`, name depends on the `listening:` flag), `kana_quiz_swipe`,
`kana_flashcard`, `kana_write`, `lessons`, `select_mode`, `vocab_list`,
`flashcards`, `learn`, `quiz` / `listening` (same `QuizView`, name depends on
`from: .audio`), `settings`, `legal`.

**Custom events**: `kana_quiz_open`, `kana_quiz_answer` (params: `correct`,
`mode` = classic/listening/swipe), `kana_clear`, `kana_write_grade` (params:
`pass`, `score`), `play_kana`, `lesson_group`, `search_vocab` (params:
`query_length`, `results`), `play_vocab`, `learn_answer`, `learn_order_mode`,
`quiz_answer` / `listening_answer` (dynamic name = `"\(screenName)_answer"`),
`flashcard_grade` / `flashcard_done`, `kana_flashcard_grade` /
`kana_flashcard_done` (dynamic name = `"\(trackName)_grade"`/`"_done"` — the
`FlashcardScreen`'s `trackName` parameter), `read_all`, `today_lesson`,
`toggle_field` (params: `field`, `shown`), `toggle_sound`, `trial_limit`
(params: `mode`, `lesson`), `paywall_shown` / `paywall_dismissed` (params:
`source`, and `purchased` on dismiss), `purchase_start` / `purchase_success` /
`purchase_failed` (params: `tier`, and `reason` on failure), `restore` (param:
`premium`), `manage_subscription`, `open_feedback`, `set_app_language` /
`set_vocab_language` (param: `code`), `interstitial_shown`, `ad_failed`
(param: `error`), `audio_missing` (param: `item`, via `Track.audioMissing`).

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
