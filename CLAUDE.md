# Japanese Daily 每日日本語 — working rules

Native SwiftUI + SwiftData iOS app teaching the Minna no Nihongo vocabulary (50
lessons, 2089 words) and the kana syllabaries, in 17 UI languages, with a widget
and an Apple Watch app. `context/` documents how it works — read `context/README.md`
first and follow its index; it is kept current and is the fastest way in.

## Hard rules

- **Never build or launch the app on your own initiative.** Not `xcodebuild build`, not
  `simctl install`/`launch`. Routine verification from the CLI is the `run-tests` skill
  and nothing else; if a change needs eyes on the running app, say so and let the user
  check it in Xcode.

  **Building *is* allowed when the user explicitly asks for it** — `fastlane ios release`,
  an archive, an upload, capturing App Store screenshots. "Explicitly" means they named
  the build, the archive or the upload. It is never implied by a request to change code,
  fix a bug, or update the store listing.
- **Never create a git commit.** Editing, staging, `git status`/`git diff` are fine.
  When asked for a commit *message*: `type: lowercase description`, and no mention of
  Claude or Claude Code anywhere in it.
- **"Publish to the App Store" means the metadata**, not a binary. It is
  `fastlane ios metadata app:<app>` — description, keywords, promotional text, release
  notes — and that is the whole job unless a build is named. Shipping a binary is a
  separate, explicit request.
- **Confirm before a build, an upload or a submission**, even when asked directly. Say
  what will run and what it will produce, and wait. These cost real time, put an
  artefact in front of App Review, and are awkward to walk back — unlike metadata, which
  is a text field that can be rewritten a minute later.
- **Never publish or deploy anything else without being asked.** `firebase deploy`, App
  Store Connect writes and Firestore rule deploys are outward-facing. Write the change,
  then stop.
- **Remove trailing whitespace** from every line you touch.

## Generated files — never hand-edit

| Generated | From |
|---|---|
| `nihongo/Resources/MinnaData.json`, `KanaChart.json`, `Resources/audio/{vocab,kana}/` | `scripts/build-minna-data.py` ← `minna/` submodule |
| `Apps/jlpt/Resources/JLPTData.json`, `Resources/audio/` | `scripts/build-jlpt-data.py` ← the same submodule's `jlpt/` half |
| `web/**` (except `privacy.html`, `terms.html`) | `scripts/build-web.py` — all copy lives in its `T` dict |
| `fastlane/minna/screenshots/**` | `fastlane/generate_framed_screenshots.py` ← `fastlane/minna/screenshot_raw/` |

## Seams — go through them, don't bypass

- **Analytics: `Track` only** (`nihongo/Ads/AppBootstrap.swift`). Nothing else may
  import `FirebaseAnalytics`. Event names and param keys are `lower_snake_case`.
- **Server writes: `Survey` only** (`nihongo/Survey.swift`), the app's *only* server
  write. Everything else is on-device or in the user's own iCloud.
- **Strings: `L.t(...)` only**, with an entry in `nihongo/UIStrings.json` for **all 17
  languages**. English-only additions fail the suite. Run `check-i18n-parity` after any
  string change. Developer-only surfaces (Diagnostics) are deliberately unlocalised.
- **Typography and colour: `Theme` only.** No literal fonts or colours at call sites.

## Invariants that bite

- **Firestore rules must ship with the app.** `hasOnly`/`hasAll` close each collection's
  field set, so adding a field without republishing `firestore.rules` rejects **every**
  write, visible only as a console line and a `survey_failed` event.
  `SurveyTests.contextKeysMatchThePublishedRules` guards this — keep it passing.
