# Japanese Daily — Android

Kotlin + Jetpack Compose + Material 3 port of the iOS app (Minna no Nihongo vocabulary and the
kana). The iOS app is the spec; decisions are in Linear FOX-146 and summarised in
[`CLAUDE.md`](CLAUDE.md).

| | |
|---|---|
| Package | `com.kfpun.japanesedaily` |
| Flavour | `minna` (dimension `course`); JLPT follows as a second flavour |
| SDK | minSdk 26, compileSdk / targetSdk 36 |
| JDK | 17 |
| Gradle / AGP / Kotlin | 9.8.2 / 9.5.1 / 2.4.21 (see `gradle/libs.versions.toml`) |

The catalog pins the last releases that build against compileSdk 36 (Compose 1.12+, core 1.19+
and lifecycle 2.11+ need 37). Do not bump them to "latest".

## Setup

```sh
brew install openjdk@17 android-commandlinetools
export JAVA_HOME=$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=$(brew --prefix)/share/android-commandlinetools

# The minna flavour packages nihongo/Resources (MinnaData.json, KanaChart.json, audio/) in
# place. They are generated and gitignored, from the private `minna` submodule:
git submodule update --init minna
python3 scripts/build-minna-data.py      # from the repo root

cd android
./gradlew assembleDebug                  # builds with secrets.example.properties as-is
```

A build without `nihongo/Resources/MinnaData.json` stops at `checkMinnaData` with the commands
above.

## Commands

Run from `android/`.

| | |
|---|---|
| `./gradlew ktlintCheck lint test assembleDebug` | What CI runs (the `Android` check). Must pass before a PR. |
| `./gradlew ktlintFormat` | Fix ktlint findings (`.editorconfig`: android_studio style, 120 columns). |
| `./gradlew installMinnaDebug` | Install on a connected device or emulator. |
| `./gradlew bundleMinnaRelease` | Release bundle; unsigned without `keystore.properties`. |

The debug APK is `app/build/outputs/apk/minna/debug/app-minna-debug.apk`.

## Config

`secrets.example.properties` is checked in and holds Google's **test** ad ids and a placeholder
Directus token. `secrets.properties` (gitignored) overrides it key by key, so a key left out
falls back to the example. `app/build.gradle.kts` reads both through `secret("NAME")` into
`BuildConfig` or manifest placeholders.

| Key | Goes to | iOS counterpart |
|---|---|---|
| `ADMOB_APP_ID` | manifest placeholder `ADMOB_APP_ID` | `GADApplicationIdentifier` |
| `AD_UNIT_ID_TODAY`, `_PROGRESS`, `_KANA`, `_LESSONS`, `_SELECT_MODE`, `_VOCAB_LIST`, `_SEARCH`, `_ABOUT` | `BuildConfig.AD_UNIT_ID_*` | `banners` in `Secrets.plist` (`AdSlot`) |
| `AD_UNIT_ID_INTERSTITIAL` | `BuildConfig.AD_UNIT_ID_INTERSTITIAL` | `interstitial` |
| `DIRECTUS_URL` | `BuildConfig.DIRECTUS_URL` | `https://cms.wahthefox.com` |
| `DIRECTUS_TOKEN` | `BuildConfig.DIRECTUS_TOKEN` | `directusToken` (create-only) |
| `PLAY_SERVICE_ACCOUNT_JSON` | Play Publisher credentials path | — |

Other gitignored local files:

| File | Purpose |
|---|---|
| `app/google-services.json` | Firebase config for `com.kfpun.japanesedaily` in project `kf-nihongo`. The google-services and Crashlytics plugins apply only when it exists; without it the app builds and Firebase stays uninitialised. |
| `keystore.properties` | Upload-key signing (copy `keystore.example.properties`). |
| `play-service-account.json` | Play publishing credentials (or the path in `PLAY_SERVICE_ACCOUNT_JSON`). |

Never commit any of these. Real values for the iOS app live in the main checkout's
`nihongo/Secrets.plist`.

## Backups

`android:allowBackup="false"`, `fullBackupContent="false"` and `data_extraction_rules.xml`
excludes every domain from both cloud backup and device transfer. Progress is on the device
only (FOX-146).

## Release (runbook stub)

Release is its own ticket and its own explicit request; nothing here runs on a code change.

1. Bump `versionCode` (and `versionName`) in `app/build.gradle.kts`.
2. Create `keystore.properties` pointing at the upload keystore (kept outside the repo, for
   example `~/.keys/japanesedaily`) and put the real ad ids, Directus token and
   `google-services.json` in place.
3. `./gradlew publishMinnaReleaseBundle` uploads a signed bundle to the **internal** track as a
   **draft** (Gradle Play Publisher); roll it out in Play Console. Without `keystore.properties`
   the task stops with a message before building.

Release builds are minified and resource-shrunk; check on a device before uploading.
