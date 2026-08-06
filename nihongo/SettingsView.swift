import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var appLanguage = L.deviceDefault
    @AppStorage("translationLanguage") private var vocabLanguage = VocabStore.defaultLanguage
    @Environment(Store.self) private var store
    @State private var showPaywall = false

    /// Airtable feedback form (from the RN app), prefilled with the platform.
    private static let feedbackURL = URL(string: "https://airtable.com/shr7xvYAyInUbJNif?prefill_Platform=iOS")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.isPremium {
                        Label(L.t("Premium active"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.accent)
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
                    Link(destination: Self.feedbackURL) {
                        Label(L.t("Send feedback"), systemImage: "envelope")
                    }
                } header: {
                    Text(L.t("Feedback"))
                } footer: {
                    Text(L.t("Something wrong or missing? Feel free to reach out."))
                }
            }
            .navigationTitle(L.t("Settings"))
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }
}

#Preview { SettingsView().environment(Store()) }
