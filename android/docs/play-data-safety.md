# Play Console compliance answers (FOX-161)

What to enter in Play Console → App content for `com.kfpun.japanesedaily`. Every answer names the file
it comes from, so the form can be re-derived when the app changes. **These are answers to type in, not
something the repo submits**: filling the forms is a user step (see
[`../README.md`](../README.md), Release).

Sources on the integration branch (`feature/fox-145-android`) today:

| Area | Android code | iOS spec it ports |
|---|---|---|
| Firebase Analytics, Crashlytics | `analytics/FirebaseSink.kt`, `analytics/Track.kt`, `AndroidManifest.xml`, `app/build.gradle.kts` | `nihongo/Ads/AppBootstrap.swift` (`Track`) |
| Survey rows (Directus) | not merged yet (FOX-157) | `nihongo/Survey.swift`, `nihongo/Feedback/Feedback.swift`, `context/09-intro-and-survey.md` |
| AdMob, UMP, Play Billing | not merged yet (FOX-158; versions are in `gradle/libs.versions.toml`) | `nihongo/Ads/`, `nihongo/Store/`, `context/06-monetization.md` |
| Progress storage | `data/progress/` (Room), `data/prefs/` (DataStore), `res/xml/data_extraction_rules.xml` | `nihongo/ChallengeResult.swift` (iOS adds iCloud) |

FOX-157 and FOX-158 had not landed when this was written, so the survey, ads and billing answers rest on
the iOS code the Android port copies (FOX-146: "the iOS app is the spec") plus the SDKs' own disclosures.
**Re-check them against the merged Android code before submitting** (the checklist at the end).

## 1. Data safety

### Overview questions

