import SwiftUI
import SwiftData
#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// One home for the developer affordances that used to be stacked on the version footer.
///
/// There were two hidden gestures on that one line of text — seven taps for the analytics
/// opt-out, a long-press to replay the intro — and a third would have had to be some
/// other tap count nobody could remember, competing with the first for the same finger.
/// A single gesture that opens a *list* scales instead: the next affordance is a row, not
/// another gesture.
///
/// **Unlocalized on purpose.** This is not an end-user surface — in Release and TestFlight
/// it's reachable only by a gesture with no visible cue (DEBUG adds a plainly-labelled row
/// in Settings, for the developer's own convenience), and every string here names a build,
/// a token or a preference key. The 7-tap toggle it replaces was unlocalized for the same
/// reason, and translating it would mean 17 copies of "App Check debug token" for an
/// audience of one.
struct DiagnosticsView: View {
    /// Set on the way out when the intro tour was asked for, and acted on by the presenting
    /// screen's `onDismiss`.
    ///
    /// The tour's cover lives above the whole `TabView` (see `Router.replayIntro`), so it
    /// can't be raised from inside this sheet: asking to present it while the sheet is
    /// still animating away is silently dropped. Same hazard, and the same fix, as the
    /// star row's two destinations in `ChallengeView`.
    @Binding var pendingReplayIntro: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var analyticsExcluded = Track.isExcluded

    /// Which feedback sheet to raise, if any.
    ///
    /// One `sheet(item:)` rather than a flag per row, because the two rows that lead here
    /// want different values: the plain row is `.hidden` with no stars, the star row's low
    /// path is `.rating` carrying the pick. Source is what the collection is grouped by,
    /// so a test row that lied about it would be worse than no test row.
    @State private var feedbackRequest: FeedbackRequest?

    /// The star row, and the pick it produced. `nil` stars means it was dismissed without
    /// answering, which routes nowhere — same distinction `ChallengeView` draws.
    @State private var showRating = false
    @State private var ratedStars: Int?

    /// Mirrors of the two once-ever flags, so the rows below re-read after a reset. Both
    /// are plain `UserDefaults` keys with no publisher behind them, so nothing would
    /// redraw on its own.
    @State private var ratingAsked = RatingPrompt.lastAskedAt != nil
    @State private var introAnswered = UserDefaults.standard.bool(forKey: Pref.introAnswered)
    @State private var shareAskedAt = SharePrompt.lastAskedAt
    @State private var showSharePrompt = false
    @State private var showShareSheet = false

    private struct FeedbackRequest: Identifiable {
        let id = UUID()
        let source: Feedback.Source
        let stars: Int
    }

    /// The exact map a submission would carry, resolved now. Read here so a tester can
    /// check what the row will say *before* sending one — the collection is write-only, so
    /// this is the only way to see it.
    private var context: [String: Any] {
        Survey.Context(store: store, modelContext: modelContext).fields
    }

