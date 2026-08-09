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
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if canImport(FirebaseAppCheck)
/// Proves a Firestore write came from a genuine, unmodified build of this app.
///
/// The survey collection takes unauthenticated writes — there are no accounts, and
/// deliberately no device identifier (see `Survey`) — so the rules can bound *what*
/// gets written but not *who* writes it. App Check closes that: Apple attests the
/// binary, and enforcement is switched on per-service in the Firebase console.
///
/// App Attest can't work on the Simulator, so DEBUG uses the debug provider, which
/// prints a token to the console that you register once under App Check → Apps →
/// Manage debug tokens. Without that, development writes are rejected.
private final class SurveyAppCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}
#endif

/// Starts Firebase + AdMob at launch. Every SDK touch is behind `canImport`, so the
/// app builds and runs before the packages are added; and Firebase only configures
/// when its git-ignored `GoogleService-Info.plist` is actually bundled, so an
/// open-source clone (no secrets) still launches cleanly.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NavigationBarTitle.install()

        #if canImport(FirebaseCore)
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            #if canImport(FirebaseAppCheck)
            // Must be installed *before* configure() — the factory is consulted as
            // Firebase starts, and setting it afterwards leaves the first requests
            // unattested.
            AppCheck.setAppCheckProviderFactory(SurveyAppCheckFactory())
            #endif
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

/// Puts navigation bar titles in the rounded title face (`Theme.titleUIFont`), so the 12
/// `.navigationTitle` call sites match every other heading in the app instead of being the
/// last SF Pro text on screen.
///
/// It lives in UIKit because SwiftUI has no way to font a nav title — there is no
/// `.navigationTitle(_:font:)` and `.font()` on the surrounding view doesn't reach the bar.
/// The only route is `UINavigationBarAppearance`, and the appearance proxy does reach
/// SwiftUI's own bars: `NavigationStack` reads `UINavigationBar.appearance()` as it builds
/// one, for both `.inline` and large titles.
///
/// Three things here are less arbitrary than they look:
///
/// **Fresh appearance objects, never the proxy's own.** `UINavigationBar.appearance()` is a
/// recorder, not a live object: reading `.standardAppearance` back off it hands you an empty
/// appearance (no background configuration, no title attributes), so the mutate-and-put-back
/// shape would quietly replace the bar's default background with nothing. A brand-new
/// `UINavigationBarAppearance()` is exactly the default configuration, so setting only the
/// two font attributes on one changes the title face and nothing else.
///
/// **`scrollEdgeAppearance` is deliberately left alone.** Its default is nil, and nil means
/// "standardAppearance with the background dropped" — so the title font carries into the
/// scrolled-to-top state for free. Assigning an appearance here instead would hand that
/// state a default *background*, turning every transparent-at-the-top bar in the app opaque.
///
/// **The size ceilings are the system's own.** An explicit font opts a nav bar out of the
/// growth limit it applies to its stock title: measured on iOS 26, the stock inline title
/// runs 17 → 19 → 21pt and then holds at 21 through every accessibility size, while a font
/// handed to the appearance is honoured verbatim — 48pt of title in a 44pt bar, straight
/// through the toolbar buttons beside it. `upTo:` restores the limit at the value the system
/// itself stops at. Large titles get 60pt for the same reason, which is where the stock
/// large title tops out; that one genuinely does grow all the way, because the large-title
/// area grows with it and has no buttons to collide with.
///
/// There is no `UIContentSizeCategory.didChangeNotification` observer and none is needed —
/// see `Theme.titleUIFont` for why the font tracks Dynamic Type on its own.
enum NavigationBarTitle {
    static func install() {
        let appearance = UINavigationBarAppearance()
        appearance.titleTextAttributes[.font] =
            Theme.titleUIFont(size: 17, weight: .semibold, relativeTo: .headline, upTo: 21)
        appearance.largeTitleTextAttributes[.font] =
            Theme.titleUIFont(size: 34, weight: .bold, relativeTo: .largeTitle, upTo: 60)

        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = appearance
        proxy.compactAppearance = appearance
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
    /// lifetime / 1m / 3m / 6m / none, plus 12m for a legacy subscriber who restored.
    /// User properties attach to every event.
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
