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
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
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
        }
        #endif

        #if canImport(GoogleMobileAds)
        MobileAds.shared.start(completionHandler: nil)
        #endif

        requestTracking()
        return true
    }

    /// Ask for App Tracking Transparency once the app is active (AdMob/Firebase use the
    /// IDFA). Requesting again after a decision is a no-op, so this is safe every launch.
    private func requestTracking() {
        #if canImport(AppTrackingTransparency)
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)   // let the app become active
            let status = await ATTrackingManager.requestTrackingAuthorization()
            Track.event("att", ["status": Int(status.rawValue)])
        }
        #endif
    }
}

/// Thin analytics seam — logs only when the Firebase SDKs are linked and configured.
/// Every event name is prefixed with `nihongo_2026_`.
enum Track {
    static let prefix = "nihongo_2026_"

    /// Log a custom event (prefixed). No-op until Firebase is linked + configured.
    static func event(_ name: String, _ params: [String: Any]? = nil) {
        #if canImport(FirebaseAnalytics)
        if FirebaseApp.app() != nil {
            Analytics.logEvent(prefix + name, parameters: params)
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
        #if canImport(FirebaseAnalytics)
        if FirebaseApp.app() != nil {
            Analytics.setUserProperty(isPremium ? "premium" : "free", forName: "user_type")
            Analytics.setUserProperty(tier, forName: "premium_tier")
        }
        #endif
    }

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
