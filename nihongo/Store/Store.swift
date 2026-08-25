import StoreKit
import UIKit

/// Premium product IDs — must match App Store Connect **and** the original RN app, so
/// existing lifetime buyers / subscribers restore automatically (a non-consumable stays
/// tied to the Apple ID forever; StoreKit 2 surfaces it via `currentEntitlements`).
enum PremiumProduct {
    /// The IDs themselves live on `Course` — they are per-app and must never be shared
    /// between two apps built from this codebase. Everything below is unchanged in shape.
    static var lifetime: String { Course.current.products.lifetime }
    /// Current subscription lineup in App Store Connect. Note the uppercase M on 3M/6M:
    /// product IDs are case-sensitive and immutable, and the lowercase 2019 IDs are
    /// reserved forever, so the new products had to differ.
    static var subscriptions: [String] { Course.current.products.subscriptions }
    /// Legacy RN-era subscriptions — no longer sold, still honored so old buyers restore.
    static var legacy: [String] { Course.current.products.legacy }
    /// What the paywall sells.
    static let purchasable = subscriptions + [lifetime]
    /// Everything that grants premium (incl. legacy) — used for the entitlement scan.
    static let all = purchasable + legacy
}

/// Free/premium gating: lessons 1…`freeLessonLimit` are free in full — every mode,
/// every challenge — and the rest need premium. Vocab List is the one exception, free
/// on every lesson, so browsing and search stay open.
///
/// One whole-lesson rule, not a card quota. A free user can *finish* the early lessons —
/// fill the progress bar, earn the stars — and meets the paywall carrying that momentum,
/// rather than being cut off mid-practice.
///
/// `freeMeaningPreview` is the single deliberate exception; see the note on it.
enum Gating {
    static var freeLessonLimit: Int { Course.current.freeLessonLimit }

    /// How many words "Play with meanings" reads on a *locked* lesson before the paywall
    /// appears. The one partial trial in the app, and it is one on purpose.
    ///
    /// Every other paid mode can be understood from its name and its row subtitle. This
    /// one can't: "reads the meaning aloud after each word" describes a rhythm — word,
    /// pause, meaning, pause — that means nothing until you've heard it. So the lesson's
    /// Vocab List, which is free at every lesson anyway, plays a few words properly and
    /// then asks. Nothing is withheld that isn't already on screen; only the voice is.
    ///
    /// Must stay below the smallest lesson in every course, or a "preview" would read the
    /// whole lesson and then charge for it — `previewStopsShortOfEveryLesson` guards that.
    static let freeMeaningPreview = 7

    /// The band earned by mastering the free lessons — Minna's "Beginning 1" (13
    /// lessons), JLPT's "N5" (19). Always `groups.first`: the reward has to be the
    /// stretch that *follows* the free lessons, or it unlocks nothing new.
    static var earnableGroup: Course.Group? { Course.current.groups.first }

    /// Three stars on every challenge of lessons 1…`freeLessonLimit`.
    ///
    /// Three stars, not merely passed: `Challenge.stars` gives three only for a clean
    /// 100%, so this is a real bar, and clearing it is a fair claim on more of the
    /// course. Passing would be no bar at all — the ladder already requires a pass to
    /// advance, so every free-lesson finisher would qualify by simply finishing.
    ///
    /// Pure, so it can be tested without a store. `rungs[lesson]` is how many challenges
    /// that lesson has; `threeStarred[lesson]` how many of them are cleanly swept.
    static func hasEarnedFirstGroup(rungs: [Int: Int], threeStarred: [Int: Int]) -> Bool {
        guard freeLessonLimit >= 1 else { return false }
        return (1...freeLessonLimit).allSatisfy { lesson in
            // A lesson with no known rung count hasn't been proven mastered — it has
            // only failed to be measured, which is not the same thing.
            guard let total = rungs[lesson], total > 0 else { return false }
            return threeStarred[lesson] == total
        }
    }

    /// The highest lesson playable without paying.
    static func freeThrough(earnedFirstGroup: Bool) -> Int {
        guard earnedFirstGroup, let band = earnableGroup else { return freeLessonLimit }
        // `max`, not just `band.last`: if a course ever set `freeLessonLimit` beyond its
        // first band, earning it must never take lessons away.
        return max(freeLessonLimit, band.last)
    }