| Question | Answer | From |
|---|---|---|
| Does the app collect or share any of the required user data types? | Yes | below |
| Is all of the user data collected by your app encrypted in transit? | Yes. Firebase and AdMob use TLS/HTTPS ([Firebase](https://firebase.google.com/docs/android/play-data-disclosure), [AdMob](https://developers.google.com/admob/android/privacy/play-data-disclosure)); Directus is `https://cms.wahthefox.com` (`Survey.Directus.baseURL`) | `nihongo/Survey.swift` |
| Do you provide a way for users to request that their data be deleted? | **No account, so no deletion request flow** (Play only requires one for apps with accounts). On-device data goes with an uninstall. Survey rows carry no identifier, so a row cannot be looked up unless the sender wrote their email into it; see the privacy policy's "Your choices" | `web/privacy.html`, `data_extraction_rules.xml` |
| Does the app follow the Families Policy? | Not applicable: not a children's app (section 4) | |

Nothing is collected from or linked to an account: there is no sign-in (FOX-146), the app never calls
`setUserId`, and the Firebase consent defaults deny ad storage, ad user data and ad personalization.
**Every data type below is therefore declared "not linked to identity"** where Play asks, and none is
"ephemeral" (all of it is stored by the receiving service).

### Data types

"Collected" = leaves the device. "Shared" = transferred to a third party that uses it for its own
purposes. Firebase acts as a service provider for us, which Play does not count as sharing; Google's
advertising use of AdMob data is declared as shared.

| Play category → type | Collected | Shared | Optional? | Purposes | Where it comes from |
|---|---|---|---|---|---|
| **App activity → App interactions** | Yes | Yes (AdMob: ad impressions and clicks); Firebase: no | Required | Analytics (Firebase events, `Track`); Advertising or marketing, Fraud prevention (AdMob) | `analytics/Track.kt`, `analytics/TrackEvents.kt` (the `nihongo_2026_*` events catalogued in `app/src/test/resources/ios-track-catalog.txt`: screens, challenge results, purchases funnel, no free text). AdMob: user product interactions ([AdMob](https://developers.google.com/admob/android/privacy/play-data-disclosure)) |
| **App activity → Other actions** | Yes (survey) | No | Optional | App functionality (reading the answers and fixing the app) | `Survey.Context`: `goal`, `knows_kana`, `textbook_lesson` from the first-launch questions, plus `challenges_passed`, `kana_answered`, `last_screen`. Sent only when the user taps submit on the intro, a star rating or the feedback sheet. `nihongo/Survey.swift` |
| **App info and performance → Crash logs** | Yes | No | Required | Analytics (Crashlytics reports), App functionality (stability) | `FirebaseSink.kt` (Crashlytics). Stack traces, device state at the crash, breadcrumbs ([Firebase](https://firebase.google.com/docs/android/play-data-disclosure)) |
| **App info and performance → Diagnostics** | Yes | Yes (AdMob: app and SDK performance) | Required | Analytics, App functionality; Advertising or marketing, Fraud prevention (AdMob) | Crashlytics device metadata; AdMob diagnostic information. Survey rows also carry app version, OS version, device model, text size, appearance (`Survey.Context`: `app_version`, `os`, `device`, `text_size`, `appearance`, `debug`, `v`) |
| **Device or other IDs** | Yes | Yes (advertising ID to Google for ads) | Required | Advertising or marketing, Fraud prevention (advertising ID, AdMob); Analytics, App functionality (Firebase installation ID and Firebase's app-instance ID) | Advertising ID: AdMob only, see section 3. The Firebase installation ID (FID) is created by `firebase-installations`, pulled in by Analytics and Crashlytics; Crashlytics adds its own installation UUID ([Firebase](https://firebase.google.com/docs/android/play-data-disclosure)). **The app never mints or sends an identifier of its own**: `android/CLAUDE.md` ("No persistent identifier"), `Track.kt` ("No identifier of our own") |
| **Location → Approximate location** | Yes | Yes (AdMob) | Required | Advertising or marketing, Fraud prevention | Not from a permission: the app declares no location permission. AdMob collects the IP address, "which may estimate a device's general location" ([AdMob](https://developers.google.com/admob/android/privacy/play-data-disclosure)). Declared because Play counts the estimate |
| **Financial info → Purchase history** | Yes | No | Required | App functionality (premium state), Analytics | Play Billing returns purchase tokens to the device; the app keeps premium state locally. What leaves the device is the derived flag: `is_premium` on every event and the `user_type` / `premium_tier` user properties (`Track.kt`, `setPremium`), and `is_premium` / `tier` in survey rows (`Survey.Context`). Card and payment details never reach the app: Google Play handles them. No server-side receipt validation (FOX-146) |
| **Personal info → Email address** | Yes (only if typed) | No | **Optional** | App functionality (a reply to the feedback) | `Feedback.email` in the `nihongo_survey_feedback` row; "optional, and never gates sending" (`nihongo/Feedback/Feedback.swift`) |
| **Messages → Other in-app messages** | Yes (only if sent) | No | **Optional** | App functionality | `Feedback.message`, free text typed in the feedback sheet, plus `kind`, `area`, `source`, `stars`, `lesson`, `item` (the word reported) |

Declared **not collected**: name, address, phone, contacts, precise location, photos or files, audio
or voice (the app only plays audio), health, web browsing, installed apps, search history, SMS, calendar,
and any user-generated content beyond the feedback text. Handwriting practice is scored on the device; no
drawing is sent (the only server write is the survey).

### Survey rows in detail (Directus, optional)

Written only after the user taps submit. Create-only static token on `nihongo_survey_{intro,rating,feedback}`
(`Survey.Directus`); no read, update or delete, and no user, session or reply channel. Columns, exactly
`Survey.Context.keys` plus the per-collection fields:

- Context on every row: `platform`, `app_version`, `os`, `device` (model string, not a unit id),
  `os_language`, `app_language`, `vocab_language`, `region`, `is_premium`, `tier`, `challenges_passed`,
  `kana_answered`, `sound_on`, `analytics_excluded`, `shown_fields`, `text_size`, `appearance`,
  `last_screen`, `knows_kana`, `goal`, `textbook_lesson`, `debug`, `v`.
- `nihongo_survey_rating`: `stars`. `nihongo_survey_feedback`: `kind`, `area`, `message`, `email`,
  `source`, `stars`, `lesson`, `item`.

Not linked to identity because nothing in the row identifies a person or joins two rows
(`nihongo/Survey.swift`, "Deliberately no user identifier of any kind"); the optional email is the only
exception and is the user's own choice to write.

### Things Play will ask that have a fixed answer

- **Sold or shared for sale?** No. AdMob's use is declared as sharing for advertising, not a sale.
- **Data processed ephemerally?** No.
- **Third-party SDK data:** declared above (Firebase Analytics, Crashlytics, Installations; Google Mobile
  Ads SDK). Play cross-checks the SDK list from the bundle, so an SDK that arrives later (App Check,
  Performance) must be added here first.

## 2. Privacy policy

URL: `https://japanesedaily.wahthefox.com/privacy.html` (`web/privacy.html`, hand-maintained, covers both
apps and now Android). Enter it in Play Console → App content → Privacy policy and on the store listing.
The text and this file share the same facts; change both together.

## 3. Ads declaration and AD_ID

| Form | Answer | Why / from |
|---|---|---|
| **Ads** → Does your app contain ads? | **Yes** | AdMob banners and an interstitial on the free tier (`secrets.example.properties`: `AD_UNIT_ID_*`, `AD_UNIT_ID_INTERSTITIAL`; iOS `nihongo/Ads/AdConfig.swift`). Premium removes them |
| **Advertising ID** → Does your app use the advertising ID? | **Yes** | The Google Mobile Ads SDK reads it and merges `com.google.android.gms.permission.AD_ID` into the manifest. Required when targeting Android 13 (API 33)+; the app targets 36 (`app/build.gradle.kts`) |
| Advertising ID purposes | **Advertising or marketing**; **Fraud prevention, security and compliance** | AdMob page above: ad ID is used for "advertising, analytics, fraud prevention"; under non-personalized ads Google still uses it for frequency capping, aggregated reporting and abuse prevention |
| Analytics purpose for the ID | **Not ticked** | `AndroidManifest.xml` sets `google_analytics_adid_collection_enabled=false`, `google_analytics_default_allow_ad_personalization_signals=false`, `..._ad_user_data=false`, `..._ad_storage=false`; `FirebaseSink.createOrNull` denies the same consents at runtime |

Do **not** strip `AD_ID` with `tools:node="remove"`: the ads need it, and removing it while declaring "Yes"
contradicts the form. If ads are ever removed from the app, remove the SDK, answer "No" and drop the
advertising rows above instead.

How ads behave (for the policy and the form): ads are always **non-personalized**, after the UMP consent
form where the user's region requires one (the UMP dependency is in `gradle/libs.versions.toml`;
`android/CLAUDE.md`: "AdMob is non-personalized, after UMP consent"). The child-directed and under-age
flags stay off because the app is not for children.

## 4. Target audience and content

| Form | Answer | Why |
|---|---|---|
| **Target audience** age groups | **13–15, 16–17, 18 and over**; none under 13 | `web/privacy.html` already says the app is not directed to children under 13. Choosing an under-13 group would put it under the Families Policy and its ad-SDK rules |
| Appeals to children? | No | Language-learning for teens and adults; no cartoon characters or child-directed content |
| **Content rating** (IARC) category | **Reference, news or educational** | A study app |
| Violence, blood, fear, sexuality, nudity, profanity, drugs, alcohol, tobacco, gambling | **No** to all | The content is textbook vocabulary and the kana. Check the word list once at release for anything the questionnaire would count |
| Simulated gambling, real-money gaming | No | No such feature |
| Does the app let users interact or exchange content? | **No** | The feedback sheet sends text to the developer only; nothing is shown to other users |
| Shares the user's location with other users | No | No location access |
| Allows purchases of digital goods | **Yes** | Premium (subscriptions and lifetime) through Play Billing |
| Unrestricted web access | No | No browser; links to the privacy policy and store page open outside the app |
| **Expected result** | PEGI 3, ESRB Everyone, USK 0, IARC 3+ | Typical for this questionnaire's answers; Play Console shows the real outcome |

Other declarations: **News app** No; **COVID-19 contact tracing** No; **Government app** No; **Financial
features** None; **Health** None; **Data safety** as above; **App access**: no login, all functionality
available without special access (the paid tier is a purchase, not credentials).

## 5. Re-check before submitting

When FOX-157 and FOX-158 are merged, confirm the answers still match the code:

1. `grep -rn "FirebaseAnalytics\|FirebaseCrashlytics" android/app/src/main` is still only `FirebaseSink.kt`,
   and no `setUserId` exists.
2. The merged manifest (`app/build/intermediates/merged_manifests/.../AndroidManifest.xml`) has no location
   permission, and has `com.google.android.gms.permission.AD_ID` (from play-services-ads).
3. The Android `Survey` writes the same keys as `Survey.Context.keys` (`SurveyTests`-style test) and sends no
   Android ID, advertising ID or minted id; and the `platform` value it sends is accepted by Directus.
4. Ad requests set `npa` (non-personalized) and the child-directed flags stay unset.
5. `app/build.gradle.kts` lists no SDK beyond Firebase Analytics, Crashlytics, Play Billing, Mobile Ads and
   UMP. A new one (App Check, Performance, Remote Config) needs a row here and a policy line.
6. The Play products exist and match the listing text: subscriptions of 1, 3, 6 and 12 months plus
   a lifetime purchase (the store description names all of them).
