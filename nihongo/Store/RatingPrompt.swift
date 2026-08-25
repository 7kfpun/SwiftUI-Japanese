import SwiftUI
import StoreKit

/// Asks for a rating, but only from people who have earned the right to be asked, and
/// no more than once every couple of months.
///
/// The shape is deliberate: a *custom* star picker first, and only a 4- or 5-star pick
/// hands off to Apple's real review sheet. A low pick opens the in-app feedback sheet
/// instead (`FeedbackView`, with the chosen stars attached). Apple's sheet gives no signal
/// about what was submitted and is rate-limited to a handful of impressions a year, so
/// spending one on someone about to leave two stars wastes the only asks the app gets.
/// Routing unhappy taps to the feedback sheet turns the same moment into something
/// actionable — and the person gets a reply rather than a one-way star.
///
/// Note this is not a rating *gate*: the App Store prohibits making a review path
/// conditional on sentiment, and nothing here blocks anyone. The star row is the app's
/// own question, every answer leads somewhere, and the App Store page stays reachable
/// from Settings regardless.
enum RatingPrompt {
    /// How long the app waits before it may ask again.
    ///
    /// This used to be "once, ever", justified by Apple silently swallowing a second ask —
    /// which was true while a second ask produced *nothing*. It produces something now:
    /// every star tap writes a `Survey.Rating` row before branching, so a later ask buys
    /// sentiment over time even on the occasions Apple's sheet never appears.
    ///
    /// Two months, which still sits inside Apple's own cap of about three review
    /// impressions per year rather than fighting it. Asking monthly would mostly produce
    /// star rows whose 4★+ half leads nowhere, which reads to the user as a prompt that
    /// does nothing.
    static let askAgainAfter: TimeInterval = 60 * 24 * 60 * 60

    /// When the star row was last shown, or `nil` if it never has been.
    static var lastAskedAt: Date? {
        let stamp = UserDefaults.standard.double(forKey: Pref.ratingAskedAt)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Whether enough time has passed. `nil` (never asked) qualifies.
    static var mayAskAgain: Bool {
        guard let last = lastAskedAt else { return true }
        return Date().timeIntervalSince(last) >= askAgainAfter
    }

    /// Stamps *now*, and clears the legacy boolean it replaces.
    ///
    /// The old `Pref.ratingAsked` shipped only in the unreleased 3.0.0, so almost no install
    /// carries it — but a TestFlight tester's might, and `bool(forKey:)` on it would be
    /// `true` with no date to compare against. `migrateLegacyFlagIfNeeded` handles that read
    /// side; this handles the write side by retiring the key the moment we stamp a real date.
    static func markAsked() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Pref.ratingAskedAt)
        UserDefaults.standard.removeObject(forKey: Pref.ratingAsked)
    }

    /// A tester who was asked under the old boolean has no timestamp, which would otherwise
    /// read as "never asked" and prompt them immediately on updating. Treat the first check
    /// after the update as the ask: conservative, and it makes the window predictable
    /// instead of retroactive.
    static func migrateLegacyFlagIfNeeded() {
        guard lastAskedAt == nil,
              UserDefaults.standard.bool(forKey: Pref.ratingAsked) else { return }
        markAsked()
    }

    /// Clears the timer so the *real* trigger can fire again on this install.
    ///
    /// For the Diagnostics screen only, and it exists because the window is the one
    /// condition of `shouldAsk` that no amount of practising can undo — you can't wait two
    /// months to test a build. Nothing in the app calls this. Note it does not lift Apple's
    /// own throttle on the review sheet, so a second earned ask will still show the star row
    /// and may well show nothing after it.
    ///
    /// `removeObject` rather than writing a zero so both keys go back to absent, which is
    /// what a fresh install actually looks like.
    static func resetAsked() {
        UserDefaults.standard.removeObject(forKey: Pref.ratingAskedAt)
        UserDefaults.standard.removeObject(forKey: Pref.ratingAsked)
    }

    /// Rungs that must be passed before the app asks anything. Several lessons of real
    /// use — enough that there's something to rate, and high enough that the ask lands on
    /// people who stayed rather than people who looked.
    ///
    /// Deliberately three times the share nudge's bar: this one asks for a public verdict
    /// on the App Store, that one asks someone to mention the app to a friend.
    static let challengesRequired = 21

    /// Whether to ask after this challenge.
    ///
    /// **Everyone, not just subscribers.** This used to be subscribers-only, on the
    /// reasoning that a free user's most likely rating is about the paywall. The cost of
    /// that was steeper than the risk: it silenced the ask for the large majority of
    /// users, so almost nobody was ever asked at all, and the rungs-cleared bar already
    /// filters for people who have actually used the app rather than bounced off it.
    ///
    /// The two remaining conditions pick the moment: enough rungs cleared to have an
    /// opinion, and a rung they just *passed* — asking straight after a failure asks
    /// how they feel about failing, which is a different question.
    ///
    /// `isPremium` is still taken, and still ignored, so the call sites keep passing it:
    /// the star row's low path opens the feedback sheet, whose `Survey.Context` carries
    /// the tier, and that is where the free-versus-paid split is actually worth reading.
    static func shouldAsk(isPremium: Bool, passed: Bool, passedCount: Int) -> Bool {
        passed && passedCount >= challengesRequired && mayAskAgain
    }

    /// 4★ and up → Apple's review sheet. Apple decides whether it actually appears;
    /// there's no callback and no guarantee, which is exactly why the star row exists
    /// in front of it.
    @MainActor static func requestAppStoreReview() {
        guard let scene = UIApplication.shared.foregroundScene else { return }
        AppStore.requestReview(in: scene)
        // The last countable step of the rating funnel. Apple reports nothing back — not
        // whether the sheet appeared, not what was written — so this is only "we asked",
        // and that is exactly why it's worth having: `rating_given` with 4★+ minus this
        // is the number of hand-offs lost to a missing scene, and the gap between this
        // and the App Store's own review count is Apple's throttle at work.
        Track.event("review_requested")
    }
}

/// The star row itself. Deliberately not a `.alert`: an alert can't hold a tappable
/// star row, and the whole point is that the rating is chosen here rather than in
/// Apple's sheet.
struct RatingSheet: View {
    /// Called with the chosen 1–5 once the user commits.
    let onRate: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var stars = 0

    var body: some View {
        VStack(spacing: 20) {
            PromptHeader(icon: "sparkles",
                         title: L.t("Enjoying %@?", Course.current.displayName),
                         blurb: L.t("Tap a star to tell us how it's going."))

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        stars = i
                        // A beat on the filled star before the sheet goes, so the tap
                        // registers as an answer rather than just closing something.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            dismiss()
                            onRate(i)
                        }
                    } label: {
                        Image(systemName: i <= stars ? "star.fill" : "star")
                            .font(.system(size: 32))
                            .foregroundStyle(i <= stars ? Theme.accent : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("%@ stars", "\(i)"))
                }
            }
            .padding(.vertical, 4)

            // Leaves `onRate` uncalled, which is how the caller tells "no answer" from
            // a low one — the two mean different things and only one wants a follow-up.
            Button(L.t("Not now")) { dismiss() }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .scrollableWhenCramped()
        .presentationDetents([.height(340), .large])
    }
}
