---
name: run-tests
description: Run the nihongo unit test suite via xcodebuild, the only way this project verifies Swift changes from the command line. Use after any change to nihongo/*.swift or nihongoTests/*.swift, or whenever asked to "run the tests" / "check if this builds" / "verify nothing broke". Don't build the full app to verify your own work — the user checks it in Xcode; a build they explicitly ask for (archive, upload, screenshots) is allowed and confirmed first.
when_to_use: run tests, run the test suite, verify tests pass, check nothing broke, xcodebuild test
allowed-tools: Bash
---

# Run the nihongo test suite

## The exact command

```sh
xcodebuild test -scheme nihongo -project nihongo.xcodeproj \
  -destination "id=5250BD7F-D8E3-484D-A209-23CCD0523399" \
  -only-testing:nihongoTests
```

Run from the repo root. That destination id is the pinned iPhone 17 Pro
(iOS 26.5) simulator **on this machine** — anywhere else (CI, another Mac) it
won't exist; substitute `-destination "platform=iOS Simulator,name=iPhone 17 Pro"`.
The deployment target is iOS 26.5 and older
simulators (e.g. iPhone 15 / iOS 17.4) are *ineligible* for this scheme, so
don't substitute a different `-destination` without checking
`xcodebuild -showdestinations -scheme nihongo -project nihongo.xcodeproj`
first.

`-only-testing:nihongoTests` scopes to the unit test target
(`nihongoTests/nihongoTests.swift`) and skips the slower UI tests
(`nihongoUITests`) — that's normally what you want for a quick "did I break
anything" check. To scope further to one test or suite:

```sh
xcodebuild test -scheme nihongo -project nihongo.xcodeproj \
  -destination "id=5250BD7F-D8E3-484D-A209-23CCD0523399" \
  -only-testing:nihongoTests/KanaTests
```

Pipe through `grep` to keep the signal readable — the raw log is huge:

```sh
xcodebuild test -scheme nihongo -project nihongo.xcodeproj \
  -destination "id=5250BD7F-D8E3-484D-A209-23CCD0523399" \
  -only-testing:nihongoTests 2>&1 | grep -E "\*\* TEST (SUCCEEDED|FAILED)|error:|Mach error"
```

Add whatever test-name substrings are relevant to what you just changed to
the `grep -E` pattern (e.g. `|FlashcardTests|GatingTests`) so a failure in the
area you touched isn't buried.

## Hard rule: don't build the app to check your own work

`CLAUDE.md`'s first hard rule, repeated here because this is the skill where it
gets broken.

**Never** reach for `xcodebuild build` (or `test` without `-only-testing:...`
narrowed to `nihongoTests`) on the full `nihongo` app scheme, and never
`xcrun simctl install`/`launch`, as a way of verifying a change. Your job from
the CLI is tests only. If a change needs eyes-on verification beyond what a unit
test can express, say so and let the user check it in Xcode.

A build the **user explicitly asks for** — an archive, an upload, App Store
screenshots — is a different thing and is allowed; confirm what will run first.
The rule here is about initiative, not capability.

## If it flakes: Mach error -308

Occasionally the simulator throws a transient `Mach error -308` (or the test
run just fails to launch) with no code-related cause. **First move: just
re-run the exact same `xcodebuild test` command.** Simulator flakes are often
one-shot.

Only if a plain retry *also* fails, escalate to resetting the simulator —
`xcrun simctl shutdown all` is disruptive (it kills every booted simulator,
including any the user has open), so treat it as a last resort, not the
default reflex:

```sh
xcrun simctl shutdown all 2>/dev/null
xcrun simctl boot 5250BD7F-D8E3-484D-A209-23CCD0523399 2>/dev/null
xcrun simctl bootstatus 5250BD7F-D8E3-484D-A209-23CCD0523399 -b
# then re-run the xcodebuild test command above
```

## Expected baseline: all green, and no total quoted on purpose

**The bar is "every test passes", not a number.** This section used to quote a
test count, and by the time anyone read it the suite had roughly quadrupled —
`context/README.md` says a stale number is the common documentation failure, and
a wrong baseline is worse than none because it invites "close enough, must be
fine". If you want the count, measure it:

```sh
grep -c '@Test' nihongoTests/nihongoTests.swift
grep -nE '^struct |^@MainActor$|^final class ' nihongoTests/nihongoTests.swift
```

Everything lives in the single file `nihongoTests/nihongoTests.swift`, as one
`struct` per suite. The suites, in file order:

`DataTests`, `TextTests`, `KanaTests`, `SearchTests`, `LearnTests`,
`FlashcardTests`, `TrainTests`, `PremiumTests`, `AdConfigTests`,
`KanaSketchTests`, `TodayTests`, `SurveyTests`, `FeedbackTests`, `LegalTests`,
`LocalizationTests`, `PersistenceTests`, `ChallengeTests`,
`ChallengeResultTests`, `IntroTests`.

There is **no `QuizTests`** — Quiz and Listening became the Challenge ladder and
`TrainModel` (see `CLAUDE.md`, "Product facts"). Grep the suite name out of the
file before you scope to it: a `-only-testing:` filter naming a suite that doesn't
exist can pass vacuously, which reads as "my change is fine" when nothing ran.

A new failure after your change means something in that area regressed, not that
the test is wrong — several of these suites are deliberate canaries and are
supposed to be annoying:

- `DataTests.generatedDataShape` pins the exact entry and clip counts (read the
  current numbers from the test, not from here). If it
  fails, the bundled data changed — see the `refresh-data` skill, and update the
  numbers deliberately rather than relaxing the assertion.
- `LocalizationTests` fails on an English-only string, a lost `%@`, or an
  unescaped `%` — most of its tests are that check — see the
  `check-i18n-parity` skill.
- `SurveyTests.contextKeysMatchThePublishedRules` fails when `Survey.Context`
  and `firestore.rules` disagree. That is not a test to edit alone: it means the
  rules must be republished with the build — see the `deploy-firestore-rules`
  skill.
