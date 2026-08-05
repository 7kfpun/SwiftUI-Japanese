import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
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
        }
        #endif

        #if canImport(GoogleMobileAds)
        MobileAds.shared.start(completionHandler: nil)
        #endif

        return true
    }
}

/// Thin analytics seam — logs only when FirebaseAnalytics is linked and configured.
enum Track {
    static func screen(_ name: String) {
        #if canImport(FirebaseAnalytics)
        if FirebaseApp.app() != nil {
            Analytics.logEvent(AnalyticsEventScreenView,
                               parameters: [AnalyticsParameterScreenName: name])
        }
        #endif
    }
}
