import Foundation
import SwiftData
import SwiftUI

/// One calendar day on which the learner answered something — the streak's raw data.
///
/// A row is written by `ChallengeResult.record` and `KanaResult.record`, i.e. by
/// *answering*, never by launching. A streak that counts app opens measures nothing and
/// rewards nothing; this one can only be extended by doing the thing.
///
/// **`day` is `yyyymmdd`, not a `Date`.** A start-of-day `Date` means a different instant
/// in every timezone, so a flight would silently move days that were already recorded and
/// could break a streak retroactively. An integer stamped from the local calendar at the
/// moment of answering is fixed once written: travel can produce two days inside 24 hours,
/// or skip one, but it can never rewrite history.
///
/// CloudKit-backed like the other models, so: no `@Attribute(.unique)`, every property
/// carries a default, and readers must tolerate duplicate rows from a sync merge.
@Model
final class StudyDay {
    var day: Int = 0
    /// How many questions were answered that day. Cosmetic — the streak only cares that
    /// the row exists — which is why duplicate rows resolve by `max` rather than by
    /// summing: two devices syncing the same day must not inflate the count.
    var answers: Int = 0

    init(day: Int, answers: Int = 0) {
        self.day = day
        self.answers = answers
    }

    // MARK: - Day stamps

    /// Gregorian numbering, the user's own day boundaries.
    ///
    /// Deliberately **not** `Calendar.current`. Day boundaries must follow the user's
    /// clock, so the time zone is theirs — but the *numbering* has to be stable, and
    /// `Calendar.current` follows the region setting. Under a Buddhist calendar the year
    /// component of today is 2569, so a stored `20260811` would be read back as year 2026
    /// **BE** and land in 1483 CE; the streak would silently re-interpret every day it
    /// had already written the moment someone changed region. A test caught exactly this
    /// on a simulator whose region is not Gregorian: 2024 stopped being a leap year.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// `yyyymmdd` for a date, on the user's day boundaries.
    static func stamp(_ date: Date = .now, calendar: Calendar = StudyDay.calendar) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// The stamp `days` before `stamp`, walked through `Calendar` rather than by
    /// arithmetic — 20260301 minus one is not 20260228 in a leap year, and month ends
    /// are exactly where a hand-rolled streak quietly breaks.
    static func stamp(_ stamp: Int, offsetBy days: Int, calendar: Calendar = StudyDay.calendar) -> Int {
        var c = DateComponents()
        c.year = stamp / 10_000
        c.month = (stamp / 100) % 100
        c.day = stamp % 100
        guard let date = calendar.date(from: c),
              let moved = calendar.date(byAdding: .day, value: days, to: date)
        else { return stamp }
        return Self.stamp(moved, calendar: calendar)
    }

    // MARK: - Recording

    /// Mark today as studied, and count the answer. Called from the two places that
    /// persist an answer, so no caller has to remember to.
    static func record(context: ModelContext, calendar: Calendar = StudyDay.calendar) {
        let today = stamp(calendar: calendar)
        let descriptor = FetchDescriptor<StudyDay>(predicate: #Predicate { $0.day == today })
        let rows = (try? context.fetch(descriptor)) ?? []
        let firstAnswerToday = rows.isEmpty
        if let row = rows.max(by: { $0.answers < $1.answers }) {
            row.answers += 1
        } else {
            context.insert(StudyDay(day: today, answers: 1))
        }
        try? context.save()

        // The habit loop the whole app is built around, and nothing reported it. Retention
        // in Firebase is measured in *opens*, which this app deliberately doesn't count as
        // studying — so "how many people come back and actually answer something" and the
        // shape of the streak distribution were both invisible.
        //
        // Only on the day's first answer, so it is one row per studied day rather than one
        // per question, and only then is the extra fetch paid. `streak` is a behavioural
        // count, not an identifier: it says how long this run is, and nothing about who.
        if firstAnswerToday {
            let streak = Self.streak(context: context, calendar: calendar)
            Track.event("study_day", ["streak": streak.current, "best": streak.best])
        }

        // Today is now studied, so any reminder still pending for tonight has become a
        // nag. Re-planning here rather than only on launch is what makes the reminder
        // trustworthy: it can't fire at someone who already did the thing.
        Task { await StreakReminder.reschedule(studiedToday: true) }
    }

    // MARK: - Streak

    /// Current and longest run of consecutive studied days.
    static func streak(context: ModelContext, calendar: Calendar = StudyDay.calendar) -> Streak {
        let rows = (try? context.fetch(FetchDescriptor<StudyDay>())) ?? []
        return Streak(days: Set(rows.map(\.day)), calendar: calendar)
    }
}

/// The streak, computed from the set of studied days.
///
/// A `struct` over a `Set` rather than a stored counter: a counter has to be maintained
/// correctly at every write, across two devices merging out of order, and gets it wrong
/// exactly once before nobody trusts it again. Recomputing is O(days) over a set that
/// grows by at most one row a day.
struct Streak: Equatable {
    /// Consecutive days ending today — or ending yesterday, in which case today is still
    /// open. The streak is not broken until a day is *missed*, so someone opening the app
    /// at 9am sees the streak they went to bed with, not zero.
    let current: Int
    /// Longest run ever, including the current one.
    let best: Int
    /// Whether today already counts. Drives "keep it going" versus "done" — never the
    /// number itself.
    let studiedToday: Bool
    /// Every day recorded, kept so callers can draw a calendar without a second fetch.
    let days: Set<Int>
    /// The day this streak was computed against, so the week strip and the streak can
    /// never disagree about which day "today" is.
    let today: Int

