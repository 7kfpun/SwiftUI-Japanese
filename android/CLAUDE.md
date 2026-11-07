# Android — working rules

Kotlin + Compose port of the iOS app. **The iOS app is the spec**: port behaviour, wording
(`nihongo/UIStrings.json`, all 19 languages) and analytics event names from the Swift files.
Read the root `CLAUDE.md` and `context/README.md` first; this file is what changes on Android.
Setup, commands and config are in [`README.md`](README.md).

## Decisions (Linear FOX-146, final)

- Package `com.kfpun.japanesedaily`; code in `android/` at the repo root; iOS files stay put.
- **Minna only in v1**, behind the `minna` product flavour (dimension `course`); JLPT later.
- Kotlin, Jetpack Compose, Material 3, Glance widget; minSdk 26, compileSdk/targetSdk 36, JDK 17.
- **Progress on the device only, no cloud backup**: no Auto Backup, no sign-in. Keep
  `allowBackup="false"` and `data_extraction_rules.xml` excluding every domain.
- Firebase project `kf-nihongo`, a **new** Android app (not the old `com.kfpun.nihongo` one).
- No remote push in v1. AdMob is non-personalized, after UMP consent.
- Noto Serif JP and KanjiStrokeOrders are bundled. No Wear OS.

## Hard rules

- **Never build a release, upload to Play, sign, or deploy unless the user asked.** No
  keystore is ever created, committed or printed. Never run `./gradlew --stop` (shared home).
- **PUBLIC repo:** never commit keys, tokens, keystores, `google-services.json`, service
  accounts or `secrets.properties`. Tests use fixtures and the example config.
- Commit or push only when told; messages `type: lowercase description`, no mention of Claude.
- Remove trailing whitespace from every line you touch.
- Verify with `cd android && ./gradlew ktlintCheck lint test assembleDebug`.

## Generated inputs — read in place, never copy or hand-edit

`nihongo/Resources/{MinnaData.json,KanaChart.json,audio/}` come from
`scripts/build-minna-data.py`; the `minna` flavour packages that folder as its assets. Strings
come from `nihongo/UIStrings.json` (FOX-150 generates `res/values*/strings.xml` from it). Edit
the generators or the source JSON, never the output.

## Rules carried over from the iOS CLAUDE.md

- **Strings: the `L.t` rule.** Every user-facing string is a generated string resource with an
  entry in `UIStrings.json` for all 19 languages, never a literal in Kotlin. Until FOX-150
  lands, `res/values/strings.xml` holds only what the scaffold needs. Add a string by adding it
  to `UIStrings.json`, not by hand to `strings.xml`.
- **Typography and colour: `Theme` only** (`ui/Theme.kt` and what FOX-149 grows it into). No
  literal fonts or colours at call sites. Green and red are exclusive to answer feedback;
  selection is an accent *border*, never a fill. Dynamic type: `sp` text, no fixed-height
  frames (German, Vietnamese and Burmese run long). Cards sit lighter than the screen in both
  appearances.
- **Analytics: `Track` only** (FOX-160); nothing else imports Firebase Analytics. Event names
  and param keys are `lower_snake_case` and match the iOS names.
- **Server writes: `Survey` only** (FOX-157), the app's only server write, to Directus
  (`DIRECTUS_URL`, create-only `DIRECTUS_TOKEN`). Add the Directus column before the app
  sends a field. An empty or placeholder token means submissions are a silent no-op.
- **No persistent identifier of the app's own**: no advertising id, no minted install id, no
  Android ID in anything this code writes (above all `Survey`). Device characteristics (model,
  OS, language, region) are fine. Google SDKs carry their own install-scoped ids, which is the
  accepted boundary, as on iOS.
- **Day stamps use the `StudyDay` calendar** (Gregorian numbering in the user's time zone),
  never the default locale calendar: a Buddhist-calendar region would reinterpret every
  stored `yyyymmdd`.
- **Never fabricate progress.** No seeded results; they inflate `totalPassed`, which gates the
  rating prompt.
- **The rating flow is not a rating gate.**

## Product facts copy must not get wrong

Check `nihongo/Store.swift` and `nihongo/Challenge.swift` before writing a claim. In short:

- Lessons 1–5 are free (`Gating.freeLessonLimit`), plus two documented ways past that: three
  stars on every challenge of lessons 1–5 opens the first band, and Read along's "Japanese +
  meaning" previews 7 words. No others. Do not state a free-lesson count in store or website
  copy, and never hardcode a lesson count in UI copy: interpolate it.
- Five practice modes per lesson plus the Challenge ladder; Flashcards is a browse-only deck.
- **All audio is synthesised (VOICEVOX for Minna), never native-speaker recordings** — never
  claim "native audio". VOICEVOX needs a visible credit.
- Subscriptions: 1, 3, 6, 12 months + lifetime; product ids are case-sensitive and immutable.
  Minna uses uppercase `3M`/`6M`/`12M` and `premium.lifetime` on iOS; Play product ids are
  FOX-158's to create.
- No third-party trademark (the textbook name) in any store field.

## Layout

`app/src/main/kotlin/com/kfpun/japanesedaily/` — `MainActivity`, `ui/` (`Theme.kt`, the
5-tab `AppScaffold`). Tabs: Today, Kana, Lessons, Progress, Settings, in the iOS order, with
Material Symbols icons. Keep shared files (`MainActivity`, navigation, `libs.versions.toml`,
`Theme`) to small additive edits so parallel tickets merge cleanly.

Design system (FOX-149): `ui/Theme.kt` (colour tokens, type scale, faces), `ui/Faces.kt` (the
font-follows-script rule: `KanaForm`/`VocabForm.isJapanese`), `ui/components/` (`SwipeCard`,
`CardStackPeek`, `cardPager`, `cardSwipe`, `QuizOptionButton`, `SwipeOptionChip`, `OptionGrid`,
`EmptyStatePanel`, `cardChrome`/`accentPlate`/`selectionBorder`). `AppScaffold(banner = ...)` has the
ad banner slot above the tab bar. Noto Serif JP is in `assets/fonts` (OFL text in `assets/licenses`);
KanjiStrokeOrders is packaged in place from `nihongo/Fonts`. The debug-only catalog
(`src/debug/.../CatalogActivity`) renders every token and component:
`adb shell am start -n com.kfpun.japanesedaily/.catalog.CatalogActivity [--es section tokens|type|cards|options|empty]`.
