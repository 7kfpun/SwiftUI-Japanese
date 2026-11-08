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

## Analytics and Crashlytics

`analytics/Track` is the only seam: nothing else imports Firebase (`FirebaseSink` is the one file that
does). Names carry the iOS `nihongo_2026_` prefix, so Android and iOS land in the same reports; the
catalog is `TrackEvents`/`TrackScreens`, pinned by `TrackCatalogTest` to
`android/app/src/test/resources/ios-track-catalog.txt`, which `python3 scripts/extract-track-events.py`
generates from the Swift source (CI runs it with `--check`). Without `app/google-services.json` Track is a
no-op. No user id, no advertising id; consent is denied for ads and personalization.

- **Excluded device:** seven quick taps on the version line at the foot of Settings toggle the opt-out
  (`Track.setExcluded`, persisted as `analyticsExcluded` in the `settings` prefs); the line then reads
  "Analytics off". It stops Analytics and Crashlytics together.
- **Debug builds are excluded**, like iOS DEBUG. To check events in DebugView: put
  `FIREBASE_DEBUG_COLLECTION=true` in `secrets.properties`, copy the real `google-services.json` to
  `app/`, install the debug build, then `adb shell setprop debug.firebase.analytics.app com.kfpun.japanesedaily`.

## Backups

`android:allowBackup="false"`, `fullBackupContent="false"` and `data_extraction_rules.xml`
excludes every domain from both cloud backup and device transfer. Progress is on the device
only (FOX-146).

## Release

The runbook for the **first release** on a new Play listing (FOX-161). Nothing here runs on a code
change: each step that uploads, signs or writes to Play Console happens only when the user asks for it.
Steps marked **[USER]** can only be done by the account owner (they need the Play or Google account, a
secret, or a decision); the rest the agent or the user can run once asked.

The listing text is in `fastlane/minna-android/metadata/android/<play-locale>/` (title, short and full
description for the 19 UI languages) and is checked by `python3 scripts/check-play-listing.py`. The
answers for the Play Console forms are in [`docs/play-data-safety.md`](docs/play-data-safety.md).

### 0. Before any upload

1. All feature tickets (FOX-152 to FOX-160) are merged and `./gradlew ktlintCheck lint test assembleDebug`
   passes. Run `python3 scripts/check-play-listing.py` and `python3 scripts/build-android-strings.py --check`.
2. Re-check the compliance answers against the merged code (`docs/play-data-safety.md`, the last section).
3. Bump `versionCode` and `versionName` in `app/build.gradle.kts` (the first upload is `1` / `3.0.0`, matching iOS 3.x; Play
   rejects a repeated `versionCode`).
4. The **VOICEVOX credit** (e.g. `VOICEVOX:WhiteCUL`) is visible in Settings, Licenses: the voice terms
   require it, and the root `CLAUDE.md` says nothing in the app carries one yet.
5. **[USER]** Real config, all gitignored (never commit): the AdMob **Android** app id and ad unit ids in
   `android/secrets.properties`; the real `DIRECTUS_TOKEN`; `app/google-services.json` for
   `com.kfpun.japanesedaily` from the `kf-nihongo` Firebase project (add the Android app there first).
   Without them a release builds with Google's test ads, no survey writes and no Firebase.
6. **[USER]** In Directus, make the survey collections accept the Android client: the `platform` column
   takes `Android` (iOS sends `iOS`). The app sends no field the columns lack.
7. **[USER]** Host `app-ads.txt` on the developer website domain (the one on the listing) so AdMob can verify
   the app.

### 1. Create the app and sign up for Play App Signing

1. **[USER]** Play Console → Create app: name "Japanese Daily 每日日本語", default language English (US),
   App, **Free**, Education category, accept the declarations. The package name is fixed by the first
   upload and cannot change: `com.kfpun.japanesedaily`.
2. **[USER]** Create the **upload key** once, outside the repo, and keep a backup (Play can reset a lost
   upload key, but the process takes days):

   ```sh
   mkdir -p ~/.keys/japanesedaily
   keytool -genkeypair -v -keystore ~/.keys/japanesedaily/upload.jks -alias upload \
     -keyalg RSA -keysize 2048 -validity 10000
   ```

   Then copy `keystore.example.properties` to `keystore.properties` (gitignored) with `storeFile`,
   `storePassword`, `keyAlias` and `keyPassword`. Never paste the passwords into a ticket, PR or chat.
3. **Play App Signing is enrolled at the first upload.** New apps must upload an Android App Bundle, and
   Google generates and keeps the app signing key; the upload key above only proves who uploaded. Accept the
   enrolment prompt on the first upload (Test and release → Setup → App signing). Do not upload an APK, and do
   not supply your own app signing key.

