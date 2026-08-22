import SwiftUI

/// A bottom banner ad for a screen slot.
///
/// Compiles with or without the Google Mobile Ads SDK: until the `GoogleMobileAds`
/// Swift Package is added in Xcode, `canImport` is false and this renders as an
/// empty (zero-height) view, so the rest of the app builds and runs untouched.
///
/// Height is **dynamic**: it stays 0 until an ad actually loads, then becomes the
/// ad's real height, so the content only gives up space when (and exactly as much as)
/// an ad is on screen — no blank gap, no overlap. The space is reserved structurally by
/// `RootView.banner(_:_:)`'s `VStack`, deliberately *not* a `.safeAreaInset` — see there.
struct BannerAd: View {
    let slot: AdSlot
    @Environment(Store.self) private var store
    #if canImport(GoogleMobileAds)
    @State private var adHeight: CGFloat = 0
    #endif

    /// Screenshot runs (UI tests launched with "-SCREENSHOTS") hide the banner
    /// so marketing shots stay clean. No effect on normal launches.
    private static let screenshotMode = ProcessInfo.processInfo.arguments.contains("-SCREENSHOTS")

    var body: some View {
        if !Course.current.adsEnabled || store.isPremium || Self.screenshotMode {
            EmptyView()   // premium removes ads; a course can switch them off wholesale
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
        AdBannerRepresentable(unitID: AdConfig.banner(slot), slot: slot, adHeight: $adHeight)
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
    /// Only for analytics — the unit ID is the thing AdMob loads, but a raw ID means
    /// nothing in a dashboard and differs between a Secrets build and a fresh clone.
    let slot: AdSlot
    @Binding var adHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(slot: slot, adHeight: $adHeight) }

    /// The adaptive ad size for the current window (clamped so it's always valid),
    /// falling back to the classic 320×50 if the adaptive lookup degenerates.
    static var adSize: AdSize {
        let width = max(320, UIApplication.shared.activeKeyWindow?.bounds.width ?? 375)
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
        let slot: AdSlot
        @Binding var adHeight: CGFloat
        init(slot: AdSlot, adHeight: Binding<CGFloat>) {
            self.slot = slot
            _adHeight = adHeight
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            withAnimation { adHeight = bannerView.adSize.size.height }
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            // Collapse to 0pt, but never silently: no-fill on new units looks like "ads broken".
            print("Ad banner failed (\(bannerView.adUnitID ?? "?")): \(error.localizedDescription)")
            // `slot` is the point of the event. Every banner in the app failed under one
            // undifferentiated name, so a single unit that had never been created in
            // AdMob — or a slot added without a Secrets key, still on the test unit —
            // was indistinguishable from the whole network being down.
            Track.event("ad_failed", ["error": error.localizedDescription,
                                      "slot": slot.rawValue])
            withAnimation { adHeight = 0 }
        }

        /// The key window's root VC, which AdMob needs to present click-through UI.
        static var rootViewController: UIViewController? {
            UIApplication.shared.activeKeyWindow?.rootViewController
        }
    }
}
#endif
