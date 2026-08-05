import Foundation

/// Where a banner appears. Keys match the slot names in `Secrets.plist` (and the
/// iOS unit names in the original RN `config.js`, e.g. `ios-kana-banner`).
enum AdSlot: String {
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
    /// Google's official sample banner unit — always safe to ship.
    static let testBanner = "ca-app-pub-3940256099942544/2934735716"

    /// `banners` dictionary from the git-ignored Secrets.plist, if any.
    private static let productionBanners: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let banners = dict["banners"] as? [String: String]
        else { return [:] }
        return banners
    }()

    /// True when real production ad IDs are configured (Secrets.plist present).
    static var isProduction: Bool { !productionBanners.isEmpty }

    /// The banner unit ID for a slot — production when configured, else the test unit.
    static func banner(_ slot: AdSlot) -> String {
        productionBanners[slot.rawValue] ?? testBanner
    }
}
