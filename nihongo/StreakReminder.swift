import Foundation
import UserNotifications

/// The daily "your streak is still open" reminder, scheduled **entirely on device**.
///
/// Deliberately not a push. The only thing worth saying — *you haven't studied today, and
/// the day ends at midnight* — is derived from `StudyDay` rows that never leave the
/// device, at a local wall-clock time only the device knows. A server would need the
/// streak, the time zone and an identifier to join them, which is three things this app
/// goes out of its way not to have. It also works offline, which the rest of the app
/// promises.
///
/// Push (`PushService`) is for the other kind of message: announcements and campaigns
/// that originate with us rather than with the learner's own clock.
enum StreakReminder {
    /// Prefix for every pending request, so `cancel` can clear ours without touching a
    /// notification some other feature scheduled.
    static let prefix = "streak.reminder."

    /// How many days ahead to schedule.
    ///
    /// iOS keeps at most 64 pending local notifications per app and silently drops the
    /// rest, so this is nowhere near the ceiling. Seven means someone who stops opening
    /// the app still gets a week of reminders — long enough to come back, short enough
    /// that a dead install stops talking. Every open and every answer re-plans, so the
    /// window keeps sliding forward for anyone still here.
    static let horizon = 7

    /// Default fire time, local. Evening: late enough that a normal day's study has
    /// already happened (so the reminder is usually cancelled before it fires), early
    /// enough to leave time to act on it before the day ends.
    static let defaultHour = 20

    // MARK: - Planning (pure — this is the part worth testing)

    /// Which day stamps should carry a reminder.
    ///
    /// Today is included **only** if it is still winnable: not already studied, and the
    /// fire time not yet past. Both matter. Scheduling a time that has gone by means iOS
    /// drops the request silently, and re-planning after the user studies is what stops
    /// the app nagging someone who is already done — the single most annoying thing a
    /// streak reminder can do, and the reason people turn them off for good.
    static func plan(now: Date = .now,
                     studiedToday: Bool,
                     hour: Int = defaultHour,
                     horizon: Int = horizon,
                     calendar: Calendar = StudyDay.calendar) -> [Int] {
        let today = StudyDay.stamp(now, calendar: calendar)
        var days: [Int] = []

        let hourNow = calendar.component(.hour, from: now)
        if !studiedToday && hourNow < hour { days.append(today) }

        for offset in 1...max(1, horizon) {
            days.append(StudyDay.stamp(today, offsetBy: offset, calendar: calendar))
        }
        return days
    }

    /// `yyyymmdd` + an hour, as the components a calendar trigger wants.
    ///
    /// Components rather than a resolved `Date` on purpose: iOS matches them against the
    /// calendar *at fire time*, so a learner who flies to another time zone still gets
    /// reminded at 8pm where they are, not 8pm where they were.
    static func components(day: Int, hour: Int) -> DateComponents {
        var c = DateComponents()
        c.year = day / 10_000
        c.month = (day / 100) % 100
        c.day = day % 100
        c.hour = hour
        c.minute = 0
        return c
    }

    // MARK: - Permission

    /// Whether the learner has already been asked, whatever they answered.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Ask for permission. Called from the Settings toggle and **nowhere else** — never
    /// at launch. A prompt on first run, before the app has shown it is worth hearing
    /// from, is the reliable way to collect a permanent "Don't Allow": iOS only ever asks
    /// once, and after that the only route back is the Settings app.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        Track.event("notification_permission", ["granted": granted])
        return granted
    }

    // MARK: - Scheduling

    /// Replace every pending streak reminder with a freshly planned set.
    ///
    /// Idempotent, and cheap enough to call on every app open and every recorded answer —
    /// which is exactly what keeps it honest, because the plan depends on whether today
    /// has been studied and that changes underneath it.
    static func reschedule(studiedToday: Bool,
                           now: Date = .now,
                           calendar: Calendar = StudyDay.calendar) async {
        let center = UNUserNotificationCenter.current()
        cancel(center: center)

        guard UserDefaults.standard.bool(forKey: Pref.streakReminderOn) else { return }
        guard await authorizationStatus() == .authorized else { return }

        let hour = resolvedHour
        for day in plan(now: now, studiedToday: studiedToday, hour: hour, calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = L.t("Keep your streak alive")
            content.body = L.t("You haven't studied yet today.")
            content.sound = .default

            // Deliberately no streak *number* in the copy. Requests are scheduled days
            // ahead, so any number baked in now is a guess about a day that hasn't
            // happened — and "your 12-day streak ends tonight" shown to someone whose
            // streak broke on day 9 is a lie the app never gets to take back.
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components(day: day, hour: hour), repeats: false)
            let request = UNNotificationRequest(identifier: "\(prefix)\(day)",
                                                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Drop every pending streak reminder, leaving anything else alone.
    static func cancel(center: UNUserNotificationCenter = .current()) {
        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }

    /// The configured hour, clamped to a real one. A stored 0 is indistinguishable from
    /// "never set" in `UserDefaults`, so an unset key reads as the default rather than
    /// as midnight.
    static var resolvedHour: Int {
        let stored = UserDefaults.standard.integer(forKey: Pref.streakReminderHour)
        return (1...23).contains(stored) ? stored : defaultHour
    }
}
