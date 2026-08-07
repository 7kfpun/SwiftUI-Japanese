import Foundation
import SwiftData

/// Persisted result of the most recent Kana quiz answer for a given kana.
/// Drives the green/red border coloring of tiles in the Kana browser.
/// Replaces RN's `kana.assessment.{romaji}` (+ `.timestamp`) store.
///
/// No `@Attribute(.unique)` on `romaji`, deliberately: CloudKit-backed SwiftData
/// forbids unique constraints, so one-row-per-kana is enforced by `record`'s
/// fetch-then-update instead. Two devices answering offline can still merge into
/// duplicate rows — readers resolve that by taking the latest `timestamp`, which
/// is also this store's semantic ("the most recent answer wins").
@Model
final class KanaResult {
    var romaji: String = ""
    var isCorrect: Bool = false
    var timestamp: Date = Date.now

    init(romaji: String, isCorrect: Bool, timestamp: Date = .now) {
        self.romaji = romaji
        self.isCorrect = isCorrect
        self.timestamp = timestamp
    }

    /// Upsert the row for a kana — shared by quiz and write modes. If a sync merge
    /// left duplicates, the most recent row is the one that gets updated.
    static func record(romaji: String, isCorrect: Bool, context: ModelContext) {
        let descriptor = FetchDescriptor<KanaResult>(predicate: #Predicate { $0.romaji == romaji })
        let existing = (try? context.fetch(descriptor))?.max { $0.timestamp < $1.timestamp }
        if let existing {
            existing.isCorrect = isCorrect
            existing.timestamp = .now
        } else {
            context.insert(KanaResult(romaji: romaji, isCorrect: isCorrect))
        }
        try? context.save()
    }
}
