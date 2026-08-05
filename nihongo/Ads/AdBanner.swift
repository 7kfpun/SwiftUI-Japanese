import SwiftUI

/// A bottom banner ad for a screen slot.
///
/// Compiles with or without the Google Mobile Ads SDK: until the `GoogleMobileAds`
/// Swift Package is added in Xcode, `canImport` is false and this renders as an
/// empty (zero-height) view, so the rest of the app builds and runs untouched.
/// Once the package is present it shows a real (test-by-default) AdMob banner.
struct BannerAd: View {
    let slot: AdSlot

    var body: some View {
        #if canImport(GoogleMobileAds)
        AdBannerRepresentable(unitID: AdConfig.banner(slot))
            .frame(height: 50)
        #else
        EmptyView()
        #endif
    }
}

#if canImport(GoogleMobileAds)
import GoogleMobileAds

/// Bridges an AdMob `BannerView` (Google Mobile Ads SDK ≥ 12) into SwiftUI.
private struct AdBannerRepresentable: UIViewRepresentable {
    let unitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = unitID
        banner.rootViewController = Self.rootViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    /// The key window's root VC, which AdMob needs to present click-through UI.
    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
#endif
