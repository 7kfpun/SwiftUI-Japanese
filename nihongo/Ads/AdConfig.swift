import Foundation

/// Where a banner appears. Keys match the slot names in `Secrets.plist` (and the
/// iOS unit names in the original RN `config.js`, e.g. `ios-kana-banner`).
enum AdSlot: String {
    case today
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

    /// True when real production ad IDs are configured (Secrets.plist present).
    static var isProduction: Bool { !productionBanners.isEmpty }

    /// The banner unit ID for a slot — production when configured, else the test unit.
    /// Slots added after the Secrets.plist was written fall back to another production
    /// unit first, so a missing key never ships test ads in a production build.
    static func banner(_ slot: AdSlot) -> String {
        if let id = productionBanners[slot.rawValue] { return id }
        if slot == .today, let id = productionBanners[AdSlot.vocabList.rawValue] { return id }
        return testBanner
    }

    /// The interstitial unit ID (RN's `assessment-popup`) — production or test.
    static var interstitial: String {
        secrets["interstitial"] as? String ?? testInterstitial
    }
}