    /// A live streak with today still open — the only state where the number on screen
    /// can go *down* by doing nothing. Everything that applies pressure keys off this,
    /// and nothing else does, so the app is never urgent at someone who is already done.
    var atRisk: Bool { current > 0 && !studiedToday }

    /// How many more days would beat the record. `nil` once the current run *is* the
    /// record — there is nothing left to chase, and inventing a target would be the kind
    /// of fabricated progress this app doesn't do.
    var toBeatBest: Int? { current < best ? best - current + 1 : nil }

    /// Time left to keep the streak, or `nil` when nothing is at stake.
    ///
    /// The deadline is real: `StudyDay.record` stamps the day from the same calendar this
    /// counts down to, so when this hits zero the streak genuinely ends. That is the only
    /// reason a countdown belongs here at all — a clock ticking toward a deadline the app
    /// invented would be theatre, and this one isn't.
    func timeLeft(now: Date = .now, calendar: Calendar = StudyDay.calendar) -> TimeInterval? {
        guard atRisk else { return nil }
        guard let midnight = calendar.date(byAdding: .day, value: 1,
                                           to: calendar.startOfDay(for: now)) else { return nil }
        return max(0, midnight.timeIntervalSince(now))
    }

    /// The last seven days, oldest first, each with whether it was studied. Drawn as a
    /// strip: a gap is visible information, which motivates far better than a sentence
    /// telling someone they missed a day.
    func lastWeek(calendar: Calendar = StudyDay.calendar) -> [(day: Int, studied: Bool)] {
        (0..<7).reversed().map { offset in
            let stamp = StudyDay.stamp(today, offsetBy: -offset, calendar: calendar)
            return (stamp, days.contains(stamp))
        }
    }

    init(days: Set<Int>, today: Int = StudyDay.stamp(), calendar: Calendar = StudyDay.calendar) {
        self.days = days
        self.today = today
        studiedToday = days.contains(today)

        // Walk back from today (or yesterday, if today is still open) until a gap.
        var run = 0
        var cursor = studiedToday ? today : StudyDay.stamp(today, offsetBy: -1, calendar: calendar)
        while days.contains(cursor) {
            run += 1
            cursor = StudyDay.stamp(cursor, offsetBy: -1, calendar: calendar)
        }
        current = run

        // Longest run anywhere: a day starts a run only if the day before it is absent,
        // so each run is measured once no matter how the set is ordered.
        var longest = 0
        for day in days where !days.contains(StudyDay.stamp(day, offsetBy: -1, calendar: calendar)) {
            var length = 0
            var next = day
            while days.contains(next) {
                length += 1
                next = StudyDay.stamp(next, offsetBy: 1, calendar: calendar)
            }
            longest = max(longest, length)
        }
        best = max(longest, current)
    }
}

/// The streak, as a flame and a number.
///
/// Silent at zero. A "0 day streak" badge is a reproach to someone who hasn't started
/// yet, and the first day of anything is the one most worth not discouraging.
///
/// The flame is filled only once today is done, so the badge distinguishes "you're on a
/// run" from "you're on a run and it's still open" without a second line of text — which
/// matters more than it sounds across 18 languages, several of which run long.
/// Amber. Deliberately not green or red — those are answer feedback and nothing else —
/// and deliberately not `Theme.accent`, so a streak at risk reads as a different kind of
/// message from every other accented control on the screen. It is also simply the colour
/// a flame is.
extension Color {
    static let streak = Color(red: 0.98, green: 0.58, blue: 0.13)
}

struct StreakBadge: View {
    let streak: Streak
    /// Tapping it opens Progress. The tab bar is the discoverable route; this is the one
    /// people will actually use, because the number is what made them curious.
    var action: () -> Void = {}