    /// Playback speed in Read along is premium, and **the normal speed is not**.
    ///
    /// Free listeners keep the feature; what they don't get is the dial. That is the
    /// shape every gate in this app takes — nothing already on screen is taken away, and
    /// the paid thing is the one you can only appreciate by having used it. Slowing a
    /// clip to shadow it, or running a review lap at 1.5×, is worth paying for; being
    /// unable to *listen* would not be.
    ///
    /// `rate(for:)` rather than a bare boolean, because the honest failure mode matters:
    /// a lapsed subscriber has 1.2× sitting in `Pref.playbackRate`, and reading it back
    /// would silently keep handing them a paid benefit. This clamps to normal speed
    /// instead — the preference is remembered, not honoured, so resubscribing restores
    /// exactly what they had.
    static let normalRate = 1.0

    static func rate(_ stored: Double, isPremium: Bool) -> Double {
        isPremium ? stored : normalRate
    }

    /// True when a lesson needs premium (everything but Vocab List).
    ///
    /// `earnedFirstGroup` defaults to false so a caller that hasn't looked it up fails
    /// *closed* — showing a lock that a tap can clear, rather than opening a lesson that
    /// hasn't been earned.
    static func isLocked(lesson number: Int, isPremium: Bool, earnedFirstGroup: Bool = false) -> Bool {
        !isPremium && number > freeThrough(earnedFirstGroup: earnedFirstGroup)
    }

    /// How many of a lesson's `count` words Read along reads.
    ///
    /// The whole lesson, except for the meanings mode without premium, which gets
    /// `freeMeaningPreview`. `mode` is taken here rather than the caller checking
    /// `isPremium` itself because the Japanese-only mode is free on **every** lesson —
    /// the gate is on reading the meaning aloud, not on the button.
    ///
    /// **Premium, not lesson-locked.** This used to key off `isLocked`, which made the
    /// meanings mode free in full on lessons 1–5 and previewed everywhere after — so the
    /// same paid feature behaved differently depending on which lesson you opened it
    /// from, and a learner who never left the free lessons never discovered it was paid
    /// at all. The preview survives the change and now reaches everyone who hasn't
    /// subscribed: the rhythm it exists to demonstrate is exactly as unknown on lesson 1
    /// as on lesson 40.
    static func wordsToRead(mode: ReadMode, count: Int, isPremium: Bool) -> Int {
        guard mode.readsBeyondTheWord, !isPremium else { return count }
        return min(freeMeaningPreview, count)
    }

