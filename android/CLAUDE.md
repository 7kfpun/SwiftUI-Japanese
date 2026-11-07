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
come from `nihongo/UIStrings.json`, generated into `res/values*/strings.xml` (see Strings below).
Edit the generators or the source JSON, never the output.

## Rules carried over from the iOS CLAUDE.md

- **Strings: the `L.t` rule.** Every user-facing string is a generated string resource with an
  entry in `UIStrings.json` for all 19 languages, never a literal in Kotlin. Add a string by
  adding it to `UIStrings.json`, then run `python3 scripts/build-android-strings.py` and commit
  the output. Only `app_name` is hand-written (`values/app_name.xml`).
- **Typography and colour: `Theme` only** (`ui/Theme.kt` and what FOX-149 grows it into). No
  literal fonts or colours at call sites. Green and red are exclusive to answer feedback;
  selection is an accent *border*, never a fill. Dynamic type: `sp` text, no fixed-height
  frames (German, Vietnamese and Burmese run long). Cards sit lighter than the screen in both
  appearances.
- **Analytics: `Track` only** (`analytics/Track.kt`); nothing else imports Firebase. Event names
  and param keys are `lower_snake_case` and match the iOS names: add the constant to `TrackEvents`, and
  rerun `python3 scripts/extract-track-events.py` when iOS adds one (`TrackCatalogTest` fails otherwise).
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
`adb shell am start -n com.kfpun.japanesedaily/.catalog.CatalogActivity [--es section tokens|type|cards|options|empty|rating]`.

## Data layer (`data/`, FOX-148)

One entry point, `AppContainer.from(context)`, gives `vocab` (`VocabStore`: 50 lessons, 2100
words, 19 meaning languages, audio asset paths), `kana` (`KanaData`), `progress`
(`ProgressRepository` over Room: `ChallengeResult`, `KanaResult`, `StudyDay`, bookmarks),
`practice` (`PracticeProgress`) and `prefs` (DataStore, `Pref` registry). `Course` holds the
course constants; only `Course.Minna` exists.

- No table has a unique constraint; every reader tolerates duplicate rows (`ChallengeResult.better`,
  latest-timestamp for kana, newest bookmark), so a later sign-in sync needs no rewrite.
