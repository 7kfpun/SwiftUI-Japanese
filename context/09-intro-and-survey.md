# 09 — Intro tour & surveys

The first-launch flow, and the only place this app writes to a server.

## Why one surface does two jobs

The app had no onboarding at all: `RootView` went straight into the `TabView` on
Today. That left three things undiscovered — the Kana tab is free in full, a
lesson has five untested practice modes before the scored ladder, and the same
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
Today, Practice and Kana Swipe all want. The tour teaches the app's one
navigation idiom while explaining the app. Paging is **clamped, not wrapped**: a
forward swipe off card 5 finishes, exactly as the button does.

## The six cards

| # | Teaches | Asks | Field |
|---|---|---|---|
| 1 | Card anatomy (kanji/kana/romaji/translation — the four `CardOptionsBar` toggles) and tap-to-hear, on a real lesson-1 word | — (sets the meanings language) | `vocab_language` |
| 2 | Kana is free in full: chart, quizzes, and drawing a kana for a stroke-scored verdict | Do you read kana already? | `knows_kana` |
| 3 | The four Learn modes, tap-to-preview | — | — |
| 4 | The Challenge ladder: 10 questions a rung, 80% to pass, up to 3 stars, pass one and the next opens | Studied Minna no Nihongo before? | `textbook_lesson` |
| 5 | Today deals exactly the next rung's words; same deck on Lock Screen, Home Screen, Watch | Why are you learning? | `goal` |
| 6 | Daily reminders — what arrives, and that nothing does once you're done | Remind me / Not now | — (see below) |

**Card 4 also carries the earned unlock** — "three-star every challenge in lessons 1–5
and all of Beginning 1 / N5 unlocks, free" — in a tinted panel rather than another grey
caption. It sits on the card that explains the stars, which is the one moment the reader
already knows what three stars costs, and *before* anyone has met a paywall.

**Card 6 answers rather than pages.** It has no Next button and its forward swipe is
blocked: iOS raises the system permission alert once per install and a refusal is
permanent, so a soft ask comes first and only a yes reaches
`UNUserNotificationCenter`. A third way off the card would let someone finish the tour
without answering, leaving the ask to fire again later as if never shown. See
`NotificationOptIn`, whose other caller is a streak reaching seven days.

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
6 locked (`Gating.freeLessonLimit = 5`).

### Card 3 — tap to preview

Four chips in `SelectModeView`'s shallow→deep order, each swapping a full-size
static vignette below: `VocabRow`s, a `SwipeCard` face with a `SwipeStamp` hint,
Practice's two chips (`PracticeModel.optionCount` is 2), and Learn's assembled reading
over a tile grid. Vocab List is preselected so the card is never an empty frame.

Two rules that aren't obvious:

- **The samples are static.** Instantiating `PracticeModel`/`LearnModel` or the real
  mode views would drag in gating, ad slots and session state, and would start
  recording results from inside a tour.
- **They are not draggable.** A horizontal drag would fight `cardPager`'s page
  turn. Taps only — tapping a sample speaks the word through `Pronouncer`.

The chip titles, subtitles and SF Symbols are the *same* strings the real mode
rows use, so the tour teaches labels the learner meets again a tap later, and
none of them needed translating.

### Card 4's rung mockup

`IntroChallengeRungs` models three states explicitly, mirroring the real ladder's
chips: rung 1 passed 3★, rung 2 **open** (numbered, three empty stars, no
padlock), rung 3 locked behind it.

Inferring "locked" from "has no stars" is the tempting shortcut and it's wrong —
an unattempted rung is *open*. Getting it wrong draws a padlock on rung 3 with
rung 2 cleared above it, contradicting `ChallengeResult.isUnlocked` and, worse,
contradicting the rule the card's own copy is teaching.

The rungs are rebuilt rather than reusing the real ladder's chips, which read a
`ChallengeResult` — fabricating `@Model` rows for a mockup would insert invented
history into the CloudKit-backed store.

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

## Directus — the one server write

