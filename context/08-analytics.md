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
  `practice_answer`, `kana_swipe_answer`, …): a name you can read straight off the
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
| `match_round` | lesson, round, attempts | a board cleared, logged before the next deal — the mode is endless, so consecutive rows are the only session length it has |
| `practice_answer` | correct, lesson, from, to | each Practice quiz swipe |
| `practice_done` | total, lesson | Practice queue emptied |
| `practice_restart` | total, lesson | Restart tapped on the done screen |
| `practice_peek` | lesson | card held to read its back (that answer is then uncredited) |
| `practice_show_kana` | lesson | the reading asked for on a kanji prompt |
| `practice_pair` | from, to, mixed, lesson | quiz pair committed from the sheet |
| `learn_answer` | correct, lesson | tile answer resolves |
| `kana_classic_answer` / `kana_listening_answer` / `kana_swipe_answer` | correct | each kana quiz answer |
| `kana_quiz_direction` | from, to | either side of a kana quiz swapped — logged in `KanaQuizModel` after the swap, so the pair reported is the one asked for, and one call site each covers both quiz screens |
| `kana_write_grade` | pass, score | a drawing is scored |
| `kana_flashcard_grade` | known | kana self-grade swipe |
| `kana_flashcard_reveal` | — | Reveal tapped before grading (`FlashcardScreen` logs `<trackName>_reveal`, so only a deck that names itself sends it — today only kana) |
| `kana_flashcard_done` | total | kana deck finished |
| `kana_flashcard_restart` | total | Restart on the kana done screen |

Retired (never reuse the names): `train_answer`, `train_form`, `train_order_mode`,
`flashcard_grade`, `flashcard_done` — Train and the Lessons flashcards merged into
Practice 2026-08 — `practice_grade`, which counted a self-assessment Practice no
longer asks for, and `practice_card`, which marked a teaching card being handed to the
quiz: the card is no longer a step of its own, so nothing logs it.

### Challenge ladder

| Event | Params | When |
|---|---|---|
| `challenge_start` | *lesson, index*, questions | the briefing's Start button — a run begins when the learner says so, not on appear |
| `challenge_complete` | score, stars, passed | run recorded (once) |
| `challenge_next` | *lesson*, from_index, stars | the result screen's forward step to the next rung |
| `challenge_retry` | previous_score | Try again on the result screen |
| `challenge_done_tapped` | passed | Done/Back on the result screen |
| `challenge_abandon` | question, of, correct | left mid-run — `correct` says whether the run was going badly or merely interrupted |
| `challenge_review_play` | — | a missed word tapped to hear it again, on the result screen's "Review these" list |
| `cheer_replay` | stars, passed | the cheer phrase tapped for another one; scoped to the tier that picks the phrase, so this row carries neither lesson nor index |
| `earned_first_group` | lesson, index | the 3★ sweep unlocks the first band — the rung that completed it |

### Study & play

| Event | Params | When |
|---|---|---|
| `study_day` | streak, best | an answer stamps today (`StudyDay.record`) |
| `read_all` | *lesson, mode*, preview | Read along starts, or switches mode; `preview` marks a run cut short by the free meanings limit |
| `read_all_loop` | lap | playback wraps to word 1 |
| `read_all_stop` | lesson, mode | the lit segment tapped a second time — the only way to end a run without leaving the screen |
| `read_all_jump` | lesson, index | a playlist row tapped while playing, moving the run to that word (a tap on a *stopped* player just speaks the word and logs nothing) |
| `read_all_speed` | rate, lesson | Read along speed changed (premium only) |
| `read_all_pause` | paused, lesson | Read along paused or resumed |
| `locked_speed` | lesson | the speed dial tapped without premium |
| `vocab_cut` | cut, lesson | vocab list cut chip (all/notMemorized/bookmarked) |
| `examples_shown` | on | example-sentence toggle |
| `play_vocab` | lesson | word tapped in a list |
| `play_example` | lesson, surface (vocab_list/practice/flashcards) | the example sentence tapped to hear it — logged at each caller, never inside `VocabFace`, so the surface is the caller's own fact |
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
| `learn_order_mode` | ordered | Learn's ordered/random switch |
| `learn_shuffle` | lesson, via (button/swipe) | a reshuffle inside random mode. One name, two ways in: the Random button pages through `CardPager`'s `fling`, so `turnPage` consumes that arrival instead of counting it a second time as a swipe |
| `flashcard_order_mode` | ordered | Flashcards' ordered/random switch |
| `flashcard_flip` | lesson | a Flashcards card held to see its back |
| `kana_table` / `kana_tile_script` | table / script | kana chart switches |
| `kana_quiz_open` | table | a kana mode opened from the chart |
| `kana_clear` | cleared | learned-kana reset confirmed |
| `kana_write_template` | shown, romaji | Write's tracing template toggled |
| `lesson_group` | group | lesson band picker |

