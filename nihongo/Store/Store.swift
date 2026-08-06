import StoreKit

/// Premium product IDs — must match App Store Connect **and** the original RN app, so
/// existing lifetime buyers / subscribers restore automatically (a non-consumable stays
/// tied to the Apple ID forever; StoreKit 2 surfaces it via `currentEntitlements`).
enum PremiumProduct {
    static let lifetime = "com.kfpun.nihongo.premium.lifetime"
    static let subscriptions = [
        "com.kfpun.nihongo.premium.3m",
        "com.kfpun.nihongo.premium.6m",
        "com.kfpun.nihongo.premium.12m",
    ]
    static let all = subscriptions + [lifetime]
}

/// Free/premium gating. Lessons 1…`freeLessonLimit` are fully free. On the rest, the
/// practice modes (Flashcards/Learn/Quiz/Listening) give `freeTrialCards` cards before
/// the paywall; Vocab List stays free everywhere.
enum Gating {
    static let freeLessonLimit = 5
    static let freeTrialCards = 5

    /// True when a lesson's practice modes are premium-gated (i.e. trial-limited).
    static func isLocked(lesson number: Int, isPremium: Bool) -> Bool {
        !isPremium && number > freeLessonLimit
    }

    /// The free card/question limit for a lesson, or nil when unlimited (free lesson or premium).
    static func trialLimit(lesson number: Int, isPremium: Bool) -> Int? {
        isLocked(lesson: number, isPremium: isPremium) ? freeTrialCards : nil
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

    func load() async {
        products = (try? await Product.products(for: PremiumProduct.all))?
            .sorted { $0.price < $1.price } ?? []
    }

    /// Premium if any premium product is currently entitled — an active subscription or
    /// the owned lifetime unlock (`currentEntitlements` only yields non-expired ones).
    func refreshEntitlement() async {
        var premium = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result,
               PremiumProduct.all.contains(t.productID),
               t.revocationDate == nil {
                premium = true
            }
        }
        isPremium = premium
    }

    func purchase(_ product: Product) async {
        purchasingID = product.id
        defer { purchasingID = nil }
        guard let result = try? await product.purchase() else { return }
        if case .success(.verified(let t)) = result {
            await t.finish()
            await refreshEntitlement()
        }
    }

    /// Restore prior purchases (incl. the legacy RN lifetime unlock) on this Apple ID.
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }
}
