import SwiftUI
import SwiftData   // the preview builds a container; Diagnostics reads ChallengeResult

struct SettingsView: View {
    @AppStorage(Pref.appLanguage) private var appLanguage = L.deviceDefault
    @AppStorage(Pref.translationLanguage) private var vocabLanguage = VocabStore.deviceDefaultLanguage
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @State private var showPaywall = false
    @State private var showFeedback = false
    @State private var legal: LegalDoc?
    @State private var showDiagnostics = false
    /// Raised inside the Diagnostics sheet, acted on once it has closed — see
    /// `DiagnosticsView.pendingReplayIntro`.
    @State private var pendingReplayIntro = false
    /// Only for the footer's suffix; the switch itself moved to Diagnostics. Re-read when
    /// that sheet closes, since it's the one place that can change it.
    @State private var analyticsExcluded = Track.isExcluded

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
                    Button { showFeedback = true } label: {
                        Label(L.t("Send feedback"), systemImage: "envelope")
                    }
                } header: {
                    Text(L.t("Feedback")).font(Theme.title(.footnote))
                } footer: {
                    Text(L.t("Something wrong or missing? Feel free to reach out."))
                }

                #if DEBUG
                // The same sheet the long-press below opens, as an ordinary row — but only
                // in a DEBUG build, so it can never reach a user. TestFlight and the App
                // Store both ship the Release configuration, where this section doesn't
                // exist and the hidden gesture is the only way in.
                //
                // It's here because a gesture is fine as a one-off escape hatch and awful
                // as a development loop: every check of the intro, the star row or a survey
                // context now starts with remembering to long-press a line of version text.
                //
                // Unlocalized, like the screen it opens and like the affordance it doubles:
                // "DEBUG" in front of it says loudly that it isn't a feature, and 17
                // translations of a word only the developer will ever read is 17 strings
                // that have to be kept in parity forever.
                Section {
                    Button { showDiagnostics = true } label: {
                        Label("DEBUG · Diagnostics", systemImage: "ant.fill")
                    }
                } footer: {
                    Text("Debug builds only. Release and TestFlight keep the long-press on the version below.")
                }
                #endif

                Section {
                    Button(L.t("Privacy Policy")) { legal = .privacy }
                    Button(L.t("Terms of Use")) { legal = .terms }
                    Button(L.t("Licenses")) { legal = .licenses }
                } header: {
                    Text(L.t("Legal")).font(Theme.title(.footnote))
                } footer: {
                    // The one hidden developer gesture in the app: long-press the version to
                    // open Diagnostics. One gesture, not several competing tap counts on the
                    // same line — everything else developer-only is a row on that screen.
                    //
                    // A long-press rather than a tap count because a footer that responds
                    // to ordinary taps invites discovery, and this isn't an end-user
                    // surface. The suffix stays as the only at-a-glance cue that this
                    // device is excluded from analytics.
                    Text(AppInfo.version + (analyticsExcluded ? " • Analytics off" : ""))
                        .onLongPressGesture {
                            showDiagnostics = true
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
            .sheet(isPresented: $showFeedback) { FeedbackView(source: .settings) }
            // `onDismiss` for the same reason the star row uses it: the intro tour's cover
            // lives above the whole `TabView`, and raising it while this sheet is still
            // animating away is silently dropped.
            .sheet(isPresented: $showDiagnostics, onDismiss: leaveDiagnostics) {
                DiagnosticsView(pendingReplayIntro: $pendingReplayIntro)
            }
        }
    }

    private func leaveDiagnostics() {
        analyticsExcluded = Track.isExcluded
        guard pendingReplayIntro else { return }
        pendingReplayIntro = false
        // Deliberately not clearing `Pref.introAnswered` — see `Router.replayIntro`.
        router.replayIntro = true
    }
}

#Preview {
    SettingsView()
        .environment(Store())
        .environment(Router())
        .modelContainer(for: [KanaResult.self, ChallengeResult.self], inMemory: true)
}
