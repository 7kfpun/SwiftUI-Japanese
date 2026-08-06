# AdMob + Firebase setup (prod / local split)

The app integrates **AdMob banners**, **Firebase Analytics**, and **Firebase
Crashlytics**. To keep this repo open-source, no real keys are committed:

| What | Committed (safe) | Real (git-ignored) |
|------|------------------|--------------------|
| Firebase config | `config/GoogleService-Info.example.plist` | `nihongo/GoogleService-Info.plist` |
| AdMob unit IDs  | `config/Secrets.example.plist` + Google **test** IDs baked into `AdConfig.swift` | `nihongo/Secrets.plist` |
| AdMob app ID    | Google **test** app ID in the target's `GADApplicationIdentifier` build setting | override locally |

**A fresh clone builds and runs with no setup**: SDK code is behind
`#if canImport(...)`, so before the packages are added the banners are empty and
Firebase is skipped. Once the packages are added, ads (test IDs) and Firebase
(only if `GoogleService-Info.plist` is present) turn on automatically.

## One-time setup for the real app

1. **Add the Swift Packages** in Xcode → *File ▸ Add Package Dependencies…*
   - `https://github.com/firebase/firebase-ios-sdk` → add **FirebaseAnalytics** and **FirebaseCrashlytics**
   - `https://github.com/googleads/swift-package-manager-google-mobile-ads` → add **GoogleMobileAds** (SDK **≥ 12**, verified with **13.7**; uses the de-prefixed API names this code calls: `MobileAds`, `BannerView`, `Request`, `currentOrientationAnchoredAdaptiveBanner`)

2. **Drop in the real config files** (both git-ignored):
   - Firebase console → download `GoogleService-Info.plist` → copy to `nihongo/GoogleService-Info.plist`
   - `cp config/Secrets.example.plist nihongo/Secrets.plist` and fill in your real `ca-app-pub-…/…` banner units

3. **Real AdMob app ID**: set the target build setting
   `GADApplicationIdentifier` (currently Google's test app ID) to your real
   `ca-app-pub-…~…` iOS app ID.

4. **Crashlytics dSYMs**: add a *Run Script* build phase (after *Copy Bundle Resources*):
   ```sh
   "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
   ```
   Input files:
   ```
   ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}
   $(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist
   $(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)
   ```
   and set **Debug Information Format = DWARF with dSYM File** for Release.

## In-app purchase (premium)

Lessons 1–5 are free; 6–50 need premium, which also removes ads. Built on
**StoreKit 2** — no SDK, no server, no shared secret (transactions verify on-device).
Product IDs match the RN app so existing lifetime/subscription buyers **restore**
automatically. No secrets, nothing git-ignored.

One-time setup:
1. Target → *Signing & Capabilities* → **+ In-App Purchase**.
2. To test in the **simulator**: scheme → *Run ▸ Options ▸ StoreKit Configuration* →
   select `nihongo/Store/Products.storekit`.
3. For production: create the subscription group `premium` (`…premium.3m/6m/12m`) and the
   non-consumable `…premium.lifetime` in App Store Connect (see `PremiumProduct` in
   `nihongo/Store/Store.swift`).

Code: `nihongo/Store/Store.swift` (entitlement + gating), `PaywallView.swift`,
`Products.storekit`. Gating is `Gating.isLocked(lesson:isPremium:)`; ads hide via
`BannerAd` reading `Store.isPremium`.

## Where it lives in code

- `nihongo/Ads/AdConfig.swift` — unit-ID resolution (test ⇢ `Secrets.plist`)
- `nihongo/Ads/AdBanner.swift` — `BannerAd(slot:)` SwiftUI view
- `nihongo/Ads/AppBootstrap.swift` — `AppDelegate` (Firebase + AdMob start) and `Track`
- Banners are placed in `RootView` via `.safeAreaInset(edge: .bottom)`.
