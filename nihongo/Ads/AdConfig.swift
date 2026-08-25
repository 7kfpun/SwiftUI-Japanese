import Foundation

/// Where a banner appears. Keys match the slot names in `Secrets.plist` (and the
/// iOS unit names in the original RN `config.js`, e.g. `ios-kana-banner`).
enum AdSlot: String {
    case today
    /// The Progress tab. Split off `today`, which it used to share: two screens on one
    /// unit blend their impressions, so there was no way to tell whether a tab people
    /// visit briefly earns anything at all.
    case progress
    case kana, lessons
    case selectMode = "select-mode"
    case vocabList  = "vocab-list"
    case search
    case about
}

/// AdMob unit IDs, split prod/local to keep the repo open-source.
///
/// A fresh clone has no `Secrets.plist`, so this falls back to Google's **public
/// test** unit — the app shows test ads and commits no secrets. The real per-screen
/// units live in a git-ignored `nihongo/Secrets.plist` (see `config/Secrets.example.plist`);
/// when present, `banner(_:)` returns the production ID for that slot.
enum AdConfig {
    /// Google's official sample units — always safe to ship.
    static let testBanner = "ca-app-pub-3940256099942544/2934735716"
    static let testInterstitial = "ca-app-pub-3940256099942544/4411468910"

    /// The whole git-ignored Secrets.plist, if present.
    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any]
        else { return [:] }
        return dict
    }()

    private static var productionBanners: [String: String] {
        secrets["banners"] as? [String: String] ?? [:]
    }

    /// The banner unit ID for a slot — production when configured, else the test unit.
    ///
    /// `.today` used to borrow the vocab-list unit here, because Secrets.plist predated
    /// the Today tab and had no key for it. That alias was the only thing keeping
    /// Google's public test banner off the landing tab in a production build — a config
    /// gap wearing a code fallback as a disguise. The key exists now, so the alias is
    /// gone and a missing key fails visibly (test ads) instead of silently.
    ///
    /// DEBUG always uses Google's test units: dev clicks on real ads violate AdMob
    /// policy, and test units always fill (brand-new real units can no-fill for days).
    static func banner(_ slot: AdSlot) -> String {
        #if DEBUG
        return testBanner
        #else
        return productionBanners[slot.rawValue] ?? testBanner
        #endif
    }

    /// The interstitial unit ID (RN's `assessment-popup`) — production or test.
    static var interstitial: String {
        #if DEBUG
        return testInterstitial
        #else
        return secrets["interstitial"] as? String ?? testInterstitial
        #endif
    }
}
