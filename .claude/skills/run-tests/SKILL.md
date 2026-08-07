---
name: run-tests
description: Run the nihongo unit test suite via xcodebuild, the only way this project verifies Swift changes from the command line. Use after any change to nihongo/*.swift or nihongoTests/*.swift, or whenever asked to "run the tests" / "check if this builds" / "verify nothing broke". Never build or launch the full app — that is a hard standing rule for this project; the user builds/runs in Xcode themselves.
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

Run from the repo root. That destination id is the project's pinned iPhone 17
Pro (iOS 26.5) simulator — the deployment target is iOS 26.5 and older
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

## Hard rule: never build or launch the app itself

**Never** run `xcodebuild build` (or `test` without `-only-testing:...`
narrowed to `nihongoTests`) on the full `nihongo` app scheme, and **never**
`xcrun simctl install`/`launch` it. This project's standing rule is that the
user builds and runs the app themselves in Xcode — your job from the CLI is
tests only. If a change needs eyes-on verification beyond what a unit test can
express, say so and let the user check it in Xcode.

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

## Expected baseline

At last count: 21 unit tests across `DataTests`, `TextTests`, `KanaTests`,
`SearchTests`, `LearnTests`, `FlashcardTests`, `QuizTests`, `PremiumTests`,
`AdConfigTests`, `KanaSketchTests`, `TodayTests`, `LegalTests`,
`LocalizationTests`, `PersistenceTests` (see `nihongoTests/nihongoTests.swift`).
All green is the bar — a new failure after your change means something in
that area regressed, not that the test is wrong (double-check before editing
a test's expectation).
