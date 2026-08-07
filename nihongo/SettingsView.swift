import SwiftUI
import SafariServices

struct SettingsView: View {
    @AppStorage(Pref.appLanguage) private var appLanguage = L.deviceDefault
    @AppStorage(Pref.translationLanguage) private var vocabLanguage = VocabStore.defaultLanguage
    @Environment(Store.self) private var store
    @State private var showPaywall = false
    @State private var showFeedback = false
    @State private var legal: LegalDoc?

    /// Airtable feedback form (from the RN app), prefilled with the platform.
    private static let feedbackURL = URL(string: "https://airtable.com/shr7xvYAyInUbJNif?prefill_Platform=iOS")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.isPremium {
                        Label(L.t("Premium active"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.accent)
                        if store.tier != "lifetime" {
                            Button(L.t("Manage subscription")) {
                                Track.event("manage_subscription")
                                Task { await store.manageSubscriptions() }
                            }
                        }
                    } else {
                        Button(L.t("Unlock all lessons")) { showPaywall = true }
                        Button(L.t("Restore Purchases")) { Task { await store.restore() } }
                    }
                } header: {
                    Text(L.t("Premium"))
                }

                Section {
                    Picker(L.t("App language"), selection: $appLanguage) {
                        ForEach(L.availableLanguages, id: \.self) { code in
                            Text(VocabStore.displayName(code)).tag(code)
                        }
                    }
                } header: {
                    Text(L.t("Interface"))
                } footer: {
                    Text(L.t("The language used for the app's own text (tabs, buttons, labels)."))
                }

                Section {
                    Picker(L.t("Vocabulary language"), selection: $vocabLanguage) {
                        ForEach(VocabStore.availableLanguages, id: \.self) { code in
                            Text(VocabStore.displayName(code)).tag(code)
                        }
                    }
                } header: {
                    Text(L.t("Meanings"))
                } footer: {
                    Text(L.t("The language Japanese words are translated into (vocabulary lists, quizzes, and search)."))
                }

                Section {
                    Button { showFeedback = true; Track.event("open_feedback") } label: {
                        Label(L.t("Send feedback"), systemImage: "envelope")
                    }
                } header: {
                    Text(L.t("Feedback"))
                } footer: {
                    Text(L.t("Something wrong or missing? Feel free to reach out."))
                }

                Section {
                    Button(L.t("Privacy Policy")) { legal = .privacy }
                    Button(L.t("Terms of Use")) { legal = .terms }
                    Button(L.t("Licenses")) { legal = .licenses }
                } header: {
                    Text(L.t("Legal"))
                }
            }
            .navigationTitle(L.t("Settings"))
            .sheet(item: $legal) { doc in LegalView(titleKey: doc.titleKey, resource: doc.rawValue) }
            .onAppear { Track.screen("settings") }
            .onChange(of: appLanguage) { Track.event("set_app_language", ["code": appLanguage]) }
            .onChange(of: vocabLanguage) { Track.event("set_vocab_language", ["code": vocabLanguage]) }
            .sheet(isPresented: $showPaywall) { PaywallView(source: "settings") }
            .sheet(isPresented: $showFeedback) {
                SafariView(url: Self.feedbackURL).ignoresSafeArea()
            }
        }
    }
}

/// Opens a URL in an in-app Safari sheet (no bounce to the external browser).
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

#Preview { SettingsView().environment(Store()) }