    private var contextLines: [(key: String, value: String)] {
        context.keys.sorted().map { ($0, String(describing: context[$0]!)) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Actions") {
                    Button("Replay the intro tour") {
                        pendingReplayIntro = true
                        dismiss()
                    }
                    Button("Open the feedback survey") {
                        feedbackRequest = FeedbackRequest(source: .hidden, stars: 0)
                    }
                }

                Section {
                    // Bypasses `RatingPrompt.shouldAsk` on purpose and does not touch
                    // `Pref.ratingAsked`: the gate (subscriber, fifteen passed rungs, once)
                    // is a product decision about not wasting Apple's few review
                    // impressions, not an obstacle to be relaxed for convenience. This row
                    // shows the same sheet the earned path shows and routes it the same
                    // way, so what gets tested is the real thing — the only difference is
                    // how it was reached.
                    Button("Show the star row") { showRating = true }
                    Button("Request Apple's review sheet") {
                        RatingPrompt.requestAppStoreReview()
                    }
                } header: {
                    Text("Rating")
                } footer: {
                    Text("The star row routes exactly as it does after a passed rung: 4★ and up to Apple's review sheet, below that to the feedback sheet with the stars attached. Apple decides whether its own sheet appears and allows only a few impressions a year per install — nothing showing is not a bug.")
                }

                Section {
                    // Same discipline as the star row above: shows the real sheet and
                    // routes it the real way, bypassing only `shouldAsk`. The month-long
                    // window is the one condition nothing can practise past.
                    Button("Show the recommend nudge") { showSharePrompt = true }
                    Button("Open the share sheet") { showShareSheet = true }
                    LabeledContent("Nudge last shown",
                                   value: SharePrompt.lastAskedAt
                                       .map { $0.formatted(date: .abbreviated, time: .shortened) }
                                       ?? "never")
                    LabeledContent("Rungs required", value: "\(SharePrompt.challengesRequired)")
                    Button("Reset the monthly window") {
                        SharePrompt.resetAsked()
                        shareAskedAt = SharePrompt.lastAskedAt
                    }
                } header: {
                    Text("Recommend to a friend")
                } footer: {
                    Text("Fires after a passed rung once \(SharePrompt.challengesRequired) rungs are cleared, at most once every \(Int(SharePrompt.askAgainAfter / 86_400)) days. It stands down entirely on any rung where the star row appears — the rating is additionally rate-limited by Apple, so a wasted occasion costs it more. Sends people to \(Course.current.appStoreURL).")
                }

                Section {
                    LabeledContent("Star row asked", value: ratingAsked ? "yes" : "no")
                    LabeledContent("Rungs required", value: "\(RatingPrompt.challengesRequired)")
                    LabeledContent("Intro answered", value: introAnswered ? "yes" : "no")
                    Button("Reset the once-ever flags") { resetOnceEverFlags() }
                } header: {
                    Text("Once-ever flags")
                } footer: {
                    // The rows above bypass the triggers; this one is what makes the
                    // triggers themselves testable more than once per install, which is a
                    // different thing and the only way to check that the earned path still
                    // fires at all.
                    Text("Clears ratingAsked and introAnswered, so the real triggers can fire again: the star row after the next passed rung (subscriber, \(RatingPrompt.challengesRequired) passed rungs), and the intro cover on next launch — RootView reads that flag once at startup, so use the row above to see the tour now. Apple's own throttle on the review sheet is not affected.")
                }

                Section {
                    Toggle("Exclude this device from analytics", isOn: $analyticsExcluded)
                        .onChange(of: analyticsExcluded) { Track.setExcluded(analyticsExcluded) }
                } header: {
                    Text("Analytics")
                } footer: {
                    // Worth spelling out on the one screen that can change it: the switch
                    // governs Analytics and Crashlytics only. Survey writes are deliberately
                    // not gated on it — a volunteered answer isn't telemetry — which is why
                    // the resolved context below reports the switch's state as a field.
                    Text("Applies to Analytics and Crashlytics. Survey submissions ignore it by design; they carry analytics_excluded instead. DEBUG builds are excluded regardless.")
                }

                Section {
                    ForEach(contextLines, id: \.key) { line in
                        LabeledContent(line.key, value: line.value)
                            .textSelection(.enabled)
                    }
                    Button("Copy") { copy(contextText) }
                } header: {
                    Text("Submitted context")
                } footer: {
                    Text("Every survey row carries exactly these fields, plus the answers and a server-stamped `at`. The key set has to match firestore.rules — if it doesn't, every write is rejected and the only sign is a console line.")
                }

                Section {
                    if let token = Self.appCheckDebugToken {
                        Text(token)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                        Button("Copy") { copy(token) }
                    } else {
                        Text("No debug token on this build.")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Firebase", value: Self.isFirebaseConfigured ? "configured" : "not configured")
                } header: {
                    Text("App Check")
                } footer: {
                    // The token has to be pasted into Firebase → App Check → Apps → Manage
                    // debug tokens, which is why it needs to be copyable from the device
                    // rather than fished out of an Xcode console the tester may not have.
                    Text("Register this under App Check → Apps → Manage debug tokens, or every survey write from this install is rejected. DEBUG only — Release builds attest with App Attest and have no token.")
                }

                Section("Build") {
                    LabeledContent("Version", value: AppInfo.version)
                    LabeledContent("Configuration", value: AppInfo.isDebugBuild ? "Debug" : "Release")
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // `onDismiss`, not the star tap — same hazard as `pendingReplayIntro` above,
            // spelled out on `ChallengeView`'s copy of this pair.
            .sheet(isPresented: $showRating, onDismiss: routeRating) {
                RatingSheet { ratedStars = $0 }
            }
            .sheet(item: $feedbackRequest) { request in
                FeedbackView(source: request.source, stars: request.stars)
            }
            .sheet(isPresented: $showSharePrompt) {
                ShareSheetPrompt { showShareSheet = true }
            }
            .shareSheet(isPresented: $showShareSheet,
                        items: [SharePrompt.appStoreURL, SharePrompt.shareText()])
        }
    }

    /// Where the stars lead — the Diagnostics copy of `ChallengeView.routeRating()`, run
    /// once the star row has finished dismissing.
    ///
    /// Deliberately the same routing rather than a shortcut to one destination: a test that
    /// jumps straight to the feedback sheet proves the sheet works, not that the branch
    /// does. 4★ and up hands off to Apple's review sheet, anything lower opens feedback
    /// with the pick attached, and a dismissal without a pick leads nowhere.
    ///
    /// The stars are read into a local *before* `ratedStars` is cleared, and travel to the
    /// sheet inside `FeedbackRequest`. Reading `ratedStars` again when the sheet is built
    /// would report every low rating as 0 — the reason `ChallengeView` keeps a second
    /// `feedbackStars` property.
    private func routeRating() {
        guard let stars = ratedStars else {
            Track.event("rating_dismissed", ["source": "diagnostics"])
            return
        }
        ratedStars = nil
        Track.event("rating_given", ["stars": stars, "source": "diagnostics"])
        // Recorded before the branch, exactly as `ChallengeView.routeRating()` does — so a
        // rating taken from here exercises the real write path rather than only the UI.
        // These rows carry `debug: true`, which is how they're filtered out of real results.
        Survey.submit(Survey.Rating(stars: stars),
                      context: .init(store: store, modelContext: modelContext))
        if stars >= 4 {
            RatingPrompt.requestAppStoreReview()
        } else {
            feedbackRequest = FeedbackRequest(source: .rating, stars: stars)
        }
    }

    /// Puts both "once, ever" keys back to absent — what a fresh install looks like.
    ///
    /// Only these two. The intro's *answers* (`knowsKana`, `textbookLesson`, `goal`) stay:
    /// they're recorded facts about this person rather than presentation state, and wiping
    /// them would also move the app's starting tab, which is a surprise nobody asked this
    /// row for. Replaying the tour overwrites them anyway if that's what's wanted.
    private func resetOnceEverFlags() {
        RatingPrompt.resetAsked()
        UserDefaults.standard.removeObject(forKey: Pref.introAnswered)
        ratingAsked = RatingPrompt.lastAskedAt != nil
        introAnswered = UserDefaults.standard.bool(forKey: Pref.introAnswered)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private var contextText: String {
        contextLines.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// The App Check debug token, when this build has one.
    ///
    /// Read out of `UserDefaults` and the environment rather than from
    /// `AppCheckDebugProvider`, so this compiles and behaves identically in a clone with
    /// no Firebase packages linked. Those are the two places the debug provider itself
    /// looks: it honours the `FIRAAppCheckDebugToken` environment variable (how CI injects
    /// one) and otherwise generates a token on first launch and persists it under the same
    /// name. A Release build has neither, which is the correct answer — it attests with
    /// App Attest and there is no token to register.
    static var appCheckDebugToken: String? {
        let key = "FIRAAppCheckDebugToken"
        if let injected = ProcessInfo.processInfo.environment[key], !injected.isEmpty {
            return injected
        }
        let stored = UserDefaults.standard.string(forKey: key)
        return (stored?.isEmpty == false) ? stored : nil
    }

    /// Whether Firebase actually started — nil in an open-source clone with no
    /// `GoogleService-Info.plist`, which is exactly when "my survey isn't arriving" has a
    /// boring explanation.
    static var isFirebaseConfigured: Bool {
        #if canImport(FirebaseCore)
        return FirebaseApp.app() != nil
        #else
        return false
        #endif
    }
}

#Preview {
    DiagnosticsView(pendingReplayIntro: .constant(false))
        .tint(Theme.accent)
        .environment(Store())
        .modelContainer(for: [KanaResult.self, ChallengeResult.self, StudyDay.self, Bookmark.self], inMemory: true)
}