- Day stamps come from `StudyDay.stamp` (`java.time`, ISO numbering, the user's zone), never
  `Calendar`/`DateFormat`. `LadderRules` holds the pass bar, stars and rung count the progress
  rules need; the Challenge ladder feature reuses it.
- Tests read `nihongo/Resources` in place through `FileAssetSource`; the Room tests run under
  Robolectric. The Room schema is exported to `app/schemas/` for future migration tests.

## Audio (`audio/`, FOX-151)

Port of `Pronouncer`/`Speech`. `Pronouncer` is the seam (`LocalPronouncer`, silent by default;
`ProvidePronouncer` in `MainActivity` supplies `AudioPronouncer`). Every sound is the bundled
VOICEVOX clip first (`VocabStore.audioPath`, the alternate voice falls back to the default), then
live `TextToSpeech` ja-JP. `MediaClipPlayer` plays from `AssetFileDescriptor` (clips are stored
uncompressed), one clip at a time, under transient-may-duck audio focus. `AndroidTtsEngine` shuts
itself down after 30 s idle; with no Japanese voice nothing plays and one toast is shown per process.
Screens call `StopSoundOnExit()`; the host also stops on `ON_STOP`.

- `AudioVoice.Alternate.suffix` (`-kenzaki`) must equal `ALT_SUFFIX` in `build-minna-data.py`;
  `AudioTest` reads the script. `speakText` is TTS only (bare text tiles); `speak(K)` uses the kana clip.
- Rates: `PlaybackRates.effective(stored, premium)`; only 1x is free. `PremiumStatus` defaults to
  `NotPremium` until FOX-158 supplies Pro.
- `Licenses.voicevox` holds the required credit lines; `LicensesScreen` is what Settings (FOX-159) links to.

## Kana tab (`kana/`, FOX-152)

Port of `nihongo/Kana/` and `context/03-kana.md`. `KanaTab` is a small state-based stack (browser, mode list,
one of five modes; Back pops one level) over a `KanaEnv` (container, `LocalPronouncer`, glyph rasteriser).
All of Kana is free: nothing here is gated. The browser rotates `TileScript` (あ, ア, A) from one toolbar
button; its **index is the persisted `kanaTileScript` pref**, so append, never reorder. Tiles border green or
red from the latest `KanaResult` for the romaji, with a check or cross beside the colour.

- Modes: Flashcards (the shared `ui/components/FlashcardScreen` + `FlashDeck`, writes nothing), Classic and
  Listening (`KanaQuizModel`, 4 options), Swipe (2 options, `SwipeCard`, 90 dp threshold), Write.
  Every answer is recorded, right or wrong, through `ProgressRepository.recordKana`, which also writes the
  study day. Write records on Next, only when something was drawn.
- Faces follow the content's script (`glyphStyle`): kana on `jpStrokes`/`jpBold`, romaji on `Theme.display`.
- **Write scoring** is `KanaSketch`, a stroke-for-stroke port of iOS `KanaSketch.swift`: 48x48 grid with a 12%
  margin, per-axis stretch, symmetric chamfer + 5x 6x6 zone term, `100 - distance * 3.5`, minus 10 per stroke of
  difference; pass is 80 *and* the exact textbook stroke count. Only the glyph rasteriser
  (`AndroidGlyphRasterizer`) is platform code; everything after it is pure Kotlin.
- **Shared fixtures:** `app/src/test/resources/kana/sketch-fixtures.json` is dumped from the real Swift by
  `python3 scripts/dump-kana-sketch-fixtures.py` (macOS, `swiftc`, no Xcode build). `KanaSketchTest` asserts
  digit stripping, glyph grids, chamfer/zone/distance (1e-9) and score arithmetic **exactly**. Rasterising the user's
  strokes is **toleranced**: CoreGraphics anti-aliases where Android lights a cell by centre distance, so up to
  6% of cells may differ and end-to-end scores must agree within 2 points (measured worst: 1).
- **Template fonts differ, on purpose:** iOS takes the best of five (KanjiStrokeOrders, YuKyokasho, Klee, Tsukushi
  A Round Gothic, Hiragino Sans W6); the last four are Apple fonts. Android uses KanjiStrokeOrders plus Noto Serif
  JP bold and regular. The shared fixtures therefore cover the KanjiStrokeOrders template only. Handwritten
  (textbook) letterforms are the loss, so a sloppy-but-right glyph may score a little lower than on iOS.
- The on-screen template scales its digit-strip threshold by the rendered font size (iOS scales by bitmap size,
  which leaves digits on the aspect-fit glyph).

## Lessons tab (`lessons/`, FOX-153)

Port of `nihongo/Lessons/` and `context/04-lessons.md`. `LessonsTab` is a state-based stack (`LessonsNav`, hoisted
in `AppScaffold`, string-encoded routes) over a `LessonsEnv` (container + current meaning language; null while
the course data decodes off the main thread). Screens: list + search, `SelectModeScreen` (the one place gating is
enforced), Practice, Vocab List, Read along, Flashcards, Match, Learn, Bookmarks.

- **Gating is pure** (`Gating`, port of iOS `Gating`): lessons 1-5 free, the earned first band
  (`hasEarnedFirstGroup`, three stars on every rung of the free lessons), `isLocked(earnedFirstGroup = false)` fails
  closed, Read along's meanings preview 7 words then the paywall, the speed dial is Pro, only subscribers loop.
  `LessonStanding` tallies results for the list rows, the lock and the earn hint.
- **Seams other tickets fill** (`Ports.kt`, `ChallengeEntry.kt`, `LessonsTab.kt`): `LocalPremium` (FOX-158, defaults
  `NotPremium`), `LocalOpenPaywall` (hosted by `PaywallHost`, a *placeholder dialog* until FOX-158 swaps in the real
  paywall), `LocalLessonExits.onLeavePractice/onLeaveMatch(answered)` (the interstitial hook), and
  `LocalOpenChallenge` (**FOX-154's entry point**: the rung strip, next-up and retry cards are drawn read-only and
  call it; replace `nextQuestions` with the pool size).
- **Models are pure Kotlin** (`PracticeModel`, `MatchModel`, `LearnModel`, `LessonPlayer`) with Compose state for the
  screen and an injectable `Random`; the mirrored iOS tests are in `app/src/test/.../lessons/`. Practice writes only
  `PracticeProgress` stages (through `StageStore`); Flashcards writes nothing at all.
- Not ported yet: the report flag and swipe-to-report (the Feedback sheet is FOX-157's), and no screen reaches
  `BookmarksScreen` until Progress/Settings push `LessonRoute.Bookmarks`.

## Strings (FOX-150)

`scripts/build-android-strings.py` (stdlib only) writes `res/values/strings.xml` (English, the
default), one `values-<qualifier>/strings.xml` per other language, and `res/xml/locales_config.xml`.
The output is **committed**, and the `Android` CI job runs `build-android-strings.py --check`,
which fails when any file is missing, stale or unexpected. Rerun the script after any
`UIStrings.json` change.

- **Folders:** `zh` (Simplified) is `values-b+zh+Hans`, `zh-Hant` is `values-b+zh+Hant`,
  Indonesian is `values-in`, the rest `values-<code>` (`fil`, `my`, `ne`, `ta`, `te`, `bn`, ...).
- **Names:** from the English key: lowercase, `%@` becomes `arg`, `%` becomes `pct`, runs of
  non-alphanumerics become `_` (`"Clear %@"` is `R.string.clear_arg`, `"Lessons"` is
  `R.string.lessons`). A name that starts with a digit or is a Java keyword (`s_interface`) gets `s_`; one over 60 characters is cut
  with a sha1 suffix; two keys that map to one name both get a sha1 suffix. The default file keeps
  each original key in a comment above its string, so grep the key to find the name.
- **Values:** `%@` becomes `%1$s`, `%2$s`... in order; `%%` stays `%%` (the app formats these
  with `getString(id, args)`); apostrophes, quotes, backslash, `& < >`, newlines, a leading `@`
  or `?` and edge spaces are escaped. A string with no placeholder uses a plain `%` and
  `formatted="false"`.
- **Parity:** `StringResourcesTest` (port of the iOS `LocalizationTests`) checks every language has
  every key with the same placeholders, and that `AppLanguage` and `locales_config.xml` agree.

### Language switching

`locale/AppLanguage` is the 19 languages in iOS `L.languageOrder`; `locale/AppLocale` stores the
choice (`appLanguage`, as on iOS) and applies it with `AppCompatDelegate.setApplicationLocales`.
`locales_config.xml` puts the languages in the phone's per-app language setting (Android 13+), and
the `AppLocalesMetadataHolderService` entry keeps the choice on 12 and below. `null` means follow
the phone. Anything without an activity (widget, notification, worker) must read text through
`AppLocale.localizedContext(context).getString(...)`, never the plain context. The Settings
picker (a later ticket) calls `AppLocale.set` and labels each language by its own name
(`Locale.forLanguageTag(tag).getDisplayName(locale)`).
