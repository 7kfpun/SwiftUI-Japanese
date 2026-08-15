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
| `progress` | — |
| `bookmarks` | — |
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
| `intro_card` | `card` (1…6, the `Intro.Card` raw value) |
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
| `read_all` | `lesson`, `mode` (`japanese`/`withMeaning`), `preview` |
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
| `paywall_shown` | `source`, `lesson` (absent from Settings) |
| `paywall_dismissed` | `source`, `lesson`, `purchased` |
| `purchase_start` | `tier`, `source` |
| `purchase_success` | `tier`, `source` |
| `purchase_failed` | `tier`, `source`, `reason` (`error`/`cancelled`/`pending`/`unverified`) |
| `restore` | `premium` |
| `manage_subscription` | — |
| `locked_mode` | `mode` (`flashcards`/`train`/`learn`), `lesson` |
| `locked_challenge` | `lesson`, `index` |
| `locked_read_all` | `lesson`, `heard` |
| `earned_first_group` | `lesson`, `index` — the rung that completed the sweep |
| `bookmark` | `lesson`, `stars` (0 = removed) |
| `interstitial_shown` | — |
| `ad_failed` | `error` |

### Where people hit the paywall

`source` is the answer, and it is on **every** event in the funnel — shown, dismissed and
all three purchase events. Four values, all stable ASCII keys:

| `source` | Triggered by |
|---|---|
| `locked_mode` | a locked Flashcards / Train / Learn row (`SelectModeView`) |
| `locked_challenge` | a locked ladder rung (`SelectModeView`) |
| `read_all_meanings` | the meaning preview running out (`VocabListView`) |
| `settings` | the Premium row in Settings |

Worth remembering when reading conversion: **the paywall is not the only way past the
lock.** Three-starring lessons 1–5 opens the course's first band free
(`earned_first_group`), so a cohort can stop hitting `paywall_shown` without ever
converting — that is the feature working, not a funnel leak.

`lesson` rides alongside it wherever a lesson triggered it, which separates "lesson 8
stops people" from "people don't buy". The finer `locked_*` events say *what* was wanted
— which mode, which rung, how many words were heard — and immediately precede the
matching `paywall_shown`.

Because `source` reaches `purchase_success`, conversion by entry point is a group-by
rather than a timestamp join. Three things were fixed to make that true, all of which had
looked fine in the code:

- **`purchase_*` carried only `tier`.** The funnel stopped dead at `paywall_shown` and
  which entry point actually earned money was a guess, despite `PaywallView.source`'s own
  comment claiming otherwise.
- **`paywall_dismissed` fired only from the Cancel button**, so swiping the sheet away
  logged nothing, and buying dismissed via the `isPremium` observer without logging
  either — making `purchased` a hardcoded `false` that could never be anything else. It
  now fires from `onDisappear`, once, for every exit.
- **`locked_mode`'s `mode` was localized.** It was passed `L.t("Flashcards")`, so the same
  tap arrived as `Flashcards`, `闪卡`, `Karteikarten` — 17 unaggregatable values. It now
  takes a separate stable `key`; `SelectModeView.mode(key:icon:title:…)` keeps the
  analytics name and the on-screen name as two arguments so they can't merge again.

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

`PaywallView` takes a **`source: String`** and an optional **`lesson: Int?`**, and tags
every event it and `Store.purchase` emit. Each call site passes a distinct, purpose-named
source so a funnel can tell which entry point actually converts:

| Call site | `source` value |
|---|---|
| `SelectModeView`, a locked Flashcards / Train / Learn row | `locked_mode` |
| `SelectModeView`, a locked ladder rung | `locked_challenge` |
| `VocabListView`, the meaning preview running out | `read_all_meanings` |
| `SettingsView`, "Unlock all lessons" | `settings` |

`PaywallView.params` builds `source` + `lesson` once and every event merges it, so a new
paywall event can't be added without its attribution.

The same pattern runs on the feedback form (`Feedback.url(source:)`), with `settings`
for someone choosing to write in and `rating` for someone a low star sent there — two
different populations that the Airtable form couldn't otherwise tell apart.

The gap this section used to describe — `source` not reaching the purchase events — is
**closed**: `Store.purchase(_:source:)` takes it and puts it on `purchase_start`,
`purchase_success` and `purchase_failed`. Attribution is a group-by, not a timestamp
join. `SelectModeView` also used to report both its triggers as one `select_mode_locked`
source; they are now distinct.

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

## Firebase Performance

Linked as `FirebasePerformance` on **both** app targets (not the widgets or the watch app)
and started by `FirebaseApp.configure()` like everything else — there is no separate
`configure` call. Most of its value is automatic and needs no code: app start time,
foreground/background traces, screen rendering including **slow and frozen frames**, and
every `URLSession` request.

It honours the same kill switch as Analytics and Crashlytics. `AppBootstrap` disables it
when `Pref.analyticsExcluded` is set or the build is DEBUG, and `Track.setExcluded`
flips it live with the other two. A developer's own device would otherwise skew exactly
the numbers Performance exists to watch — debug build, fast device, office wifi.

### Custom traces go through `Track.trace`

```swift
Track.trace("vocab_decode") { … }
```

`Track` is the one seam and nothing else may import a Firebase module, so this wraps
`Performance.startTrace` the way `Track.event` wraps `Analytics.logEvent`. It takes the
same `nihongo_2026_` prefix, wants `lower_snake_case` names, and — because the whole body
is behind `canImport` — a build with no Firebase package still runs the work, untimed,
rather than failing to compile.

