import SwiftUI
import SafariServices

struct SettingsView: View {
    @AppStorage(Pref.appLanguage) private var appLanguage = L.deviceDefault
    @AppStorage(Pref.translationLanguage) private var vocabLanguage = VocabStore.defaultLanguage
    @Environment(Store.self) private var store
    @State private var showPaywall = false
    @State private var showFeedback = false
    @State private var legal: LegalDoc?
    @State private var analyticsExcluded = Track.isExcluded
    @State private var versionTapCount = 0

    private static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }


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
                } footer: {
                    // Tap 7 times to exclude this device from analytics — a hidden
                    // developer toggle, not a normal end-user setting, so no
                    // localized label; the small suffix is the only visible cue.
                    Text(Self.appVersion + (analyticsExcluded ? " • Analytics off" : ""))
                        .onTapGesture {
                            versionTapCount += 1
                            guard versionTapCount >= 7 else { return }
                            versionTapCount = 0
                            analyticsExcluded.toggle()
                            Track.setExcluded(analyticsExcluded)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                }
            }
            .navigationTitle(L.t("Settings"))
            .sheet(item: $legal) { doc in LegalView(titleKey: doc.titleKey, resource: doc.rawValue) }
            .onAppear { Track.screen("settings") }
            .onChange(of: appLanguage) { Track.event("set_app_language", ["code": appLanguage]) }
            .onChange(of: vocabLanguage) { Track.event("set_vocab_language", ["code": vocabLanguage]) }
            .sheet(isPresented: $showPaywall) { PaywallView(source: "settings") }
            .sheet(isPresented: $showFeedback) {
                SafariView(url: Feedback.url(source: "settings")).ignoresSafeArea()
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
