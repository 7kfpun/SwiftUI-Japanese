// NOTE: intentionally duplicated in nihongo/Today/, TodayWidget/, WatchApp/ and
// WatchWidget/ (synchronized groups scope files per target) — KEEP ALL COPIES IDENTICAL.
import Foundation

/// A small snapshot of the current "Today" lesson, shared with the home-screen widget
/// through an App Group. Kept to plain strings so the widget target needs no app code
/// beyond this one file (add it to every target that shows Today's words).
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
}