`nihongo/Survey.swift`. Everything else in this app is on-device or in the user's
own iCloud; a survey answer is content someone chose to send us, so it goes
somewhere readable.

Until the Directus move the rows went to Firestore (`survey_*` collections, closed by
`firestore.rules` and attested with App Check). `firestore.rules` and the App Check
setup in `Ads/AppBootstrap.swift` are still in the repo, but `Survey` no longer writes
to Firestore at all.

### Where rows go

`POST https://cms.wahthefox.com/items/<collection>` with a JSON body and
`Authorization: Bearer <token>` — `Survey.Directus.createRequest`. Three collections:

| Collection | Row |
|---|---|
| `japanese_survey_intro` | one per **completed** intro run — the shared context, with this run's three answers winning |
| `japanese_survey_rating` | one per star tap — context + `stars` (1…5) |
| `japanese_survey_feedback` | one per feedback sheet — context + `kind`, `area`, `message`, `email`, `source`, `stars`, `lesson`, `item` |

Every row carries the identical `Survey.Context` map (`Survey.Context.keys`), snake_case
to match the Analytics param convention rather than the camelCase `Pref` keys — the two
datasets get read side by side. Directus adds `id`, `date_created` (the server-stamped
time, which replaced Firestore's `at`) and `archived`, which the server presets to
`false` and is the soft-delete flag. The app never sends any of those three.

Skips and partial intro runs write nothing — `IntroAnswers.submission(...)` returns
`nil` unless all three answers are present — and drop-off is counted in Analytics
instead.

`debug` is true for a Debug build. It exists because `Survey` deliberately doesn't
honour the analytics opt-out (below), so development runs write real rows into the
same collection as real users — this is what filters them out.

**Adding or removing a field means adding or removing the Directus column first**, or
every write fails. `SurveyTests.contextKeysMatchTheDirectusColumns` and its siblings
transcribe the column lists and compare.

### The token — who may write

A static Directus token for the *Japanese App* role, whose only policy is `create` on
the three collections: no read, update or delete. It is read from the git-ignored
`nihongo/Secrets.plist` key `directusToken` (template: `config/Secrets.example.plist`);
Xcode Cloud writes that file from `MINNA_SECRETS_PLIST`, and `ci_post_clone.sh` refuses
to archive without the key. No token bundled — a fresh clone — makes every submission a
silent no-op; Diagnostics shows *Survey token: bundled / missing*.

The token ships inside the binary, so treat it as extractable: the create-only scope is
what keeps it harmless, not secrecy. The worst a leaked token can do is append rows.
Unlike the Firestore rules, nothing on the app side validates *values* server-side
unless the Directus fields themselves carry validation.

Requests use an ephemeral `URLSession` with `waitsForConnectivity`, which stands in for
Firestore's offline queue only while the app is running — a submission made offline
and followed by the app being killed is lost.

### Why `Survey` ignores the analytics opt-out

Unlike everything in `Track`, `Survey.submit` is **not** gated on
`Pref.analyticsExcluded` or `#if DEBUG`. That switch governs passive telemetry —
events the user never asked to send. A survey answer is the opposite, and
silently discarding it would be the worse betrayal. Gating DEBUG would also make
the write path untestable outside TestFlight.

Consequence: development submissions land in the same collection as real ones and
nothing marks them.

### Reading the results

In the Directus admin at `https://cms.wahthefox.com`, as an account with read access
(the app's token has none). Filter `debug = false` and `archived = false`; archiving a
row is the soft delete. Older answers sent before the Directus move stay in the
Firestore console's `survey_*` collections and are not migrated.

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

A Directus rejection arrives as a non-2xx status, not a thrown error — URLSession only
throws for transport failures. Both count as a failure: swallowing either would make a
missing column or a revoked token look exactly like success, hence `survey_failed`
(`collection` is the Directus collection name) plus an unconditional `print` that
includes Directus's own error message.

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

27 new keys × 17 languages. Card 3's strings and card 4's captions were
reused from `SelectModeView`'s own copy rather than re-added. Four carry
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