There is exactly one custom trace today, and adding more should clear a real bar: the
automatic instrumentation already covers launch, rendering and network.

| Trace | Why it isn't covered automatically |
|---|---|
| `vocab_decode` | The bundled-JSON decode in `VocabStore.data` — the largest single launch cost, and the one that differs by *course* rather than by device (2,089 entries against JLPT's 7,972, from identical code). A regression reads to users as "the app got slow to open", a report that never arrives with a cause attached. |

### What it costs

Performance is not a small dependency: it pulls in `FirebaseInstallations`,
`FirebaseRemoteConfig` and `FirebaseABTesting` (it fetches its own sampling config at
runtime). That is binary size and a network call at launch. Weigh that before assuming
any further Firebase product is free to add.

### Identifiers

Performance reports carry the Firebase Installation ID. **It does not introduce one** —
`FirebaseAppCheck` and `FirebaseSessions` (under Crashlytics) already depend on
`FirebaseInstallations`, so the FID predates this. See `CLAUDE.md`'s identifier bullet
for where the app's own no-identifier rule starts and the SDKs' internals end.

`PERFORMANCE_DATA` was **already** declared in `fastlane/minna/app_privacy_details.json`
before the SDK existed in the project. That declaration is now accurate rather than
aspirational; don't remove it.

## Notifications

Three types, and they do not overlap. Confusing them is the easiest way to break this.

| Type | Owner | What it's for |
|---|---|---|
| Local | `StreakReminder` | The daily "you haven't studied yet" nudge. No server, no token, no identifier. |
| Remote (FCM) | `PushService` | Server-initiated messages — announcements, campaigns. |
| Remote (OneSignal) | `PushService` | The same job as FCM. Both are wired; pick one to actually send with. |

### The streak reminder is deliberately local

Everything it needs — the streak, the time zone, the wall-clock hour — is on the device
already. A server would need all three plus an identifier to join them, which is three
things this app avoids. It also works offline, which the rest of the app promises.

Scheduling is a **sliding one-week plan of one-shot triggers**, not a repeating trigger:
iOS can't skip a single occurrence of a repeat, and skipping is the whole feature. Today
is included only if it is still winnable — not already studied, and the hour not yet
past — so the reminder can't fire at someone who is already done. `reschedule` runs on
every `reloadStreak` and after every `StudyDay.record`, which is what keeps that true.
`StreakReminderTests` pins the planner.

### Asking is a two-step, and that is not decoration

**iOS raises the system permission alert once per install, ever.** A "Don't Allow" is
permanent and only the Settings app can undo it. So the alert is never spent on a guess:

1. A **soft ask** in the app's own UI (`NotificationOptInCard`) explains the offer.
2. Only a **yes** calls `requestAuthorization`. A "not now" reaches iOS not at all.

`NotificationOptIn` is the shared policy so the two callers can't both fire in the same
week. It stays silent when the reminder is already on, when the status is `.denied`
(a yes would have nowhere to go), and for `askAgainAfter` (60 days) after any ask.

| Trigger | Where |
|---|---|
| Last intro card (`Intro.Card.reminders`) | after the tour has shown what there is to come back to |
| Streak reaches `streakThreshold` (7) | `TodayView.reloadStreak` — the run you're *on*, never `best` |

Turning the reminder **off** in Settings raises a confirmation. Not a dark pattern: the
default action is still "Turn off", and the thing it says — it stays quiet on days you've
already studied — is exactly what someone reacting to one badly-timed alert doesn't know.

| Event | Params |
|---|---|
| `notification_opt_in` | `source` (`intro`/`streak`), `accepted`, `streak` |
| `notification_permission` | `granted` |
| `notification_opened` | `kind` (`streak_reminder`/`push`) |
| `streak_reminder` | `on`, `hour` |
| `streak_reminder_hour` | `hour` |
| `streak_reminder_kept` | — |
| `push_registered` | — |
| `push_register_failed` | `error` |
| `fcm_token` | `present` — **never the token itself** |

### Running FCM and OneSignal together

Both swizzle `UIApplicationDelegate` by default and both want the APNs device token and
`UNUserNotificationCenter.delegate`. Left alone they race, and the loser goes silent with
no error — noticed weeks later as "a campaign went out and nobody got it".

`PushService` is the single owner, which is what makes coexistence safe:

- `FirebaseAppDelegateProxyEnabled` is `NO` in **both** Info.plists.
- `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` forwards
  the token, and `PushService.didRegister` hands it to each SDK by name. Those delegate
  methods are load-bearing, not boilerplate — delete them and FCM never learns the token.
- `UNUserNotificationCenter.delegate` is set once, to `PushService.shared`.

If one provider is ever dropped, delete its branch rather than re-enabling the proxy.

**The FCM registration token is a persistent install-scoped identifier the app itself
handles** — a stronger claim than the Installation ID App Check already carries, because
push only works if something stores it. It is never logged and never written into
`Survey`. See `CLAUDE.md`'s identifier rule.

### Not done yet

- `OneSignalAppID` is **empty** in both Info.plists. `PushService` skips OneSignal
  entirely while it is, which is the honest behaviour for "not configured".
- An **APNs Auth Key** must be uploaded to Firebase *and* OneSignal.
- **Push Notifications capability** must be enabled on both App IDs in the developer
  portal — `aps-environment` is in both entitlements files, so signing fails without it.
- No **Notification Service Extension** target. OneSignal needs one for confirmed
  delivery and rich media; basic push works without it.
- App Store privacy labels don't yet declare anything push-related.
