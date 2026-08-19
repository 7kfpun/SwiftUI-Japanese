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
#if canImport(FirebasePerformance)
import FirebasePerformance
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
        // Retires the old boolean rating flag in favour of a timestamp, before anything can
        // read it — see `RatingPrompt.migrateLegacyFlagIfNeeded`.
        RatingPrompt.migrateLegacyFlagIfNeeded()

        #if canImport(FirebaseCore)
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            #if canImport(FirebaseAppCheck)
            // Must be installed *before* configure() — the factory is consulted as
            // Firebase starts, and setting it afterwards leaves the first requests
            // unattested.
            AppCheck.setAppCheckProviderFactory(SurveyAppCheckFactory())
            #endif
            FirebaseApp.configure()
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
                #if canImport(FirebasePerformance)
                // Excluded on the same terms as the other two. A developer's own device
                // would otherwise skew exactly the numbers Performance exists to watch —
                // it runs a debug build, on a fast device, on office wifi.
                Performance.sharedInstance().isDataCollectionEnabled = false
                Performance.sharedInstance().isInstrumentationEnabled = false
                #endif
            }
        }
        #endif

        // After `FirebaseApp.configure()`: `Messaging.messaging()` needs a configured app
        // and hands back a useless instance before there is one. Starting it here rather
        // than in a `.task` also means the notification delegate is set before iOS can
        // deliver a launch notification.
        PushService.shared.start(launchOptions: launchOptions)
        Task { await PushService.shared.registerIfAuthorized() }

        #if canImport(GoogleMobileAds)
        // Non-personalized ads only: we deliberately ship without App Tracking
        // Transparency, so ads must never use the IDFA. No ATT prompt, no tracking
        // declaration in App Privacy — at the cost of lower ad personalization/eCPM.
        MobileAds.shared.requestConfiguration.publisherPrivacyPersonalizationState = .disabled
        MobileAds.shared.start(completionHandler: nil)
        #endif

        return true
    }

    // Firebase's app-delegate proxy is disabled (`FirebaseAppDelegateProxyEnabled = NO`
    // in both Info.plists) so it can't fight OneSignal over these callbacks. That makes
    // them load-bearing rather than boilerplate: without them FCM never learns the APNs
    // token and every push it sends is dropped, silently.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushService.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushService.shared.didFailToRegister(error: error)
    }
}

/// Puts navigation bar titles in the rounded title face (`Theme.titleUIFont`), so every
/// `.navigationTitle` call site matches the rest of the app's headings instead of being the
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

/// The two UIKit lookups a SwiftUI app keeps needing and has no API for: the window that
/// is actually on screen (its size, its root view controller) and the scene something modal
/// can be presented in. Both were spelled out at five call sites across the ads, StoreKit
/// and rating code; a chain repeated that often drifts one `first(where:)` at a time.
extension UIApplication {
    /// The key window — deliberately not named `keyWindow`, which is the deprecated
    /// pre-scene API. For anything that needs the on-screen window itself: its bounds
    /// (the adaptive banner width) or its root view controller (ad presentation).
    var activeKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// The foreground-active window scene, which is what Apple's own modal sheets
    /// (`showManageSubscriptions`, `requestReview`) are presented *in* rather than over.
    var foregroundScene: UIWindowScene? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
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
        // Also remembered for the survey context, which is why this is the one place worth
        // routing every screen through: `last_screen` is what turns "the audio is broken"
        // into "the audio is broken on Kana Write". Recorded here rather than at the 16 call
        // sites so it can't fall out of step with what analytics saw, and deliberately
        // *outside* the analytics opt-out — a feedback report needs its own context even
        // from a device excluded from tracking.
        Survey.recordScreen(name)
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