### Money

| Event | Params | When |
|---|---|---|
| `paywall_shown` / `paywall_dismissed` / `paywall_unavailable` | *source, lesson*; +purchased on dismiss | paywall lifecycle |
| `paywall_retry` | *source, lesson* | Try again on the products-didn't-load state — whether an empty paywall is retried or simply abandoned |
| `purchase_start` / `purchase_success` / `purchase_failed` | *tier, source*; +reason on failure (error/cancelled/pending/unverified) | StoreKit flow |
| `restore` | outcome (already_premium/restored/nothing_found/failed), source, premium; +error on failure | Restore tapped; outcome separates "wrong Apple ID" from "cancelled sign-in", and `error` names the failure mode (cancelled, offline) a support reply turns on — the message only, never anything identifying |
| `locked_mode` | mode, lesson | locked practice row tapped |
| `locked_challenge` | lesson, index | locked rung tapped |
| `locked_read_all` | lesson, heard | meanings preview hit its limit (`heard` = words played before it did) |

### Prompts (rating, share, notifications)

| Event | Params | When |
|---|---|---|
| `rating_shown` | lesson, passed_total | the star row is about to appear (ladder only) |
| `rating_given` | stars, source (challenge/diagnostics); +lesson, index from the ladder | a star picked |
| `rating_dismissed` | source; +lesson from the ladder | closed without picking |
| `review_requested` | — | SKStoreReviewController asked |
| `share_prompt_shown` / `share_prompt_dismissed` | lesson, passed_total / accepted | the recommend-a-friend nudge |
| `share_opened` | source (prompt/settings) | share sheet opened |
| `share_completed` | source, completed, activity | the share sheet closed — **also on cancel**, as `completed: false` with `activity: none`, so this is not a conversion count on its own. Only the prompt path can emit it (Settings shares through `ShareLink`, which has no completion handler), so `source` is always `prompt` |
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
| `ad_failed` / `interstitial_shown` / `interstitial_failed` | error where relevant; `ad_failed` adds slot | ad lifecycle — `slot` is which banner placement failed, so one broken unit doesn't read as every ad failing |
| `widget_open` / `widget_challenge_open` | lesson (+index) | launched via widget deep link |
| `push_registered` / `push_register_failed` / `fcm_token` | error / present | APNs registration |
| `notification_opened` | kind (streak_reminder/push) | a notification was tapped |
| `feedback_opened` / `feedback_dismissed` | source; +message_length on dismiss | sheet opened / abandoned |
| `feedback_submitted` | source, kind, area, lesson, has_item, message_length, has_email, stars | a report sent (`Feedback.Draft.trackParams`). Buckets and lengths only: `has_item` and `has_email` are the aggregate halves of the reported word and the reply address, and the message itself is never logged |
| `report_swipe` | lesson | the vocab list swiped to report a mistake — logged on the swipe, so finding the gesture is countable separately from sending a report |
| `manage_subscription` | — | Settings row tapped |

**Audio replays on a card or a prompt are deliberately untracked.** Tapping the Practice
card, a flashcard, the Today card or a quiz prompt speaks the word — but there the tap
*is* the surface, so it fires as often as a learner idly touches the screen and would
swamp `play_vocab` with rows that mean nothing in particular. The explicit speaker
controls are the tracked ones (`play_vocab`, `play_example`, `play_kana`,
`challenge_review_play`, `cheer_replay`): each is a control someone aimed at.

### Screens (`screen`, split by `name`)

`today` `kana` `lessons` `select_mode` `vocab_list` `read_along` `flashcards` `practice` `match`
`learn` `challenge` `kana_flashcard` `kana_quiz_mode` `kana_quiz_classic`
`kana_quiz_listening` `kana_quiz_swipe` `kana_write` `progress` `bookmarks`
`settings` `legal` `intro` `diagnostics` — lesson-scoped ones carry `lesson` (challenge
adds `index`, legal adds `doc`). `kana_quiz_classic` and `kana_quiz_listening` are one
screen passing its table, so a grep for the literal finds neither. `intro` fires
alongside the tour's own `intro_card`; `diagnostics` is developer-only and unlocalised,
and is there because `last_screen` has to be able to name it when its rating write or its
Firestore probe reports a failure.

### Performance traces

`vocab_decode` (`VocabStore`) — the app's largest launch cost, and the one number that
differs by course (2,100 vs 7,972 entries). Everything else (app start, rendering,
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
