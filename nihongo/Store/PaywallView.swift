import SwiftUI
import StoreKit

/// Premium paywall: buy a subscription or the lifetime unlock, or restore prior
/// purchases. Dismisses itself the moment premium becomes active.
struct PaywallView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var legal: LegalDoc?

    /// Where this paywall was triggered from (settings, a locked Today lesson, a
    /// locked mode row) — lets analytics tell which entry point actually converts.
    let source: String

    private let subscriptionTerms = "Auto-renewable subscriptions renew unless canceled at least 24 hours before the period ends. Payment is charged to your Apple ID; manage in Settings."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 44)).foregroundStyle(Theme.accent)
                    Text(L.t("Unlock all lessons")).font(Theme.title(.title, weight: .bold))
                    // Interpolated from Gating rather than written out, so the offer on
                    // screen can't drift from the rule the app actually enforces.
                    Text(L.t("Free through lesson %@ — unlock the rest and remove ads.",
                             "\(Gating.freeLessonLimit)"))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    features

                    if store.isLoadingProducts || !store.didAttemptLoad {
                        ProgressView().padding(.top, 8)
                    } else if store.productsUnavailable {
                        unavailable
                    } else {
                        VStack(spacing: 12) {
                            ForEach(store.subscriptions) { subscriptionRow($0) }
                        }
                        if let lifetime = store.lifetime { lifetimeRow(lifetime) }
                    }

                    Button(L.t("Restore Purchases")) {
                        Task { await store.restore() }
                    }
                    .font(.footnote)
                    .padding(.top, 4)

                    // App Review requires the auto-renewal disclosure + legal links.
                    Text(L.t(subscriptionTerms))
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    HStack(spacing: 18) {
                        Button(L.t("Terms of Use")) { legal = .terms }
                        Button(L.t("Privacy Policy")) { legal = .privacy }
                    }
                    .font(.caption2)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas)
            .navigationTitle(L.t("Premium"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancel")) {
                        Track.event("paywall_dismissed", ["source": source, "purchased": false])
                        dismiss()
                    }
                }
            }
            .sheet(item: $legal) { doc in LegalView(titleKey: doc.titleKey, resource: doc.rawValue) }
            .onAppear { Track.event("paywall_shown", ["source": source]) }
            // Retry on open. Products load once at launch, so a user who started the
            // app offline would otherwise face an empty paywall for the whole session.
            .task { if store.products.isEmpty { await store.load() } }
            .onChange(of: store.isPremium) { if store.isPremium { dismiss() } }
        }
    }

    /// Shown when the fetch came back empty. An eternal spinner told the user nothing
    /// and offered no way forward — this at least names the likely cause and lets them
    /// try again without relaunching the app.
    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title).foregroundStyle(.secondary)
            Text(L.t("Plans couldn't load. Check your connection and try again."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L.t("Try again")) {
                Task { await store.load() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            feature("All 50 lessons unlocked")
            feature("Every challenge, from lesson 1 to 50")
            feature("No ads, ever")
            // Both of these were wrong. "Flashcards, Learn, quizzes & listening" named two
            // modes that no longer exist — Quiz and Listening became the Challenge ladder
            // and Train — and "Native audio for every word" claimed native speakers when the
            // clips are `say -v Kyoko`, with two sentence templates having none at all.
            // Neither is a claim worth making on the screen that asks for money: what the
            // audio is *for* sells better than who recorded it, and it happens to be true.
            feature("Flashcards, Train, Learn and the full ladder")
            feature("Audio in every practice and learning task, to help it stick")
            feature("Study offline, anywhere")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func feature(_ key: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.correct)
            Text(L.t(key)).font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    /// A subscription option: term, price, and — the point of this row — the monthly
    /// equivalent plus what it saves. Listing four bare totals made the reader do the
    /// arithmetic to find the cheaper deal, which mostly means they didn't.
    private func subscriptionRow(_ product: Product) -> some View {
        let isBest = product.id == bestValue?.id
        return Button {
            Task { await store.purchase(product) }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(periodLabel(product)).font(Theme.title(.headline))
                        if isBest {
                            Text(L.t("Best value"))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    if let saved = savingsPercent(product) {
                        Text(L.t("Save %@%", "\(saved)"))
                            .font(.caption).foregroundStyle(Theme.correct)
                    }
                }
                Spacer()
                if store.purchasingID == product.id {
                    ProgressView()
                } else {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(product.displayPrice).font(Theme.title(.headline)).foregroundStyle(Theme.accent)
                        if let each = perMonthDisplay(product), months(product) > 1 {
                            Text(L.t("%@ / month", each))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(isBest ? Theme.accent.opacity(0.08) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isBest ? Theme.accent : Theme.line, lineWidth: isBest ? 2 : 1))
        }
        .buttonStyle(.plain)
        .disabled(store.purchasingID != nil)
    }

    /// Lifetime, set apart below a divider. It's a different commitment from a
    /// subscription, and as a fourth row in the same list it just read as the
    /// expensive one rather than an alternative.
    private func lifetimeRow(_ product: Product) -> some View {
        VStack(spacing: 12) {
            HStack {
                Rectangle().fill(Theme.line).frame(height: 1)
                Text(L.t("or")).font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            .padding(.top, 4)

            Button {
                Task { await store.purchase(product) }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.t("Lifetime")).font(Theme.title(.headline))
                        Text(L.t("Pay once, yours forever"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.purchasingID == product.id {
                        ProgressView()
                    } else {
                        Text(product.displayPrice).font(Theme.title(.headline)).foregroundStyle(Theme.accent)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            }
            .buttonStyle(.plain)
            .disabled(store.purchasingID != nil)
        }
    }

    // MARK: - Naming and price maths
    //
    // Plan names are built here from `subscriptionPeriod`, *not* taken from App Store
    // Connect's `displayName`. ASC localizations resolve by App Store **storefront**
    // (the Apple ID's region), while this app has its own in-app language picker — so
    // ASC text can't follow it. Reading it produced "6 Months / Premium, billed every
    // 6 months." in English sitting beside a Chinese "最超值" on the same row. StoreKit
    // hands back one localization, not all of them, so there's no hybrid that works:
    // anything that must match the in-app language has to come from UIStrings.json.
    //
    // Prices are the exception and stay with StoreKit: `displayPrice` and
    // `priceFormatStyle` render ¥/€/₩ correctly per storefront, which is right —
    // currency follows where you *pay*, not what language you read.
    //
    // Products arrive sorted by price ascending (`Store.load`), so the rows read
    // cheapest-first and `periodLabel` just names each one.

    /// Subscription length, in the app's own language.
    private func periodLabel(_ product: Product) -> String {
        let n = months(product)
        guard n > 0 else { return L.t("Lifetime") }
        return n == 1 ? L.t("1 month") : L.t("%@ months", "\(n)")
    }

    private func months(_ product: Product) -> Int {
        guard let period = product.subscription?.subscriptionPeriod else { return 0 }
        switch period.unit {
        case .year:  return period.value * 12
        case .month: return period.value
        case .week:  return max(1, period.value / 4)
        default:     return 1                      // daily plans aren't in the lineup
        }
    }

    private func perMonth(_ product: Product) -> Decimal? {
        let n = months(product)
        return n > 0 ? product.price / Decimal(n) : nil
    }

    private func perMonthDisplay(_ product: Product) -> String? {
        perMonth(product).map { $0.formatted(product.priceFormatStyle) }
    }

    /// The plan with the lowest monthly cost — recommended on merit, so the badge
    /// stays honest if the lineup or prices change.
    private var bestValue: Product? {
        store.subscriptions
            .filter { months($0) > 1 }
            .min { (perMonth($0) ?? .greatestFiniteMagnitude) < (perMonth($1) ?? .greatestFiniteMagnitude) }
    }

    /// Discount against the priciest month — i.e. what the shortest plan costs.
    private func savingsPercent(_ product: Product) -> Int? {
        guard let mine = perMonth(product), months(product) > 1,
              let baseline = store.subscriptions.compactMap(perMonth).max(),
              baseline > 0, mine < baseline else { return nil }
        let ratio = (baseline - mine) / baseline * 100
        let pct = Int(NSDecimalNumber(decimal: ratio).doubleValue.rounded())
        return pct >= 5 ? pct : nil            // don't advertise a rounding error
    }

}
