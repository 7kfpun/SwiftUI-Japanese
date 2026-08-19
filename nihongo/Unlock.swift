import SwiftUI
import SwiftData

/// Whether the course's first band has been *earned* rather than bought.
///
/// Three stars on every challenge of lessons 1…`Gating.freeLessonLimit` opens all of
/// Minna's "Beginning 1" or JLPT's "N5" — see `Gating.hasEarnedFirstGroup`.
///
/// An observable rather than a computed call at each gate, because `Gating.isLocked` is
/// a pure static consulted from six places and none of them should have to fetch. It sits
/// beside `Store` in the environment for the same reason: entitlement and achievement are
/// two independent ways past the paywall, and every gate needs both.
///
/// Recomputed rather than stored. A persisted "earned" flag would be a second source of
/// truth for something the `ChallengeResult` rows already answer, and — worse — it would
/// survive a CloudKit merge that removed the rows behind it. Recomputing costs one fetch
/// at the moments it can actually change.
@Observable
@MainActor
final class Unlock {
    private(set) var earnedFirstGroup = false
    /// Three-starred rungs across the free lessons, and how many there are — drives the
    /// "you're N of M away" line that makes the offer visible before it's won.
    private(set) var swept = 0
    private(set) var totalRungs = 0

    /// True the moment it flips from unearned to earned, so the UI can celebrate once.
    /// Cleared by `acknowledge()`.
    private(set) var justEarned = false

    func refresh(context: ModelContext) {
        let progress = ChallengeResult.firstGroupProgress(context: context)
        swept = progress.swept
        totalRungs = progress.total

        let earned = ChallengeResult.hasEarnedFirstGroup(context: context)
        if earned && !earnedFirstGroup { justEarned = true }
        earnedFirstGroup = earned

        // The analytics profile is refreshed from here because this is the one place that
        // runs often *and* holds the only value not in `UserDefaults` — everything else is
        // read straight off the defaults below. `Track.setProfile` skips unchanged values,
        // so calling it on every Today appear costs nothing.
        let defaults = UserDefaults.standard
        Track.setProfile(uiLanguage: L.current,
                         meaningLanguage: defaults.string(forKey: Pref.translationLanguage)
                             ?? VocabStore.deviceDefaultLanguage,
                         knowsKana: defaults.string(forKey: Pref.knowsKana),
                         goal: defaults.string(forKey: Pref.goal),
                         earnedFirstGroup: earned)
    }

    func acknowledge() { justEarned = false }

    /// The band this unlocks, for copy that should name it — "Beginning 1", "N5".
    var bandName: String { Gating.earnableGroup.map { L.t($0.name) } ?? "" }

    /// Highest lesson the band reaches, for "lessons 1–13" style copy.
    var bandLast: Int { Gating.earnableGroup?.last ?? Gating.freeLessonLimit }
}

/// Shown once, the moment the first band is earned.
///
/// Deliberately has nothing to sell and nothing to ask. The rating and share prompts are
/// suppressed on this run precisely so this moment isn't spent on us — someone who just
/// three-starred five lessons has earned a screen that only congratulates them.
struct EarnedUnlockCard: View {
    let band: String
    let through: Int
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.streak)
                .accessibilityHidden(true)

            Text(L.t("%@ unlocked!", band))
                .font(Theme.title(.title2, weight: .bold))
                .multilineTextAlignment(.center)

            Text(L.t("Three stars on every challenge so far — lessons up to %@ are yours, free.",
                     "\(through)"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onDone) {
                Text(L.t("Keep going"))
                    .font(Theme.title(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}
