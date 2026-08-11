# 09 — Intro tour & surveys

The first-launch flow, and the only place this app writes to a server.

## Why one surface does two jobs

The app had no onboarding at all: `RootView` went straight into the `TabView` on
Today. That left three things undiscovered — the Kana tab is free in full, a
lesson has four untested practice modes before the scored ladder, and the same
deck appears on the Lock Screen and Watch — and one thing unasked: whether the
learner can read kana at all, which lesson 1 rung 1 assumes.

So the intro is a **feature tour that also asks three questions**. A question
that visibly configures the feature you were just shown reads as setup rather
than data collection, which is the only honest way to run a survey at first
launch.

## Presentation

`RootView` presents `IntroView` as a `.fullScreenCover`, gated by
`Pref.introAnswered`. Two structural constraints:

- **The cover is attached outside `.id(appLanguage)`.** `RootView.swift` keys
  the whole tab tree on the app language so a language switch rebuilds it
  instantly (see `07-ux-ui.md`); a cover inside that would be torn down
  mid-onboarding.
- **The intro never writes `Pref.appLanguage`** for the same reason. The
  *meanings* language (`Pref.translationLanguage`) is the one it sets, and that
  is the setting nobody discovers on their own anyway.

Paging is `cardPager` over a `SwipeCard` deck with `CardStackPeek` — not
`TabView(.page)` — so the first swipe a learner ever makes is the same gesture
Today, Flashcards, Train and Kana Swipe all want. The tour teaches the app's one
navigation idiom while explaining the app. Paging is **clamped, not wrapped**: a
forward swipe off card 5 finishes, exactly as the button does.

## The five cards

| # | Teaches | Asks | Field |
|---|---|---|---|
| 1 | Card anatomy (kanji/kana/romaji/translation — the four `CardOptionsBar` toggles) and tap-to-hear, on a real lesson-1 word | — (sets the meanings language) | `vocab_language` |
| 2 | Kana is free in full: chart, quizzes, and drawing a kana for a stroke-scored verdict | Do you read kana already? | `knows_kana` |
| 3 | The four Learn modes, tap-to-preview | — | — |
| 4 | The Challenge ladder: 10 questions a rung, 80% to pass, up to 3 stars, pass one and the next opens | Studied Minna no Nihongo before? | `textbook_lesson` |
| 5 | Today deals exactly the next rung's words; same deck on Lock Screen, Home Screen, Watch | Why are you learning? | `goal` |

Every sample on every card is built from `VocabStore.lesson(1, language).entries`
— never a hardcoded word — so the tour shows what lesson 1 will actually show, in
the learner's language, and can't drift out of sync with a data regeneration.

Card 1 deliberately does **not** use `entries.first`: わたし is kana-only
(`displaysKanji == false`), so a card built on it would teach three fields where
`CardOptionsBar` toggles four. It takes the first lesson-1 entry carrying a
distinct kanji.

**No pricing, premium or free-lesson limit is mentioned anywhere in the five
cards.** A deliberate product decision, not an omission. Consequence: a free
user's first paywall encounter is passing lesson 3's last rung and finding lesson
8 locked (`Gating.freeLessonLimit = 7`).

### Card 3 — tap to preview

Four chips in `SelectModeView`'s shallow→deep order, each swapping a full-size
static vignette below: `VocabRow`s, a `SwipeCard` face with a `SwipeStamp` hint,
Train's two chips (`TrainModel.optionCount` is 2), and Learn's assembled reading
over a tile grid. Vocab List is preselected so the card is never an empty frame.

Two rules that aren't obvious:

- **The samples are static.** Instantiating `TrainModel`/`LearnModel` or the real
  mode views would drag in gating, ad slots and session state, and would start
  recording results from inside a tour.
- **They are not draggable.** A horizontal drag would fight `cardPager`'s page
  turn. Taps only — tapping a sample speaks the word through `Pronouncer`.

The chip titles, subtitles and SF Symbols are the *same* strings the real mode
rows use, so the tour teaches labels the learner meets again a tap later, and
none of them needed translating.

### Card 4's rung mockup

`IntroChallengeRungs` models three states explicitly, mirroring
`ChallengeRowState`: rung 1 passed 3★, rung 2 **open** (numbered, three empty
stars, no padlock), rung 3 locked behind it.

