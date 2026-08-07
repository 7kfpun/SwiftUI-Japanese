import Foundation
import SwiftData

/// Persisted result of the most recent Kana quiz answer for a given kana.
/// Drives the green/red border coloring of tiles in the Kana browser.
/// Replaces RN's `kana.assessment.{romaji}` (+ `.timestamp`) store.
@Model
final class KanaResult {
    @Attribute(.unique) var romaji: String
    var isCorrect: Bool
    var timestamp: Date

    init(romaji: String, isCorrect: Bool, timestamp: Date = .now) {
        self.romaji = romaji
        self.isCorrect = isCorrect
        self.timestamp = timestamp
    }

    /// Upsert the single row for a kana (unique romaji) — shared by quiz and write modes.
    static func record(romaji: String, isCorrect: Bool, context: ModelContext) {
        let descriptor = FetchDescriptor<KanaResult>(predicate: #Predicate { $0.romaji == romaji })
        if let existing = try? context.fetch(descriptor).first {
            existing.isCorrect = isCorrect
            existing.timestamp = .now
        } else {
            context.insert(KanaResult(romaji: romaji, isCorrect: isCorrect))
        }
        try? context.save()
    }
}