- **The app never mints or sends a persistent identifier of its own.** No IDFA, IDFV,
  vendor UUID or minted install ID in anything *this code* writes — above all `Survey`,
  whose Firestore documents carry no user, session or reply channel. It ships without App
  Tracking Transparency and forces non-personalized ads. Device *characteristics* (model,
  OS, language, region) are fine; anything that joins two rows to one person is not, and
  `Survey.Context.model` is a characteristic precisely because every unit of a model
  returns the same string where `identifierForVendor` would not.

  **The Google SDKs are a separate matter and do carry install-scoped IDs.** Firebase
  Installations (an FID in the keychain) is pulled in by `FirebaseAppCheck` and by
  `FirebaseSessions` under Crashlytics — so it predates, and is not introduced by,
  Firebase Performance, which also consumes it. Analytics keeps its own app-instance ID.
  This is the accepted boundary, not an oversight: the rule governs the app's own data,
  and third-party SDK internals are declared in their own privacy manifests. Don't cite
  this bullet as proof the binary contains no identifier — it doesn't say that.
- **SwiftData is CloudKit-backed** (`iCloud.com.kfpun.nihongo`), so no
  `@Attribute(.unique)` is permitted and every reader must tolerate duplicate rows from
  a sync merge — see `ChallengeResult.better(_:_:)`.
- **A new `@Model` needs its CloudKit schema deployed to Production before release.**
  Running in Xcode only creates it in Development. Ship without pressing *Deploy Schema
  Changes* and the type silently never syncs for App Store users — no crash, no error,
  progress just never leaves the device. `StudyDay` (the streak) is the current one
  awaiting this in **both** containers.
- **Day stamps use `StudyDay.calendar`, never `Calendar.current`.** The region setting
  changes the calendar, and under a Buddhist one today's year component is 2569 — so a
  stored `yyyymmdd` would be reinterpreted, and every recorded day would move. Gregorian
  numbering, the user's time zone.
- **Never fabricate progress.** Seeding `ChallengeResult` rows pushes invented history to
  every device the user owns and inflates `totalPassed`, which gates the rating prompt.
- **The rating flow is not a rating gate.** The App Store forbids conditioning a review
  path on sentiment. The star row is the app's own question, every answer leads
  somewhere, and the App Store page stays reachable from Settings regardless.
- **`Theme.jp`/`jpBold`/`jpStrokes` all have full Latin coverage** — romaji drawn with
  them looks merely *plain*, never broken, which is why several slots sat on the wrong
  face unnoticed. The face follows the content's script at runtime (`KForm.isJapanese`,
  `VForm.isJapanese`), not the screen. `jpStrokes` is functional, not decorative: it is
  the handwriting scoring template.
- **`CardPager` belongs on the card, not the enclosing `ZStack`** — outside it, the peek
  layers fling along with the card and the deck slides as one slab.

## UI rules

- **Green and red are exclusive to answer feedback.** Selection state is a
  `Theme.accent` **border**, never a fill.
- **Dynamic Type everywhere.** No fixed point sizes for text (the two documented
  `Theme.display` slots aside), and no fixed-height frames — 17 languages, and German,
  Vietnamese and Burmese run long.
- Cards sit *lighter* than the screen in both appearances; a `Theme.surface` element on
  a `Theme.surface` card is invisible. Inset panes use `Theme.canvas`.
