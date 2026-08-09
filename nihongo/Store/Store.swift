import StoreKit
import UIKit

/// Premium product IDs — must match App Store Connect **and** the original RN app, so
/// existing lifetime buyers / subscribers restore automatically (a non-consumable stays
/// tied to the Apple ID forever; StoreKit 2 surfaces it via `currentEntitlements`).
enum PremiumProduct {
    static let lifetime = "com.kfpun.nihongo.premium.lifetime"
    /// Current subscription lineup in App Store Connect. Note the uppercase M on 3M/6M:
    /// product IDs are case-sensitive and immutable, and the lowercase 2019 IDs are
    /// reserved forever, so the new products had to differ.
    static let subscriptions = [
        "com.kfpun.nihongo.premium.1m",
        "com.kfpun.nihongo.premium.3M",
        "com.kfpun.nihongo.premium.6M",
    ]
    /// Legacy RN-era subscriptions — no longer sold, still honored so old buyers restore.
    static let legacy = [
        "com.kfpun.nihongo.premium.3m",
        "com.kfpun.nihongo.premium.6m",
        "com.kfpun.nihongo.premium.12m",
    ]
    /// What the paywall sells.
    static let purchasable = subscriptions + [lifetime]
    /// Everything that grants premium (incl. legacy) — used for the entitlement scan.
    static let all = purchasable + legacy
}

/// Free/premium gating: lessons 1…`freeLessonLimit` are free in full — every mode,
/// every challenge — and the rest need premium. Vocab List is the one exception, free
/// on every lesson, so browsing and search stay open.
///
/// Deliberately one rule with no partial trial. A free user can *finish* the early
/// lessons — fill the progress bar, earn the stars — and meets the paywall carrying
/// that momentum, rather than being cut off mid-practice by a card quota.
enum Gating {
    static let freeLessonLimit = 3

    /// True when a lesson needs premium (everything but Vocab List).
    static func isLocked(lesson number: Int, isPremium: Bool) -> Bool {
        !isPremium && number > freeLessonLimit
    }
}

/// StoreKit 2 premium store. No server / shared-secret receipt validation — transactions
/// are verified on-device; restore is `AppStore.sync()`. `isPremium` drives lesson
/// gating and ad hiding across the app.
@Observable
@MainActor
final class Store {
    private(set) var products: [Product] = []
    private(set) var isPremium = false
    // Sold: lifetime / 1m / 3m / 6m. Also reachable by restore only: 12m (see `legacy`).
    private(set) var tier = "none"
    private(set) var purchasingID: String?

    init() {
        // Renewals, revocations, Ask-to-Buy approvals, and restores on other devices.
        Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await self?.refreshEntitlement()
            }
        }
        Task { await load(); await refreshEntitlement() }
    }

    /// Whether a fetch is in flight, and whether one has ever finished — the paywall
    /// needs to tell "still loading" from "loaded nothing", which a bare `isEmpty`
    /// can't. Without the distinction a failed fetch renders as an eternal spinner.
    private(set) var isLoadingProducts = false
    private(set) var didAttemptLoad = false

    /// A load finished and produced nothing: offline, StoreKit unavailable, or the
    /// products aren't approved in App Store Connect yet.
    var productsUnavailable: Bool { didAttemptLoad && !isLoadingProducts && products.isEmpty }

    func load() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false; didAttemptLoad = true }
        products = (try? await Product.products(for: PremiumProduct.purchasable))?
            .sorted { $0.price < $1.price } ?? []
    }

    /// Subscriptions only, cheapest first — the paywall's main list.
    var subscriptions: [Product] { products.filter { $0.subscription != nil } }

    /// The lifetime non-consumable, shown apart from the subscriptions rather than as
    /// a fourth peer in the same list: it's a different kind of commitment, and mixed
    /// in among them it reads as "the expensive one" instead of "the other option".
    var lifetime: Product? { products.first { $0.subscription == nil } }

    /// Premium if any premium product is currently entitled — an active subscription or
    /// the owned lifetime unlock.
    func refreshEntitlement() async {
        var premium = false
        var tier = "none"
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil,
                  PremiumProduct.all.contains(t.productID) else { continue }
            premium = true
            tier = Self.tierLabel(t.productID)
        }
        isPremium = premium
        self.tier = tier
        Track.setPremium(premium, tier: tier)
    }

    func purchase(_ product: Product) async {
        purchasingID = product.id
        defer { purchasingID = nil }
        let tier = Self.tierLabel(product.id)
        Track.event("purchase_start", ["tier": tier])
        guard let result = try? await product.purchase() else {
            Track.event("purchase_failed", ["tier": tier, "reason": "error"])
            return
        }
        switch result {
        case .success(.verified(let t)):
            await t.finish()
            await refreshEntitlement()
            Track.event("purchase_success", ["tier": tier])
        case .userCancelled:
            Track.event("purchase_failed", ["tier": tier, "reason": "cancelled"])
        case .pending:
            Track.event("purchase_failed", ["tier": tier, "reason": "pending"])
        default:
            Track.event("purchase_failed", ["tier": tier, "reason": "unverified"])
        }
    }

    /// Restore prior purchases (incl. the legacy RN lifetime unlock) on this Apple ID.
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
        Track.event("restore", ["premium": isPremium])
    }

    /// Apple's native manage-subscriptions sheet — where users switch tier (1m↔3m↔6m
    /// within the same group) or cancel. Refreshes entitlement on return.
    func manageSubscriptions() async {
        guard let scene = UIApplication.shared.foregroundScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        await refreshEntitlement()
    }

    /// Short tier label from a product ID (…premium.3M → "3m", lifetime → "lifetime").
    private static func tierLabel(_ id: String) -> String {
        id == PremiumProduct.lifetime ? "lifetime"
            : (id.components(separatedBy: ".").last ?? id).lowercased()
    }
}
