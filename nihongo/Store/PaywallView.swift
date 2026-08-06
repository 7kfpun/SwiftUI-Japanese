import SwiftUI
import StoreKit

/// Premium paywall: buy a subscription or the lifetime unlock, or restore prior
/// purchases. Dismisses itself the moment premium becomes active.
struct PaywallView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var legal: LegalDoc?

    private let subscriptionTerms = "Auto-renewable subscriptions renew unless canceled at least 24 hours before the period ends. Payment is charged to your Apple ID; manage in Settings."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 44)).foregroundStyle(Theme.accent)
                    Text(L.t("Unlock all lessons")).font(.title.bold())
                    Text(L.t("Free through lesson 5 — unlock the rest and remove ads."))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    features

                    if store.products.isEmpty {
                        ProgressView().padding(.top, 8)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(store.products) { product in
                                productRow(product)
                            }
                        }
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
                    Button(L.t("Cancel")) { dismiss() }
                }
            }
            .sheet(item: $legal) { doc in LegalView(titleKey: doc.titleKey, resource: doc.rawValue) }
            .onAppear { Track.event("paywall_shown") }
            .onChange(of: store.isPremium) { if store.isPremium { dismiss() } }
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            feature("All 50 lessons unlocked")
            feature("No ads, ever")
            feature("Unlimited flashcards, quizzes & listening")
            feature("Native audio for every word")
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

    private func productRow(_ product: Product) -> some View {
        Button {
            Task { await store.purchase(product) }
        } label: {
            HStack {
                Text(periodLabel(product)).font(.headline)
                Spacer()
                if store.purchasingID == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice).font(.headline).foregroundStyle(Theme.accent)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator)))
        }
        .buttonStyle(.plain)
        .disabled(store.purchasingID != nil)
    }

    /// "Lifetime" for the non-consumable; else the subscription length in months.
    private func periodLabel(_ product: Product) -> String {
        guard let sub = product.subscription else { return L.t("Lifetime") }
        let p = sub.subscriptionPeriod
        let months = p.unit == .year ? p.value * 12 : p.value
        return L.t("%@ months", "\(months)")
    }
}
