import SwiftUI
import UserNotifications

/// When to *ask about* notifications, as opposed to how to schedule them
/// (`StreakReminder`) or how to receive them (`PushService`).
///
/// The whole design turns on one fact: **iOS raises the system permission alert once per
/// install, ever.** A "Don't Allow" is permanent, undoable only by a trip to the Settings
/// app that nobody makes. So the system alert is treated as a scarce resource and is never
/// spent on a guess — a soft ask, in the app's own UI, comes first, and the real alert
/// only follows a yes. A no costs nothing and can be asked again another day.
///
/// Two places ask: the last intro card, and the streak crossing
/// `streakThreshold`. They share this policy so they can't both fire in the same week.
enum NotificationOptIn {
    /// Streak length that earns a second ask.
    ///
    /// Seven days is the point the habit is demonstrably real and the thing being
    /// protected is worth protecting — asking earlier is asking someone to defend
    /// something they don't have yet, which is what makes a permission prompt feel like
    /// an interruption rather than an offer.
    static let streakThreshold = 7

    /// How long a "not now" is respected. Long, deliberately: this is a prompt about
    /// prompts, and the second most annoying thing after a badly-timed permission alert
    /// is being asked repeatedly whether you'd like one.
    static let askAgainAfter: TimeInterval = 60 * 24 * 60 * 60   // 60 days

    static var lastAskedAt: Date? {
        let t = UserDefaults.standard.double(forKey: Pref.notificationAskedAt)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func recordAsked(_ now: Date = .now) {
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Pref.notificationAskedAt)
    }

    /// Whether a soft ask may be shown at all.
    ///
    /// Pure, and takes everything it needs, so the four reasons to stay quiet are one
    /// readable list rather than conditions scattered across two views.
    static func mayAsk(isOn: Bool,
                       status: UNAuthorizationStatus,
                       lastAsked: Date? = lastAskedAt,
                       now: Date = .now) -> Bool {
        // Already getting reminders — there is nothing to offer.
        guard !isOn else { return false }
        // `.denied` means iOS will never show the alert again, so a soft ask could only
        // lead somewhere it can't go. `.authorized` without our toggle on is a real
        // state (permission granted, reminder later switched off) and *is* worth asking.
        guard status != .denied else { return false }
        guard let lastAsked else { return true }
        return now.timeIntervalSince(lastAsked) >= askAgainAfter
    }

    /// The streak milestone trigger: a live streak that has reached the threshold.
    ///
    /// `current`, not `best` — the offer is to protect the run you are *on*. Someone whose
    /// record is 30 days but who is on day 1 has nothing at stake tonight, and telling
    /// them otherwise is the sort of urgency that reads as manipulation.
    static func shouldAskAfterStreak(_ streak: Streak,
                                     isOn: Bool,
                                     status: UNAuthorizationStatus,
                                     lastAsked: Date? = lastAskedAt,
                                     now: Date = .now) -> Bool {
        guard streak.current >= streakThreshold else { return false }
        return mayAsk(isOn: isOn, status: status, lastAsked: lastAsked, now: now)
    }
}

/// The soft ask, shared by the intro card and the streak milestone.
///
/// Explains the offer in the app's own voice and returns a plain yes/no. **Only a yes ever
/// reaches `UNUserNotificationCenter`** — the point of the whole pattern.
struct NotificationOptInCard: View {
    /// Called with the learner's answer. `true` means "go ahead and ask iOS".
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack(spacing: 18) {
            PromptHeader(icon: "bell.badge",
                         title: L.t("Never lose a streak"),
                         iconFont: .system(size: 44),
                         tint: Color.streak,
                         titleFont: Theme.title(.title2, weight: .bold))

            // Concrete about what arrives and what doesn't. "Enable notifications to stay
            // motivated" is the phrasing people have learned to refuse; the promise that
            // it stays silent once you're done is the part that earns a yes.
            VStack(alignment: .leading, spacing: 12) {
                reason("clock.badge.checkmark", "One reminder, only on days you haven't studied yet.")
                reason("moon.zzz", "Nothing at all once you're done for the day.")
                reason("slider.horizontal.3", "Pick the time, or turn it off, in Settings.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                Button {
                    onAnswer(true)
                } label: {
                    Text(L.t("Remind me"))
                        .font(Theme.title(.headline))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                // A real, unpenalised way out. Styled as a plain button rather than
                // greyed-out small print, because a decline that feels discouraged is how
                // an app collects a permanent system-level "no" one screen later.
                Button(L.t("Not now")) { onAnswer(false) }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .padding()
    }

    private func reason(_ symbol: String, _ key: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(L.t(key)).font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}
