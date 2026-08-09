// `Shared/` is a synchronized group listed by every target that shows Today's words —
// app, TodayWidget, WatchApp, WatchWidget. One file, four memberships.
//
// This was four hand-copied files carrying a "KEEP ALL COPIES IDENTICAL" warning, which
// is a rule nothing enforced. Put anything genuinely shared here; anything
// target-specific stays in its own folder.
import Foundation

/// A small snapshot of the current "Today" lesson, shared with the home-screen widget
/// through an App Group. Kept to plain strings so the widget targets need no app code
/// beyond this one file.
///
/// App Group containers are per-platform: watchOS gets its *own* container under the
/// same identifier, so nothing the phone writes here is visible on the wrist. The watch
/// app fills its container from the WatchConnectivity payload (see WatchLink.swift) and
/// the watch complications then read it back through this same API.
enum TodayShared {
    /// Create this App Group in Signing & Capabilities on BOTH the app and widget targets.
    static let appGroup = "group.com.kfpun.nihongo"
    private static let key = "today.snapshot"

    struct Word: Codable, Hashable {
        let kana: String, kanji: String, romaji: String, meaning: String
    }
    /// `challenge` is the rung these words prepare for; a cleared ladder sends its
    /// last rung as a retake, so it's always populated by the current app. Optional
    /// only so a snapshot written before this field existed still decodes.
    struct Snapshot: Codable { let lesson: Int; let words: [Word]; var challenge: Int? = nil }

    private static var store: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Written by the app whenever the Today lesson/language changes.
    static func write(_ snapshot: Snapshot) {
        guard let store, let data = try? JSONEncoder().encode(snapshot) else { return }
        store.set(data, forKey: key)
    }

    /// Read by the widget's timeline provider.
    static func read() -> Snapshot? {
        guard let store, let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    // MARK: - Hourly rotation

    /// Which word of a `count`-word deck to show at `date`, given the widget's manual
    /// paging `cursor` (0 on the watch, which has no buttons).
    ///
    /// A pure function of the wall clock, and that is the whole point. The timeline is
    /// rebuilt every time the app publishes a snapshot — `TodayView.loadPicks()` calls
    /// `reloadAllTimelines()`, and that runs on *every* visit to the Today tab — so an
    /// index counted forward from the moment of the rebuild restarts at the same word each
    /// time. Anyone who opened the app more than once an hour never saw the widget rotate
    /// at all. Deriving the index from the hour makes a rebuild idempotent: mid-hour it
    /// recomputes the word already on screen, and the rotation survives.
    static func rotationIndex(count: Int, cursor: Int = 0, at date: Date = Date()) -> Int {
        guard count > 0 else { return 0 }
        return floorMod(cursor &+ hourSlot(date), count)
    }

    /// Whole hours since the epoch — the rotation's clock. Deliberately not a calendar
    /// component: this only has to advance by exactly one every hour and be identical in
    /// the app, the widget and the watch, which a UTC-anchored count is and a local-time
    /// one isn't across a DST boundary.
    static func hourSlot(_ date: Date = Date()) -> Int {
        Int((date.timeIntervalSince1970 / 3600).rounded(.down))
    }

    /// The top of the next clock hour after `date`, where the following timeline entry
    /// belongs. Scheduling on hour boundaries rather than `now + 1h` keeps the rotation on
    /// the clock instead of drifting to whenever the timeline was last rebuilt.
    static func nextHour(after date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: Double(hourSlot(date) + 1) * 3600)
    }

    /// Floor modulo. Swift's `%` keeps the sign of the dividend and the paging cursor is a
    /// free-running value that goes negative once someone pages back — `-1 % 7` is `-1`,
    /// which fed into an array subscript would trap.
    static func floorMod(_ value: Int, _ count: Int) -> Int {
        guard count > 0 else { return 0 }
        let r = value % count
        return r < 0 ? r + count : r
    }
}