- **SF Symbols only for anything functional** — icons, controls, list rows, tab items.
  They scale with Dynamic Type, follow the appearance, and render in all 17 languages
  for free, which is the whole reason for the rule.
  The single exception is `nihongo/Illustrations.xcassets`: hand-drawn SVGs from
  [koboyo](https://koboyo.com/icons) (free for commercial use, no attribution) used as
  **empty-state artwork only** — never as an icon, never inside a control. They are
  template-rendered so they take `Theme` colours. Adding one to a control would give up
  every property above; if a screen needs a symbol, it needs an SF Symbol.

## Product facts copy must not get wrong

Each of these was wrong in shipped copy and had to be corrected across 17 languages.
Check `Store.swift` and `Challenge.swift` before writing any user-facing claim.

- **Lessons 1–5 are free** (`Gating.freeLessonLimit = 5`), plus **two documented ways
  past that**, and no others:
  - **Earned:** three stars on *every* challenge of lessons 1–5 opens the whole first
    band free — Minna's "Beginning 1" (to lesson 13), JLPT's "N5" (to 19). Three stars
    means a clean 100% (`Challenge.stars`), so it is a real bar; a pass would be none,
    since the ladder already needs one to advance. `Gating.hasEarnedFirstGroup` decides
    it, `Unlock` carries it, and every `Gating.isLocked` caller must pass
    `earnedFirstGroup` — the parameter defaults to `false` so an un-plumbed gate fails
    *closed*.
  - **Previewed:** on a locked lesson "Play with meanings" reads
    `Gating.freeMeaningPreview` (7) words, then the paywall (`Gating.wordsToRead`).

  Plain "Play all" — Japanese only — stays free on every lesson, and Vocab List itself is
  free everywhere. **Do not state a free-lesson count** in App Store or website copy — the
  product decision is that a visitor assumes it's free and meets the paywall having
  already got value. Still make clear a paid unlock exists.
- **Never hardcode a lesson count in UI copy.** The paywall said "All 50 lessons" in both
  apps, promising 50 of JLPT's 201 on the screen that asks for money. Interpolate
  `Course.current.lessonCount`; `Gating.freeLessonLimit` likewise.
- **Four practice modes** per lesson — Vocab List, Flashcards, Train, Learn — **plus the
  Challenge ladder**. There is no `QuizView.swift`; Quiz and Listening became the ladder
  and `TrainModel`. Kana has five modes, one of which is Listening.
- **All the audio is synthesised, never native-speaker recordings — so never claim
  "native audio"**, whatever the voice. The two courses use different engines:
  - **Minna: VOICEVOX** (neural). `whitecul` is the default for vocab and kana;
    `kenzaki` ships alongside it purely so the Challenge ladder can alternate voices —
    with one voice a listening rung is passable by recognising the waveform rather than
    the word. `Speech.Voice.alternate.suffix` must equal the suffix
    `build-minna-data.py` writes, or `audioURL` silently falls back to the default and
    the ladder stops being a listening test with nothing to notice.
  - **JLPT: `say -v Kyoko`** (macOS, concatenative) — the only voice its dataset ships.
    `audioURL`'s fallback is what makes `.alternate` harmless there.
  - **VOICEVOX requires attribution.** Its characters are licensed for commercial use
    with a visible credit (e.g. `VOICEVOX:WhiteCUL`). Nothing in the app carries one yet;
    Settings → Licenses is where it belongs. Check the current terms before shipping.

  All 2089 Minna words and all 7972 JLPT words have a clip. Live `AVSpeechSynthesizer`
  remains the fallback — it covers bare kana tiles, and any future course shipping no
  clips — so "every word has a clip" is true of *this* data, not a guarantee.
- **Subscriptions sold: 1, 3, 6 months + lifetime.** 12-month is legacy and
  unpurchasable, honoured only for restores. Product IDs are case-sensitive, immutable,
  and unique per *team* forever — a deleted one is reserved and can never be recreated.
  **The two apps' IDs differ on purpose and must not be "aligned":** minna uses uppercase
  `3M`/`6M` (the lowercase ones were burned by the RN app) and `premium.lifetime`; JLPT
  uses lowercase `3m`/`6m` and `premium.forever` (its `premium.lifetime` was deleted
  during setup and is gone for good). `Course.swift` is the record of what App Store
  Connect actually holds — `PremiumTests.jlptProductIDsMatchAppStoreConnect` pins it.
- **No third-party trademark in the App Store name or subtitle** (Guideline 5.2). The
  textbook name stays out of every user-visible store field; the website keeps it to the
  meta description and one FAQ answer.

## Documentation

`context/` describes source-of-truth files, not the other way around. When a doc and the
code disagree, **the code is right — fix the doc.** A stale *number* is the common
failure; a stale *absence* is the dangerous one — a persistence key that no longer
exists, a mode merged into another, a per-mode trial that became one whole-lesson rule.
When rewriting a doc, read the code first and the existing doc second: a rewrite that
paraphrases a confidently wrong doc is worse than no rewrite.