Inferring "locked" from "has no stars" is the tempting shortcut and it's wrong —
an unattempted rung is *open*. Getting it wrong draws a padlock on rung 3 with
rung 2 cleared above it, contradicting `ChallengeResult.isUnlocked` and, worse,
contradicting the rule the card's own copy is teaching.

The rungs are rebuilt rather than reusing the real (private) `ChallengeRow`,
which takes a `ChallengeResult` — fabricating `@Model` rows for a mockup would
insert invented history into the CloudKit-backed store.

## The three answers

| Answer | `Pref` | Consumer |
|---|---|---|
| `knows_kana` (`none`/`hiragana`/`both`) | `knowsKana` | `Intro.landingTab(kana:)` — `none` lands on the Kana tab instead of Today |
| `textbook_lesson` (0–50, 0 = never) | `textbookLesson` | **none — recorded only** |
| `goal` | `goal` | **none — recorded only** |

`Intro.KanaLevel.notYet` has raw value `"none"`, not `none`, because the type is
used as an `Optional` and `.none` on an optional means something else entirely.

**Why `textbook_lesson` changes nothing.** The obvious use — start a returning
learner further up the ladder — was considered and rejected. Seeding
`ChallengeResult` rows would push invented history to every device the learner
owns through CloudKit, and inflate `ChallengeResult.totalPassed`, which gates the
rating prompt. A `studyLesson()` floor was the safer variant and still wasn't
worth changing the one derivation Today depends on. It stays a recorded answer.

The two record-only answers exist so a later survey submission can be segmented
by prior experience and motive: this app ships **no user identifier of any kind**,
so there is no key to join a second submission back on, and denormalising the
answers onto it is the substitute.

## Firestore — the one server write

`nihongo/Survey.swift`. Everything else in this app is on-device or in the user's
own iCloud; a survey answer is content someone chose to send us, so it goes
somewhere readable.

### `survey_intro`

One document per **completed** run. Skips and partial runs write nothing —
`IntroAnswers.submission(vocabLanguage:appLanguage:)` returns `nil` unless all
three answers are present, because the schema is closed and a half-answered row
can't be told from a deliberate `0` after the fact. Drop-off is counted in
Analytics instead.

Eleven fields, snake_case to match the Analytics param convention rather than the
camelCase `Pref` keys — the two datasets get read side by side:
`knows_kana`, `textbook_lesson`, `goal`, `vocab_language`, `app_language`,
`app_version`, `os`, `platform`, `debug`, `v`, `at`.

`debug` is true for a Debug build. It exists because `Survey` deliberately
doesn't honour the analytics opt-out (below), so development runs write real rows
into the same collection as real users — this is what filters them out. Note the
rules' `hasOnly`/`hasAll` closes the field set, so **adding or removing a field
here means re-publishing the rules, or every write starts failing.**

`at` is `FieldValue.serverTimestamp()`: device clocks lie, and Firestore's
offline queue can land a write hours after the tap that made it.

### Rules (`firestore.rules`)

Create-only. `allow read, update, delete: if false` — denying update/delete
matters as much as denying read, since auto-IDs are unguessable but not secret
and "write-only" must not mean "may overwrite". Reading results is the project
owner's job via the console or a service account, both of which bypass rules, so
denying `read` costs nothing operationally.

`hasOnly` + `hasAll` close the field set to exactly those eleven keys, and the enum
checks on `knows_kana`/`goal`/`platform` mean a client-side typo can't silently
invent a sixth `goal` value that splits the data at analysis time.

The file is declared in `firebase.json` (`"firestore": { "rules": "firestore.rules" }`),
so it deploys from the repo (`firebase deploy --only firestore:rules`) rather than only
by pasting into the console Rules tab — which matters because the field set is closed and
a schema change *must* ship with a rules change.

**The Rules Playground can't verify this ruleset.** It makes you supply `at` as a
literal timestamp, which won't equal the `request.time` it generates, so a
`create` simulation fails on that clause even though a real write passes. Comment
that line out to exercise the rest, or test with a real build.

### App Check — who may write

There is no Firebase Auth: no accounts, and deliberately no identifier (the app
ships without ATT and `PrivacyInfo.xcprivacy` declares no collected
identifiers). Anonymous Auth would mint a persistent UID per install and undo
that. So the rules bound *what* can be written and **App Check** bounds *who*:

- `SurveyAppCheckFactory` in `Ads/AppBootstrap.swift`, installed **before**
  `FirebaseApp.configure()` — the factory is consulted as Firebase starts.
- Release uses `AppAttestProvider`; DEBUG uses `AppCheckDebugProvider`, because
  App Attest cannot run on the Simulator. Register the token DEBUG prints under
  App Check → Apps → Manage debug tokens.
- `nihongo.entitlements` sets `appattest-environment` to **`production`**, not
  Xcode's default `development`. Debug and Release share one entitlements file,
  so only one value ships, and it has to be the one TestFlight needs. Nothing is
  lost locally because DEBUG doesn't use App Attest at all. **Re-adding the App
  Attest capability in Xcode silently resets this to `development`**, and the
  failure mode — writes rejected only in TestFlight — is miserable to debug.
- Enforcement is a console toggle (App Check → APIs → Cloud Firestore). Until
  it's on, anything that can reach the endpoint can write.

### Why `Survey` ignores the analytics opt-out

Unlike everything in `Track`, `Survey.submit` is **not** gated on
`Pref.analyticsExcluded` or `#if DEBUG`. That switch governs passive telemetry —
events the user never asked to send. A survey answer is the opposite, and
silently discarding it would be the worse betrayal. Gating DEBUG would also make
the write path untestable outside TestFlight.

Consequence: development submissions land in the same collection as real ones and
nothing marks them.

### Reading the results

The console's Data tab shows every document, unsampled — but it's a document
browser, not a table: one document at a time, no aggregation, no CSV export. Fine
for reading answers, painful for computing anything. A local script with a
service account is the practical path. The Stream-to-BigQuery extension would be
the dashboard answer but needs the **Blaze** plan; the project is on Spark, where
Firestore's free tier is far beyond survey volume.

## Analytics

Via `Track` only (see `08-analytics.md`). `intro_card` (`card`) per card shown,
`intro_skip` (`card`) on skip, `intro_mode_peek` (`mode`) when a card-3 chip is
tapped, `intro_done` with all three answers, `survey_failed` (`collection`) when
a write is rejected.

`intro_mode_peek` reports the canonical English `titleKey`, not the localized
title — a param whose value shifts with device language can't be grouped in a
dashboard. `intro_done` always carries all three keys, using `"unanswered"` /
`-1` sentinels, so a funnel can count "asked but not answered" rather than
finding a param missing.

A rules rejection surfaces in `addDocument`'s completion handler, not at the call
site — offline persistence applies the write locally first and only learns it was
refused on flush. Swallowing that would make a misconfigured rule look exactly
like success, hence `survey_failed` plus an unconditional `print`.

## Related fix: the meanings-language default

Shipped alongside, and card 1 depends on it. `Pref.appLanguage` defaulted to
`L.deviceDefault` but `Pref.translationLanguage` defaulted to
`VocabStore.defaultLanguage` — literally `"en"` — at every call site, so a
Vietnamese user got a Vietnamese interface with English word meanings until they
found Settings. `VocabStore.deviceDefaultLanguage` now forwards to
`L.deviceDefault` for that first-launch default.

`VocabStore.defaultLanguage` deliberately stays `"en"`: it is also the
argument-less fallback for `lessons(_:)`/`allVocab(_:)`/`lesson(_:_:)` and the
missing-translation fallback, and several tests depend on that meaning.

## Localization

27 new keys × 17 languages. Card 3's eight strings and card 4's captions were
reused from `SelectModeView`/`ChallengeRow` rather than re-added. Four carry
format placeholders and one escapes a literal percent (`%%`) — see
`LocalizationTests.formatPlaceholdersSurviveTranslation`, which counts
placeholders per language. Run `check-i18n-parity` after any string change here.

Body copy is the expensive part: German and Vietnamese run long, Burmese needs
line height. Nothing in the intro uses a fixed-height frame or a fixed point
size for that reason.

## What's not here yet

- **NPS.** Designed but unbuilt. `RatingPrompt.shouldAsk` is premium-only
  (`isPremium && passed && passedCount >= 15`), so the app collects no sentiment
  from free users — who are the entire pre-purchase funnel. The intended shape is
  NPS for free users at a rung threshold with its own `Pref` flag, since
  `Pref.ratingAsked` is a single boolean the two instruments would fight over.
  `Survey` is built to take a second collection.
