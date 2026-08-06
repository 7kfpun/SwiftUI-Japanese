// NOTE: intentionally duplicated in nihongo/Today/ and TodayWidget/ (synchronized
// groups scope files per target) — KEEP BOTH COPIES IDENTICAL.
import Foundation

/// A small snapshot of the current "Today" lesson, shared with the home-screen widget
/// through an App Group. Kept to plain strings so the widget target needs no app code
/// beyond this one file (add it to both the app and widget targets).
enum TodayShared {
    /// Create this App Group in Signing & Capabilities on BOTH the app and widget targets.
    static let appGroup = "group.com.kfpun.nihongo"
    private static let key = "today.snapshot"

    struct Word: Codable, Hashable {
        let kana: String, kanji: String, romaji: String, meaning: String
    }
    struct Snapshot: Codable { let lesson: Int; let words: [Word] }

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
