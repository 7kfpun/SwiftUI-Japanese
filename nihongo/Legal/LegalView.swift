import SwiftUI

/// The two bundled legal docs, usable as a `.sheet(item:)` selector.
enum LegalDoc: String, Identifiable {
    case privacy = "PrivacyPolicy"
    case terms = "TermsOfUse"
    var id: String { rawValue }
    var titleKey: String { self == .privacy ? "Privacy Policy" : "Terms of Use" }
}

/// Shows a bundled legal document (Privacy Policy / Terms of Use) in a scrollable sheet.
struct LegalView: View {
    let titleKey: String
    let resource: String
    @Environment(\.dismiss) private var dismiss

    private var text: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(L.t(titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Done")) { dismiss() }
                }
            }
        }
    }
}
