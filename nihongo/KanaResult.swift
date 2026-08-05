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
}
