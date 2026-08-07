import SwiftUI

/// The bundled legal docs, usable as a `.sheet(item:)` selector.
enum LegalDoc: String, Identifiable {
    case privacy = "PrivacyPolicy"
    case terms = "TermsOfUse"
    case licenses = "KanjiStrokeOrders-LICENSE"   // third-party notices (BSD requires shipping them)
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .privacy: return "Privacy Policy"
        case .terms: return "Terms of Use"
        case .licenses: return "Licenses"
        }
    }
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
            .onAppear { Track.screen("legal", ["doc": resource]) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Done")) { dismiss() }
                }
            }
        }
    }
}
