import SwiftUI

/// A bottom banner ad for a screen slot.
///
/// Compiles with or without the Google Mobile Ads SDK: until the `GoogleMobileAds`
/// Swift Package is added in Xcode, `canImport` is false and this renders as an
/// empty (zero-height) view, so the rest of the app builds and runs untouched.
///
/// Height is **dynamic**: it stays 0 until an ad actually loads, then becomes the
/// ad's real height. Placed in a `.safeAreaInset`, that means the content only gives
/// up space when (and exactly as much as) an ad is on screen — no blank gap, no overlap.
struct BannerAd: View {
    let slot: AdSlot
    @Environment(Store.self) private var store
    #if canImport(GoogleMobileAds)
    @State private var adHeight: CGFloat = 0
    #endif

    var body: some View {
        if store.isPremium {
            EmptyView()   // premium removes ads
        } else {
            adBody
        }
    }

    @ViewBuilder private var adBody: some View {
        #if canImport(GoogleMobileAds)
        // The SDK refuses to load into a zero-sized view ("Invalid ad width or height"),
        // so the BannerView always keeps its full ad size internally; the outer frame +
        // clip decide how much the layout shows — 0 until an ad actually arrives.
        let size = AdBannerRepresentable.preferredSize
        AdBannerRepresentable(unitID: AdConfig.banner(slot), adHeight: $adHeight)
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity)
            .frame(height: adHeight, alignment: .top)
            .clipped()
        #elseif DEBUG
        // SDK not added yet: show where the banner will sit (DEBUG only).
        Text("Ad banner · \(slot.rawValue) · add GoogleMobileAds package")
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(.tertiarySystemFill))
        #else
        EmptyView()
        #endif
    }
}

#if canImport(GoogleMobileAds)
import GoogleMobileAds

/// Bridges an AdMob adaptive `BannerView` (Google Mobile Ads SDK ≥ 12) into SwiftUI,
/// reporting the loaded ad's height back so the layout can size to it.
private struct AdBannerRepresentable: UIViewRepresentable {
    let unitID: String
    @Binding var adHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(adHeight: $adHeight) }

    /// The adaptive ad size for the current window (clamped so it's always valid),
    /// falling back to the classic 320×50 if the adaptive lookup degenerates.
    static var adSize: AdSize {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        let width = max(320, window?.bounds.width ?? 375)
        let adaptive = currentOrientationAnchoredAdaptiveBanner(width: width)
        return adaptive.size.height > 0 ? adaptive : AdSizeBanner
    }

    /// The size the SwiftUI layout should give the (possibly hidden) banner view.
    static var preferredSize: CGSize { adSize.size }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: Self.adSize)
        banner.adUnitID = unitID
        banner.rootViewController = Coordinator.rootViewController
        banner.delegate = context.coordinator
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var adHeight: CGFloat
        init(adHeight: Binding<CGFloat>) { _adHeight = adHeight }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            withAnimation { adHeight = bannerView.adSize.size.height }
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            // Collapse to 0pt, but never silently: no-fill on new units looks like "ads broken".
            print("Ad banner failed (\(bannerView.adUnitID ?? "?")): \(error.localizedDescription)")
            Track.event("ad_failed", ["error": error.localizedDescription])
            withAnimation { adHeight = 0 }
        }

        /// The key window's root VC, which AdMob needs to present click-through UI.
        static var rootViewController: UIViewController? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?
                .rootViewController
        }
    }
}
#endif
