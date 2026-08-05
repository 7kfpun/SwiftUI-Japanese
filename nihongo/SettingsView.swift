import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var appLanguage = L.deviceDefault
    @AppStorage("translationLanguage") private var vocabLanguage = VocabStore.defaultLanguage

    var body: some View {
        NavigationStack {
            Form {
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
            }
            .navigationTitle(L.t("Settings"))
        }
    }
}

#Preview { SettingsView() }