### 2. Service account for publishing

1. **[USER]** Google Cloud console (a project of the user's choice): enable the **Google Play Android
   Developer API**, create a service account, and download a JSON key.
2. **[USER]** Play Console → Users and permissions → Invite new users: the service account's email, with
   permission to release to testing tracks (and, later, production) for this app only.
3. **[USER]** Save the key as `android/play-service-account.json` (gitignored) or point
   `PLAY_SERVICE_ACCOUNT_JSON` in `secrets.properties` at it. A new service account can take some hours to
   work.

### 3. Store listing and the Play Console forms

1. **[USER]** Store listing → add each language (Manage translations → Add your own), then push the text
   from the repo. Metadata only, no binary:

   ```sh
   fastlane supply --package_name com.kfpun.japanesedaily --json_key android/play-service-account.json \
     --metadata_path fastlane/minna-android/metadata/android --skip_upload_aab --skip_upload_apk \
     --skip_upload_images --skip_upload_screenshots --skip_upload_changelogs
   ```

   (Or paste the three files per language into Console by hand.) Language folders use Play's codes:
   `zh-CN`, `zh-TW`, `bn-BD`, `my-MM`, `ne-NP`, `ta-IN`, `te-IN`, `fil`, and so on.
2. **[USER]** Graphics are not in the repo: the 512 px icon, the 1024 x 500 feature graphic, and phone (and
   tablet, if offered) screenshots. Capture screenshots from the release build in English and the
   longer-text languages.
3. **[USER]** App content, with the answers in `docs/play-data-safety.md`: privacy policy URL
   (`https://japanesedaily.wahthefox.com/privacy.html`), ads (yes), advertising ID (yes), Data safety, content
   rating (IARC), target audience (13 and over, not for children), app access (no login), contact email.
4. **[USER]** Monetize → create the in-app products and subscriptions the listing names: 1, 3, 6 and 12
   months plus a lifetime purchase. Product ids are permanent once created, and FOX-158 defines which ids
   the app asks for, so create exactly those.

### 4. Internal testing

1. Build and upload to the **internal** track as a draft (`play {}` in `app/build.gradle.kts`):

   ```sh
   cd android
   ./gradlew publishMinnaReleaseBundle
   ```

   It stops with a message if `keystore.properties` is missing. Release builds are minified: install the
   bundle from Play on a real device before going further.
2. **[USER]** Release the draft to internal testing in Console and add testers (an email list; they accept
   through the opt-in link).
3. Smoke test from the Play install: first launch and the intro, UMP consent where the region needs it,
   ads appear (real ones, not test ads), a Challenge, audio, the widget, language switching, and a survey
   submission arriving in Directus.

### 5. Closed testing with license testers (Billing)

Play Billing only works on a build installed from Play, with products that are Active.

1. **[USER]** Settings → License testing: add the testers' Google accounts. They buy with a test card and
   are not charged; subscriptions renew on a short test schedule.
2. **[USER]** Promote the build to a **closed** testing track and add the same testers. If the developer
   account is a personal account created after November 2023, Play requires a closed test with a minimum
   number of opted-in testers (12 when this was written) for 14 days before production access: check the
   current requirement in Console and plan the calendar around it.
3. Test every product: buy each subscription and the lifetime item, restore on a second device or after a
   reinstall, cancel, and check that premium turns on and off and ads disappear.

### 6. Staged production rollout

1. **[USER]** Production → Create release from the tested bundle, with release notes, and start at **5%**.
   Managed publishing (Publishing overview) lets the user decide when an approved release goes live.
2. Before each step up (5%, 20%, 50%, 100%), wait for at least a day of data and check, in Play Console →
   Android vitals and in Crashlytics (project `kf-nihongo`):
   - **User-perceived crash rate** under 1.09% and **user-perceived ANR rate** under 0.47%, Play's
     bad-behaviour thresholds, and better than the previous release;
   - no new top crash or ANR cluster in Crashlytics;
   - billing and ads working (no spike in `ad_failed` or purchase-failed events), and ratings not
     dropping.
3. If a step fails, **halt the rollout** in Console and ship a fixed `versionCode`; do not push through.
4. When the rollout reaches 100% and the listing is public, build the website with the Google Play badge on
   (`python3 scripts/build-web.py --all --google-play`) and deploy it only when the user asks
   (see the `build-and-deploy-web` skill). Read the page copy at the same time: it still says "iOS app" and
   "Free on iPhone & iPad".
<!-- FOX-169 throwaway check, not merged -->
