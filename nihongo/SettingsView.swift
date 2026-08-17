import SwiftUI
import SwiftData   // the preview builds a container; Diagnostics reads ChallengeResult

struct SettingsView: View {
    @AppStorage(Pref.appLanguage) private var appLanguage = L.deviceDefault
    @AppStorage(Pref.translationLanguage) private var vocabLanguage = VocabStore.deviceDefaultLanguage
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    /// Only so the reminder can be re-planned against today's real state when the toggle
    /// or the hour changes — a plan built from a guess would nag someone already done.
    @Environment(\.modelContext) private var context
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
    @AppStorage(Pref.streakReminderOn) private var streakReminderOn = false
    @AppStorage(Pref.streakReminderHour) private var streakReminderHour = StreakReminder.defaultHour
    /// iOS only ever asks once. When the answer was no, the toggle can't do anything and
    /// must say so rather than sit there looking functional.
    @State private var notificationsDenied = false
    @State private var showReminderOffConfirm = false
    /// Guards the writes the dialog's own buttons make, which re-enter `onChange` and
    /// would otherwise raise the dialog a second time.
    @State private var suppressOffConfirm = false

    /// The hour as the learner's locale writes it — "8 PM" or "20:00" — rather than a
    /// bare number, which is ambiguous in every 12-hour region.
    private static func hourLabel(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour; c.minute = 0
        guard let date = Calendar.current.date(from: c) else { return "\(hour)" }
        return date.formatted(.dateTime.hour().minute())
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
                        Button(L.t("Restore Purchases")) { Task { await store.restore(source: "settings") } }
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
                    Toggle(L.t("Daily reminder"), isOn: $streakReminderOn)
                    if streakReminderOn {
                        Picker(L.t("Reminder time"), selection: $streakReminderHour) {
                            // Whole hours only. A minute picker implies a precision the
                            // feature doesn't have — the reminder is "some time this
                            // evening", not an appointment.
                            ForEach(6...23, id: \.self) { hour in
                                Text(Self.hourLabel(hour)).tag(hour)
                            }
                        }
                    }
                } header: {
                    Text(L.t("Reminders")).font(Theme.title(.footnote))
                } footer: {
                    Text(notificationsDenied
                         ? L.t("Notifications are turned off for this app in iOS Settings.")
                         : L.t("A nudge on any day you haven't studied yet. Nothing is sent when you're already done."))
                }

                Section {
                    ShareAppLink()
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
            .task { notificationsDenied = await StreakReminder.authorizationStatus() == .denied }
            // Permission is requested here — on an explicit "yes, remind me" — and nowhere
            // else. If iOS says no, the toggle goes back off rather than staying on over a
            // reminder that can never fire.
            .onChange(of: streakReminderOn) { _, on in
                // Turning it *off* asks first. Not a dark pattern and not a second toggle:
                // the confirm exists because switching this off is usually a reaction to
                // one badly-timed alert, and the thing worth saying — it stays quiet on
                // days you've already studied — is exactly what the person who just got
                // annoyed doesn't know yet. "Turn off" remains the default action.
                if !on && !suppressOffConfirm {
                    showReminderOffConfirm = true
                    return
                }
                Task {
                    if on {
                        let granted = await StreakReminder.requestAuthorization()
                        notificationsDenied = !granted
                        if !granted { streakReminderOn = false; return }
                        await PushService.shared.registerIfAuthorized()
                    }
                    await StreakReminder.reschedule(studiedToday: StudyDay.streak(context: context).studiedToday)
                    Track.event("streak_reminder", ["on": on, "hour": streakReminderHour])
                }
            }
            .confirmationDialog(L.t("Turn off the daily reminder?"),
                                isPresented: $showReminderOffConfirm, titleVisibility: .visible) {
                Button(L.t("Turn off"), role: .destructive) {
                    // `suppressOffConfirm` stops the re-entrant `onChange` this write
                    // triggers from raising the same dialog again.
                    suppressOffConfirm = true
                    streakReminderOn = false
                    suppressOffConfirm = false
                    Task {
                        await StreakReminder.reschedule(studiedToday: StudyDay.streak(context: context).studiedToday)
                        Track.event("streak_reminder", ["on": false, "hour": streakReminderHour])
                    }
                }
                Button(L.t("Keep it on"), role: .cancel) {
                    // Put the switch back: the binding already flipped to draw the tap.
                    suppressOffConfirm = true
                    streakReminderOn = true
                    suppressOffConfirm = false
                    Track.event("streak_reminder_kept")
                }
            } message: {
                Text(L.t("Most people who lose a streak simply forgot. The reminder only arrives on days you haven't studied — and never once you're done."))
            }
            .onChange(of: streakReminderHour) { _, hour in
                Task {
                    await StreakReminder.reschedule(studiedToday: StudyDay.streak(context: context).studiedToday)
                    Track.event("streak_reminder_hour", ["hour": hour])
                }
            }
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
        .modelContainer(for: [KanaResult.self, ChallengeResult.self, StudyDay.self, Bookmark.self], inMemory: true)
}
