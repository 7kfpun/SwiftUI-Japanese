import SwiftUI
import SafariServices

struct SettingsView: View {
    @AppStorage(Pref.appLanguage) private var appLanguage = L.deviceDefault
    @AppStorage(Pref.translationLanguage) private var vocabLanguage = VocabStore.deviceDefaultLanguage
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @State private var showPaywall = false
    @State private var showFeedback = false
    @State private var legal: LegalDoc?
    @State private var analyticsExcluded = Track.isExcluded
    @State private var versionTapCount = 0

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
                    // Section headers keep the size and secondary colour a grouped list
                    // gives them and change only the face — a rounded heading over plain
                    // rows, same split as everywhere else. Promoting them to `.headline`
                    // would make the labels compete with the settings they label.
                    Text(L.t("Premium")).font(Theme.title(.footnote))
                }

                Section {
                    Picker(L.t("App language"), selection: $appLanguage) {
                        ForEach(L.availableLanguages, id: \.self) { code in
                            Text(VocabStore.displayName(code)).tag(code)
                        }
                    }
                } header: {
                    Text(L.t("Interface")).font(Theme.title(.footnote))
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
                    Text(L.t("Meanings")).font(Theme.title(.footnote))
                } footer: {
                    Text(L.t("The language Japanese words are translated into (vocabulary lists, quizzes, and search)."))
                }

                Section {
                    Button { showFeedback = true; Track.event("open_feedback") } label: {
                        Label(L.t("Send feedback"), systemImage: "envelope")
                    }
                } header: {
                    Text(L.t("Feedback")).font(Theme.title(.footnote))
                } footer: {
                    Text(L.t("Something wrong or missing? Feel free to reach out."))
                }

                Section {
                    Button(L.t("Privacy Policy")) { legal = .privacy }
                    Button(L.t("Terms of Use")) { legal = .terms }
                    Button(L.t("Licenses")) { legal = .licenses }
                } header: {
                    Text(L.t("Legal")).font(Theme.title(.footnote))
                } footer: {
                    // Tap 7 times to exclude this device from analytics — a hidden
                    // developer toggle, not a normal end-user setting, so no
                    // localized label; the small suffix is the only visible cue.
                    Text(AppInfo.version + (analyticsExcluded ? " • Analytics off" : ""))
                        .onTapGesture {
                            versionTapCount += 1
                            guard versionTapCount >= 7 else { return }
                            versionTapCount = 0
                            analyticsExcluded.toggle()
                            Track.setExcluded(analyticsExcluded)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        // Second hidden developer affordance on the same footer: long-press
                        // replays the first-launch tour. A distinct *gesture* rather than a
                        // different tap count, so the two can't fire on the way to each
                        // other — a 3-tap trigger would be unreachable past the 7-tap one.
                        // Goes through `Router` because the cover lives above the TabView;
                        // it deliberately doesn't clear `Pref.introAnswered`, so replaying
                        // the tour doesn't make this install look brand new.
                        .onLongPressGesture {
                            router.replayIntro = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

#Preview { SettingsView().environment(Store()).environment(Router()) }
