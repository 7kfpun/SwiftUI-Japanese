import SwiftUI
import StoreKit

/// Premium paywall: buy a subscription or the lifetime unlock, or restore prior
/// purchases. Dismisses itself the moment premium becomes active.
struct PaywallView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 44)).foregroundStyle(Theme.accent)
                    Text(L.t("Unlock all lessons")).font(.title2.bold())
                    Text(L.t("Free through lesson 5 — unlock the rest and remove ads."))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

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
            .onChange(of: store.isPremium) { if store.isPremium { dismiss() } }
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
