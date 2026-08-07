import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// Starts Firebase + AdMob at launch. Every SDK touch is behind `canImport`, so the
/// app builds and runs before the packages are added; and Firebase only configures
/// when its git-ignored `GoogleService-Info.plist` is actually bundled, so an
/// open-source clone (no secrets) still launches cleanly.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if canImport(FirebaseCore)
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()   // enables Analytics + Crashlytics
            // Developer/Xcode runs (DEBUG) never pollute production counts. A
            // Release/TestFlight build on the developer's own device can opt out
            // too, via the hidden toggle in Settings (Track.setExcluded).
            var excludeThisDevice = UserDefaults.standard.bool(forKey: Pref.analyticsExcluded)
            #if DEBUG
            excludeThisDevice = true
            #endif
            if excludeThisDevice {
                #if canImport(FirebaseAnalytics)
                Analytics.setAnalyticsCollectionEnabled(false)
                #endif
                #if canImport(FirebaseCrashlytics)
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
                #endif
            }
        }
        #endif

        #if canImport(GoogleMobileAds)
        // Non-personalized ads only: we deliberately ship without App Tracking
        // Transparency, so ads must never use the IDFA. No ATT prompt, no tracking
        // declaration in App Privacy — at the cost of lower ad personalization/eCPM.
        MobileAds.shared.requestConfiguration.publisherPrivacyPersonalizationState = .disabled
        MobileAds.shared.start(completionHandler: nil)
        #endif

        return true
    }
}

/// Thin analytics seam — logs only when the Firebase SDKs are linked and configured.
/// Every event name is prefixed with `nihongo_2026_`.
enum Track {
    static let prefix = "nihongo_2026_"

    /// Cached from the last `setPremium` call so every event can carry it as a
    /// param — `user_type`/`premium_tier` (below) already attach via Firebase user
    /// properties, but an explicit per-event `is_premium` also lets funnels filter
    /// without joining user-level data.
    private static var isPremium = false

    /// Log a custom event (prefixed). No-op until Firebase is linked + configured.
    static func event(_ name: String, _ params: [String: Any]? = nil) {
        #if canImport(FirebaseAnalytics)
        if FirebaseApp.app() != nil {
            let merged = (params ?? [:]).merging(["is_premium": isPremium]) { existing, _ in existing }
            Analytics.logEvent(prefix + name, parameters: merged)
        }
        #endif
    }

    /// A screen was shown.
    static func screen(_ name: String, _ params: [String: Any] = [:]) {
        event("screen", params.merging(["name": name]) { a, _ in a })
    }

    /// Segment users by entitlement: `user_type` = premium/free, `premium_tier` =
    /// lifetime / 3m / 6m / 12m / none. User properties attach to every event.
    static func setPremium(_ isPremium: Bool, tier: String) {
        Self.isPremium = isPremium
        #if canImport(FirebaseAnalytics)
        if FirebaseApp.app() != nil {
            Analytics.setUserProperty(isPremium ? "premium" : "free", forName: "user_type")
            Analytics.setUserProperty(tier, forName: "premium_tier")
        }
        #endif
    }

    /// Per-device analytics opt-out (Settings' hidden long-press toggle) — persists
    /// across launches via `Pref.analyticsExcluded` and also applies immediately,
    /// so switching it off mid-session stops collection right away.
    static func setExcluded(_ excluded: Bool) {
        UserDefaults.standard.set(excluded, forKey: Pref.analyticsExcluded)
        #if canImport(FirebaseAnalytics)
        if FirebaseApp.app() != nil { Analytics.setAnalyticsCollectionEnabled(!excluded) }
        #endif
        #if canImport(FirebaseCrashlytics)
        if FirebaseApp.app() != nil { Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(!excluded) }
        #endif
    }

    static var isExcluded: Bool { UserDefaults.standard.bool(forKey: Pref.analyticsExcluded) }

    /// A bundled clip was missing so playback fell back to TTS — Analytics event +
    /// Crashlytics breadcrumb, to surface coverage gaps.
    static func audioMissing(_ item: String) {
        print("audio is missing: \(item)")
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().log("audio is missing: \(item)")
        #endif
        event("audio_missing", ["item": item])
    }
}