    /// The four things about a learner that **Firebase cannot work out for itself**,
    /// pushed as user properties so any event can be segmented by them.
    ///
    /// The bar for adding one here is exactly that: GA4 already collects device model,
    /// OS version, screen size, app version and build, country, and the *device* language
    /// automatically, as dimensions. Re-sending those as user properties buys nothing and
    /// spends from a hard budget of 25 per project — a predecessor of this app shipped
    /// fifteen such duplicates. What is *not* automatic is what the learner chose.
    ///
    /// - `ui_language` / `meaning_language`: the two settings are deliberately
    ///   independent and both deliberately differ from the device locale — a Taiwanese
    ///   phone reading Vietnamese meanings is a real and invisible-to-GA4 configuration.
    /// - `knows_kana` / `learning_goal`: answered in the intro, until now sent once as
    ///   `intro_done` params and so unusable as a segment afterwards.
    /// - `earned_first_group`: splits free users into two populations that behave nothing
    ///   alike — those who took the free unlock path and those who met the paywall.
    ///
    /// **No identifier, ever.** Not `user_id`, not `identifierForVendor`, not a minted
    /// install id. Every value here is a coarse attribute shared by many people; none of
    /// them joins two rows to one person. `Analytics.setUserID` is called nowhere in this
    /// codebase and must stay that way.
    ///
    /// Idempotent: unchanged values are skipped, so callers may fire it as often as is
    /// convenient — `Unlock.refresh` does, on every Today appear.
    static func setProfile(uiLanguage: String,
                           meaningLanguage: String,
                           knowsKana: String?,
                           goal: String?,
                           earnedFirstGroup: Bool) {
        let values = profile(uiLanguage: uiLanguage, meaningLanguage: meaningLanguage,
                             knowsKana: knowsKana, goal: goal,
                             earnedFirstGroup: earnedFirstGroup)
        guard values != lastProfile else { return }
        lastProfile = values
        #if canImport(FirebaseAnalytics)
        if FirebaseApp.app() != nil {
            for (name, value) in values { Analytics.setUserProperty(value, forName: name) }
        }
        #endif
    }

    /// The properties `setProfile` will send. Pure, and separated from the sending so the
    /// naming and the fallbacks can be tested — Firebase isn't configured under test, so
    /// anything folded into the call itself would be verified by nothing.
    static func profile(uiLanguage: String,
                        meaningLanguage: String,
                        knowsKana: String?,
                        goal: String?,
                        earnedFirstGroup: Bool) -> [String: String] {
        // GA4 truncates a user-property value past 36 characters, which would silently
        // merge two segments. Nothing here is close today; the clamp is what keeps that
        // true if a goal or language code ever grows.
        func clamped(_ v: String) -> String { String(v.prefix(36)) }
        return ["ui_language": clamped(uiLanguage),
                "meaning_language": clamped(meaningLanguage),
                // "unanswered" rather than omitting the key: a property never set is
                // indistinguishable in GA4 from one whose owner skipped the question,
                // and those are different populations.
                "knows_kana": clamped(knowsKana ?? "unanswered"),
                "learning_goal": clamped(goal ?? "unanswered"),
                "earned_first_group": earnedFirstGroup ? "true" : "false"]
    }

    private static var lastProfile: [String: String] = [:]

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
        #if canImport(FirebasePerformance)
        if FirebaseApp.app() != nil {
            Performance.sharedInstance().isDataCollectionEnabled = !excluded
            Performance.sharedInstance().isInstrumentationEnabled = !excluded
        }
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

    /// Time `work` as a Firebase Performance custom trace.
    ///
    /// Here rather than at the call sites for the same reason `event` is: `Track` is the
    /// one seam, and nothing else in the app may import a Firebase module. It also means
    /// a build without the SDK — an open-source clone with no `GoogleService-Info.plist`
    /// — still runs the work, untimed, instead of failing to compile.
    ///
    /// Most of what's worth knowing is already automatic: Performance instruments app
    /// start, foreground/background, screen rendering (including frozen and slow frames)
    /// and every URLSession request without being asked. Reach for this only for a
    /// specific span those don't cover, and name it `lower_snake_case` like an event.
    @discardableResult
    static func trace<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
        #if canImport(FirebasePerformance)
        guard FirebaseApp.app() != nil, let t = Performance.startTrace(name: prefix + name) else {
            return try work()
        }
        defer { t.stop() }
        return try work()
        #else
        return try work()
        #endif
    }
}