    /// Whether Read along may start over at the top and keep going indefinitely.
    ///
    /// **Subscribers only, in every mode.** Endless playback is the thing this feature is
    /// really for — a lesson running in the background while someone washes up — and it
    /// is the part that costs nothing to give and everything to give away. A free
    /// listener still hears the whole lesson, once, in Japanese-only; the loop is what
    /// they are being offered.
    ///
    /// `mode` is no longer read. It stays in the signature because the un-subscribed
    /// meanings *preview* depends on this returning false — the paywall hangs off
    /// `onFinished`, which a looping player never reaches — and a future mode that needs
    /// to loop for everyone would want to say so here rather than at its call site.
    static func loopsForever(mode: ReadMode, isPremium: Bool) -> Bool { isPremium }
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
        var entitled: [String] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil,
                  PremiumProduct.all.contains(t.productID) else { continue }
            entitled.append(t.productID)
        }

        isPremium = !entitled.isEmpty
        tier = Self.tier(from: entitled)
        Track.setPremium(isPremium, tier: tier)
    }

    /// One label for a set of simultaneous entitlements.
    ///
    /// Holding more than one is ordinary — a lifetime bought after subscribing, or an old
    /// subscription still running alongside it — and `currentEntitlements` is an async
    /// sequence with no promised order. Assigning the label inside the loop meant the
    /// last one seen won, so the same account could report a different tier on each
    /// launch and look like it was churning when nothing had changed.
    ///
    /// Lifetime outranks everything: it is permanent, so someone holding both is a
    /// lifetime owner whose subscription is incidental. Otherwise sorted, purely so the
    /// answer is stable rather than incidental.
    nonisolated static func tier(from entitled: [String]) -> String {
        if entitled.isEmpty { return "none" }
        if entitled.contains(PremiumProduct.lifetime) { return "lifetime" }
        return entitled.sorted().first.map(tierLabel) ?? "none"
    }

    /// `source` is the paywall entry point that led here — see `PaywallView.source`. It
    /// rides every purchase event so conversion can be grouped by where the paywall was
    /// triggered; without it the funnel stops at `paywall_shown` and which entry point
    /// actually earns money is a guess.
    func purchase(_ product: Product, source: String) async {
        purchasingID = product.id
        defer { purchasingID = nil }
        let tier = Self.tierLabel(product.id)
        let base: [String: Any] = ["tier": tier, "source": source]
        Track.event("purchase_start", base)
        guard let result = try? await product.purchase() else {
            Track.event("purchase_failed", base.merging(["reason": "error"]) { a, _ in a })
            return
        }
        switch result {
        case .success(.verified(let t)):
            await t.finish()
            await refreshEntitlement()
            Track.event("purchase_success", base)
        case .userCancelled:
            Track.event("purchase_failed", base.merging(["reason": "cancelled"]) { a, _ in a })
        case .pending:
            Track.event("purchase_failed", base.merging(["reason": "pending"]) { a, _ in a })
        default:
            Track.event("purchase_failed", base.merging(["reason": "unverified"]) { a, _ in a })
        }
    }

    /// Restore prior purchases (incl. the legacy RN lifetime unlock) on this Apple ID.
    /// The four ways a Restore tap can end. Reported as `outcome` on `restore`.
    ///
    /// The old event logged only `premium` — the entitlement *after* the tap — which
    /// cannot answer the one question worth asking. Someone already subscribed reported
    /// `premium: true` identically to someone whose restore genuinely recovered a
    /// purchase, and a cancelled sign-in reported `premium: false` identically to an
    /// Apple ID that never bought anything. Those two pairs need opposite support
    /// replies, so the event has to separate them.
    enum RestoreOutcome: String {
        /// Already entitled — the tap changed nothing, and nothing was wrong.
        case alreadyPremium = "already_premium"
        /// Not entitled before, entitled now. The restore did its job.
        case restored
        /// `AppStore.sync()` succeeded and found nothing: wrong Apple ID, or a purchase
        /// that was never made. **This is what most "restore is broken" reports are.**
        case nothingFound = "nothing_found"
        /// `sync()` threw — a cancelled Apple ID prompt, or no network.
        case failed
    }

    /// Restore prior purchases (incl. the legacy RN lifetime unlock) on this Apple ID.
    ///
    /// `source` distinguishes the paywall's Restore — a step inside a purchase decision —
    /// from Settings', which is usually someone who has just reinstalled. The same tap
    /// means different things there and the fix for a failure differs too.
    @discardableResult
    func restore(source: String) async -> RestoreOutcome {
        let wasPremium = isPremium

        var syncFailed: String?
        do {
            try await AppStore.sync()
        } catch {
            // Deliberately not `try?`: the throw is the single most informative thing
            // that can happen here, and swallowing it made a cancelled sign-in
            // indistinguishable from an account with no purchases.
            syncFailed = "\(error)"
        }
        await refreshEntitlement()

        let outcome: RestoreOutcome
        if syncFailed != nil          { outcome = .failed }
        else if wasPremium            { outcome = .alreadyPremium }
        else if isPremium             { outcome = .restored }
        else                          { outcome = .nothingFound }

        var params: [String: Any] = ["outcome": outcome.rawValue,
                                     "source": source,
                                     "premium": isPremium]
        // The message, never anything identifying — it names the failure mode
        // (cancelled, offline) which is exactly what a support reply turns on.
        if let syncFailed { params["error"] = syncFailed }
        Track.event("restore", params)
        return outcome
    }

    /// Apple's native manage-subscriptions sheet — where users switch tier (1m↔3m↔6m
    /// within the same group) or cancel. Refreshes entitlement on return.
    func manageSubscriptions() async {
        guard let scene = UIApplication.shared.foregroundScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        await refreshEntitlement()
    }

    /// Short tier label from a product ID (…premium.3M → "3m", lifetime → "lifetime").
    ///
    /// **Five labels, and only five**: `1m`, `3m`, `6m`, `12m`, `lifetime`. The label
    /// names the *plan*, not the SKU — the burned 2019 IDs differ from the current lineup
    /// only in case (`3m` vs `3M`), and lowercasing folds each onto its current twin
    /// deliberately. A legacy six-month subscriber and a new one are the same thing to
    /// every question this label answers, so they belong in the same bucket; a
    /// case-sensitive analytics value would be a reporting accident anyway.
    ///
    /// Where the distinction *does* matter — new sales versus restores — the events
    /// already carry it without help: `purchase_success` only ever fires for a
    /// purchasable product, and `restore` reports its own outcome.
    nonisolated static func tierLabel(_ id: String) -> String {
        id == PremiumProduct.lifetime ? "lifetime"
            : (id.components(separatedBy: ".").last ?? id).lowercased()
    }
}
