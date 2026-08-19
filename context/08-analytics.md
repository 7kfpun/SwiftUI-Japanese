# 08 — Analytics

All analytics/crash reporting goes through one seam: `Track`
(`nihongo/Ads/AppBootstrap.swift`). Nothing else imports `FirebaseAnalytics`.

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
    static func trace<T>(_ name: String, _ work: () throws -> T) rethrows -> T
}
```

## Rules

- **Every name ships prefixed `nihongo_2026_`** (the second analytics generation).
  Console dashboards must search the prefixed name.
- **`screen` is not a Firebase screen view** — it logs one event named `screen` with a
  `name` param, and also feeds `Survey.recordScreen` (deliberately outside the opt-out:
  a feedback report needs its context even from an excluded device).
- **`is_premium` rides on every event**, merged in by `Track.event` from a flag cached
  by `setPremium` — which also sets the `user_type` and `premium_tier` user properties.
- Names and param keys are `lower_snake_case`. Params qualify (which lesson, which
  rung, correct?); no param ever carries an identifier or user-typed text.
- Custom params are invisible in GA4 reports until registered as custom dimensions in
  the console — collection alone only reaches DebugView and BigQuery.
- The per-device opt-out (`setExcluded`, Settings' hidden version-footer long-press)
  disables Analytics, Crashlytics and Performance together.
- **One event name per thing that happened — never one generic name split by a
  param.** Every mode's answer has its own name (`challenge_answer`, `match_answer`,
  `train_answer`, `kana_swipe_answer`, …): a name you can read straight off the
  console says what it is. Params qualify (which lesson, correct?); they don't
  identify. Decided, reversed once, and re-decided 2026-08 — don't "unify" these.

## Adding an event

- **Through `Track`, nowhere else.** If a file needs `import FirebaseAnalytics`, the
  change is wrong. Views call `Track.event`; the seam adds the prefix and `is_premium`.
- **Name the thing that happened**, `lower_snake_case`, past-tense outcome or noun
  (`purchase_failed`, `bookmark`). Params qualify it — which lesson, which rung,
  correct? — they don't identify it. A new mode's answer gets its own `<mode>_answer`
  name, per the rule above.
- **Reuse an existing name for the same action on the same kind of surface** (add a
  `source` param, as the paywall and prompts do) instead of minting a near-duplicate.
  GA4 caps: 500 distinct names, 25 params per event, 50 registered event dimensions,
  100-char param values.
- **Never log**: an identifier of any kind, user-typed text, or anything joining two
  rows to one person. Lengths and categories are fine (`message_length`,
  `query_length`); content is not.
- **Every new screen goes through `Track.screen`** — it also feeds the survey's
  `last_screen`, so a screen logged any other way breaks feedback context.
- **Failure events carry a `reason`/`outcome` param**, not separate names per failure —
  see `purchase_failed`, `restore`. Success and failure stay separate names, because a
  funnel filters by name first.
- Then: add the row to this file's inventory, and register any new param you'll want
  in reports as a GA4 custom dimension.

## Events

Params in *italics* are common to every row of their group. `is_premium` is on all.

### Answering

| Event | Params | When |
|---|---|---|
| `challenge_answer` | correct, lesson, index, from, to | each ladder option picked |
| `match_answer` | correct, lesson | each Match pair resolved |
| `train_answer` | correct, lesson, from, to | each Train swipe |
| `learn_answer` | correct, lesson | tile answer resolves |
| `kana_classic_answer` / `kana_listening_answer` / `kana_swipe_answer` | correct | each kana quiz answer |
| `kana_write_grade` | pass, score | a drawing is scored |
| `flashcard_grade` / `kana_flashcard_grade` | known, lesson | self-grade swipe — `known` is the learner's own verdict |
| `flashcard_done` / `kana_flashcard_done` | total, lesson | deck finished |

### Challenge ladder

| Event | Params | When |
|---|---|---|
| `challenge_start` | *lesson, index*, questions | run begins |
| `challenge_complete` | score, stars, passed | run recorded (once) |
| `challenge_retry` | previous_score | Try again on the result screen |
| `challenge_done_tapped` | passed | Done/Back on the result screen |
| `challenge_abandon` | question, of | left mid-run |
| `earned_first_group` | — | the 3★ sweep unlocks the first band |

### Study & play

| Event | Params | When |
|---|---|---|
| `study_day` | streak, best | an answer stamps today (`StudyDay.record`) |
| `read_all` | *lesson, mode*, words | Play all / with meanings starts |
| `read_all_loop` | lap | playback wraps to word 1 |
| `play_vocab` | lesson | word tapped in a list |
| `play_kana` | romaji | kana tile tapped |
| `today_swipe` | lesson, depth, deck, for_challenge | deck depth high-water mark |
| `today_challenge_open` | lesson, index | Today's challenge capsule tapped |
| `bookmark` | lesson, stars | star tier cycled |
| `search_vocab` | query_length, results | search fires (never the query text) |
| `intro_mode_peek` | mode | intro card 3 chip tapped |
| `intro_card` / `intro_skip` | card | card shown / tour skipped |
| `intro_done` | knows_kana, textbook_lesson, goal | tour finished, answers attached |

### Settings & toggles

| Event | Params | When |
|---|---|---|
| `set_app_language` / `set_vocab_language` | code | either picker changes |
| `toggle_sound` | on | the global sound toggle |
| `toggle_field` | field, shown | CardOptionsBar chips |
| `train_order_mode` / `learn_order_mode` | ordered | ordered/random switch |
| `train_form` | from, to, lesson | Train's form pair cycled |
| `kana_table` / `kana_tile_script` | table / script | kana chart switches |
| `kana_quiz_open` | table | a kana mode opened from the chart |
| `kana_clear` | cleared | learned-kana reset confirmed |
| `kana_write_template` | shown, romaji | Write's tracing template toggled |
| `lesson_group` | group | lesson band picker |

### Money

| Event | Params | When |
|---|---|---|
| `paywall_shown` / `paywall_dismissed` / `paywall_unavailable` | *source, lesson*; +purchased on dismiss | paywall lifecycle |
| `purchase_start` / `purchase_success` / `purchase_failed` | *tier, source*; +reason on failure (error/cancelled/pending/unverified) | StoreKit flow |
| `restore` | outcome (already_premium/restored/nothing_found/failed), source, premium | Restore tapped; outcome separates "wrong Apple ID" from "cancelled sign-in" |
| `locked_mode` | mode, lesson | locked practice row tapped |
| `locked_challenge` | lesson, index | locked rung tapped |
| `locked_read_all` | lesson, words_read | meanings preview hit its limit |

### Prompts (rating, share, notifications)

| Event | Params | When |
|---|---|---|
| `rating_shown` / `rating_given` / `rating_dismissed` | lesson or source; stars on given | the star row (result screen or Diagnostics) |
| `review_requested` | — | SKStoreReviewController asked |
| `share_prompt_shown` / `share_prompt_dismissed` | lesson, passed_total / accepted | the recommend-a-friend nudge |
| `share_opened` / `share_completed` | source (prompt/settings) | share sheet opened / finished |
| `notification_opt_in` | source (intro/streak), accepted; +streak from streak | soft ask answered |
| `notification_opt_in_dismissed` | streak | soft-ask sheet swiped away |
| `notification_permission` | granted | the one-shot iOS alert |
| `streak_reminder` / `streak_reminder_hour` / `streak_reminder_kept` | on, hour | Settings reminder controls |

### Plumbing & diagnostics

| Event | Params | When |
|---|---|---|
| `screen` | name (+lesson etc.) | every screen; the full list is below |
| `audio_missing` | item | clip fell back to TTS (+ a Crashlytics breadcrumb) |
| `survey_failed` | collection | a Firestore write was rejected — usually stale rules |
| `ad_failed` / `interstitial_shown` / `interstitial_failed` | error where relevant | ad lifecycle |
| `widget_open` / `widget_challenge_open` | lesson (+index) | launched via widget deep link |
| `push_registered` / `push_register_failed` / `fcm_token` | error / present | APNs registration |
| `notification_opened` | kind (streak_reminder/push) | a notification was tapped |
| `feedback_opened` / `feedback_dismissed` / `feedback_submitted` | source; +message_length on dismiss, categories on submit — never the text | feedback flow |
| `manage_subscription` | — | Settings row tapped |

### Screens (`screen`, split by `name`)

`today` `kana` `lessons` `select_mode` `vocab_list` `flashcards` `train` `match`
`learn` `challenge` `kana_flashcard` `kana_quiz_mode` `kana_quiz_classic`
`kana_quiz_listening` `kana_quiz_swipe` `kana_write` `progress` `bookmarks`
`settings` `legal` — lesson-scoped ones carry `lesson` (challenge adds `index`,
legal adds `doc`).

### Performance traces

`vocab_decode` (`VocabStore`) — the app's largest launch cost, and the one number that
differs by course (2,089 vs 7,972 entries). Everything else (app start, rendering,
network) is Performance's automatic instrumentation.

## User properties

| Property | Values | Set by |
|---|---|---|
| `user_type` | premium / free | `setPremium`, from `Store.refreshEntitlement` |
| `premium_tier` | lifetime / 1m / 3m / 6m / 12m / none | same |
| `ui_language` | the chosen interface language | `setProfile`, from `Unlock.refresh` |
| `meaning_language` | the chosen meanings language | same |
| `knows_kana` | none / hiragana / both / unanswered | same |
| `learning_goal` | travel / jlpt / work / culture / other / unanswered | same |
| `earned_first_group` | true / false | same |

**The bar for adding one: GA4 must not already know it.** Device model, OS version,
screen size, app version and build, country and the *device* language are collected
automatically as dimensions — re-sending them as user properties buys nothing and spends
from a cap of 25 per project. (The RN predecessor shipped fifteen such duplicates, plus a
`user_id` and `deviceId` both holding `identifierForVendor`. Neither is portable here:
`Analytics.setUserID` is called nowhere in this codebase and must stay that way.)

`Track.profile(...)` is pure and `analyticsProfileSegmentsWithoutIdentifying` pins the
names, the `unanswered` fallbacks and the 36-char clamp — Firebase isn't configured under
test, so anything folded into the send itself would be verified by nothing.

Caps: 25 user properties, values ≤36 chars (truncated silently past it), 50 event-scoped
custom dimensions per project. User properties are forward-only — they don't apply to
events already sent.
