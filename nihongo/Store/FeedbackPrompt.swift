import SwiftUI

/// The "what isn't working?" ask, offered after a run has fallen short more than once.
///
/// Deliberately the occasion `RatingPrompt` refuses. That one documents why it waits for a
/// *passed* rung — "asking straight after a failure asks how they feel about failing, which
/// is a different question". It is a different question, and it is precisely the one this
/// prompt wants: someone who has missed the bar three times has something specific to say,
/// and is being asked to describe a problem rather than to do the app a favour.
///
/// **No precedence rule is needed**, which is the point of putting it here. The rating and
/// the share nudge both require `passed`; this one requires the opposite, so the three can
/// never contend for a single occasion the way `SharePrompt` has to guard against for the
/// rating. The windows still live in separate keys, because a shared one would let whichever
/// fired last silence the others.
enum FeedbackPrompt {
    /// Missed runs before the app asks.
    ///
    /// Three, not one. A single miss is ordinary learning — the honest answer to "what went
    /// wrong?" there is "nothing, I'm still learning it", and asking turns a normal retry
    /// into a suggestion that something is broken. Three is a pattern the sender can
    /// actually describe, and it is still low enough to catch someone before they leave.
    static let missesRequired = 3

    /// How long a shown prompt stays quiet, matching the other two.
    ///
    /// Equal to `RatingPrompt.askAgainAfter` and `SharePrompt.askAgainAfter` on purpose, and
    /// pinned to them by test: what separates these prompts is what they ask and which
    /// outcome triggers them, never their cadence.
    static let askAgainAfter: TimeInterval = RatingPrompt.askAgainAfter

    /// Missed runs recorded on this install.
    static var missCount: Int {
        UserDefaults.standard.integer(forKey: Pref.challengeMissCount)
    }

    /// Count one missed run and hand back the new total, so the caller can decide with the
    /// value it just wrote rather than re-reading a preference that may not have settled.
    @discardableResult
    static func recordMiss() -> Int {
        let next = missCount + 1
        UserDefaults.standard.set(next, forKey: Pref.challengeMissCount)
        return next
    }

    static var lastAskedAt: Date? {
        let stamp = UserDefaults.standard.double(forKey: Pref.feedbackAskedAt)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Whether enough time has passed. `nil` (never asked) qualifies.
    static var mayAskAgain: Bool {
        guard let last = lastAskedAt else { return true }
        return Date().timeIntervalSince(last) >= askAgainAfter
    }

    static func markAsked() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Pref.feedbackAskedAt)
    }

    /// Diagnostics only — the window is the one condition no amount of failing can undo,
    /// and nobody can wait out forty days to check a build. Nothing in the app calls this.
    ///
    /// The miss tally is cleared too: resetting the timer alone would re-arm a prompt that
    /// fires on the very next miss, which is not the state a fresh install is in.
    static func resetAsked() {
        UserDefaults.standard.removeObject(forKey: Pref.feedbackAskedAt)
        UserDefaults.standard.removeObject(forKey: Pref.challengeMissCount)
    }

    /// Whether to offer the feedback sheet after this run.
    ///
    /// `passed` is taken rather than assumed so the condition reads the same way the other
    /// two prompts' do, and so the mutual exclusion is visible at the call site instead of
    /// being an invariant someone has to remember.
    static func shouldAsk(passed: Bool, missCount: Int) -> Bool {
        !passed && missCount >= missesRequired && mayAskAgain
    }
}

/// The nudge itself. A sheet rather than an alert, for the reason `ShareSheetPrompt` gives:
/// an alert can't hold a real way out that doesn't read as a punishment.
///
/// The copy names the problem, not the person — "stuck on this one" is about the rung, and
/// the blurb promises a reader rather than a reply, which is the honest version of what
/// `Survey` can deliver.
struct StuckFeedbackPrompt: View {
    /// Called when the user chooses to write, after this sheet has dismissed — presenting
    /// the feedback sheet from a view on its way out drops it silently, the same trap
    /// `ShareSheetPrompt` documents.
    let onWrite: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// Whether the write button was the way out, so the dismissal event can tell the three
    /// exits apart.
    @State private var accepted = false

    var body: some View {
        VStack(spacing: 20) {
            // `bubble.left.and.exclamationmark.bubble.right` would say "complaint"; this is
            // the same question-mark bubble the feedback sheet's own flag family uses, and
            // it reads as an offer to listen rather than an invitation to vent.
            PromptHeader(icon: "questionmark.bubble",
                         title: L.t("Stuck on this one?"),
                         blurb: L.t("We read every one of these."))

            Button {
                accepted = true
                dismiss()
                // A beat, so the feedback sheet rises after this one has gone rather than
                // fighting it for the presentation slot.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onWrite() }
            } label: {
                Label(L.t("Send feedback"), systemImage: "envelope")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)

            Button(L.t("Not now")) { dismiss() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .scrollableWhenCramped()
        .presentationDetents([.height(360), .large])
        // `onDisappear` rather than the buttons, for the reason `ShareSheetPrompt` and
        // `PaywallView` both record: swiping the sheet away is a third exit, and counting
        // only the button would make `accepted` a rate over an undercounted denominator.
        .onDisappear {
            Track.event("stuck_feedback_dismissed", ["accepted": accepted])
        }
    }
}