    var body: some View {
        if streak.current > 0 {
            Button(action: action) {
                HStack(spacing: 4) {
                    // Hollow while today is open, filled once it's done. The badge is on
                    // screen all day, so the outline is a standing reminder that the
                    // number is not yet safe — without a word of nagging copy.
                    Image(systemName: streak.studiedToday ? "flame.fill" : "flame")
                        .symbolEffect(.pulse, options: .repeating, isActive: streak.atRisk)
                    Text("\(streak.current)").monospacedDigit()
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.streak)
                // No self-drawn capsule: iOS 26 wraps toolbar items in their own
                // circular chrome, and the badge's tinted pill inside the system's
                // white circle read as a button in a button. The states survive
                // without it — hollow/filled flame for open/done, the pulse for
                // at-risk.
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L.t("%@-day streak", "\(streak.current)"))
            .accessibilityHint(streak.atRisk ? L.t("Study today to keep your streak.") : "")
        }
    }
}

/// The streak, full size: the number, the week behind it, and what is at stake.
///
/// Every pressure here is a true statement about the user's own data — the run they
/// built, the days they missed, the record they set. Nothing counts down to a deadline
/// the app invented, and nothing appears once today is done: someone who has already
/// studied should be told they're safe, not chased.
struct StreakHero: View {
    let streak: Streak

    private var weekdaySymbols: [String] {
        var calendar = StudyDay.calendar
        calendar.locale = Locale(identifier: L.current)
        return calendar.veryShortStandaloneWeekdaySymbols
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: streak.studiedToday ? "flame.fill" : "flame")
                    .font(.system(size: 40))
                    .symbolEffect(.pulse, options: .repeating, isActive: streak.atRisk)
                Text("\(streak.current)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    // One of the few deliberate fixed sizes in the app: this is the
                    // display slot Theme documents, and the number is the screen.
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Color.streak)

            week

            if let message {
                Text(message)
                    .font(Theme.title(.footnote, weight: .regular))
                    .foregroundStyle(streak.atRisk ? Color.streak : .secondary)
                    .multilineTextAlignment(.center)
            }

            countdown
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.t("%@-day streak", "\(streak.current)"))
    }

    /// Time remaining until the streak actually ends.
    ///
    /// `TimelineView(.periodic(by: 60))` rather than a `Timer`: SwiftUI drives the
    /// redraw, stops it when the view is off screen, and there is no object to invalidate.
    /// A minute is the right cadence — a seconds-level clock on a deadline hours away
    /// reads as a bomb timer, and the app is trying to be a reason to come back, not a
    /// source of anxiety.
    ///
    /// Absent entirely unless the streak is at risk. Someone who has already studied is
    /// not counted down at.
    @ViewBuilder
    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let remaining = streak.timeLeft(now: context.date),
               let text = Self.remainingFormatter.string(from: remaining) {
                Label(L.t("%@ left today", text), systemImage: "clock")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.streak)
            }
        }
    }

    /// "5h 12m", localized by the system in the *app's* language rather than the device's
    /// — the two differ whenever someone has changed the in-app language, and a Japanese
    /// UI showing "5h 12m" in Vietnamese units would be the tell.
    private static let remainingFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropLeading
        f.calendar = {
            var calendar = StudyDay.calendar
            calendar.locale = Locale(identifier: L.current)
            return calendar
        }()
        return f
    }()

    /// Seven dots. The gaps are the point — a missed day is a hole you can see, which
    /// argues for not making another one far better than any sentence could.
    private var week: some View {
        HStack(spacing: 10) {
            ForEach(streak.lastWeek(), id: \.day) { entry in
                VStack(spacing: 5) {
                    Circle()
                        .fill(entry.studied ? Color.streak : Color.secondary.opacity(0.15))
                        .frame(width: 12, height: 12)
                        .overlay(
                            // Today gets a ring whether or not it's filled, so the eye
                            // lands on the one day still in the user's hands.
                            Circle().strokeBorder(Color.streak,
                                                  lineWidth: entry.day == streak.today ? 2 : 0)
                                .frame(width: 19, height: 19)
                        )
                        .frame(width: 19, height: 19)
                    Text(weekdayLetter(entry.day))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityHidden(true)   // the streak's own label already says the number
    }

    private func weekdayLetter(_ stamp: Int) -> String {
        var c = DateComponents()
        c.year = stamp / 10_000; c.month = (stamp / 100) % 100; c.day = stamp % 100
        let calendar = StudyDay.calendar
        guard let date = calendar.date(from: c) else { return "" }
        let index = calendar.component(.weekday, from: date) - 1
        return weekdaySymbols.indices.contains(index) ? weekdaySymbols[index] : ""
    }

    /// At most one line, and only when there is something true to say.
    private var message: String? {
        if streak.atRisk { return L.t("Study today to keep your streak.") }
        if let n = streak.toBeatBest { return L.t("%@ more days to beat your best", "\(n)") }
        return nil
    }
}
