import UIKit

/// Compile-safe facade for the full-screen interstitial ("popup") ad. All SDK use is
/// behind `#if canImport`, so callers (e.g. `QuizView`) don't depend on the package.
/// Callers must gate on `!store.isPremium` — premium users see no ads.
enum Ads {
    /// Warm up an interstitial so it's ready to show at the next break.
    static func preloadInterstitial() {
        #if canImport(GoogleMobileAds)
        Task { await Interstitial.shared.preload() }
        #endif
    }

    /// Show the interstitial if one is loaded and the throttle window has elapsed.
    static func showInterstitialIfReady() {
        #if canImport(GoogleMobileAds)
        Interstitial.shared.showIfReady()
        #endif
    }
}

#if canImport(GoogleMobileAds)
import GoogleMobileAds

/// Loads and presents an interstitial, throttled so it never shows more than once per
/// `minInterval`. Reloads itself after each presentation.
@MainActor
final class Interstitial {
    static let shared = Interstitial()

    private var ad: InterstitialAd?
    private var loading = false
    private var lastShown = Date.distantPast
    private let minInterval: TimeInterval = 180   // ≤ once per 3 minutes

    func preload() async {
        guard ad == nil, !loading else { return }
        loading = true
        defer { loading = false }
        ad = try? await InterstitialAd.load(with: AdConfig.interstitial, request: Request())
    }

    func showIfReady() {
        guard Date().timeIntervalSince(lastShown) > minInterval else { return }
        guard let ad, let root = Self.topViewController else {
            Task { await preload() }        // not ready — warm up for next time
            return
        }
        ad.present(from: root)
        Track.event("interstitial_shown")
        lastShown = Date()
        self.ad = nil
        Task { await preload() }
    }

    /// The front-most view controller to present from.
    private static var topViewController: UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
#endif
