import Foundation
import SwiftData

/// Persisted best result for one challenge, keyed `"<lesson>/<index>"`.
///
/// Only bests are kept, never a full attempt history: the ladder asks "how far have I
/// got, how well", and storing every run would grow without bound for no extra answer.
/// A retry can raise the score and stars but never lower them, so replaying a passed
/// challenge is always safe.
@Model
final class ChallengeResult {
    @Attribute(.unique) var id: String
    var lesson: Int
    var index: Int
    var bestScore: Int          // percent
    var stars: Int
    var attempts: Int
    var completedAt: Date?      // first time it was passed; nil while still unpassed

    init(lesson: Int, index: Int, bestScore: Int = 0, stars: Int = 0,
         attempts: Int = 0, completedAt: Date? = nil) {
        self.id = Self.key(lesson: lesson, index: index)
        self.lesson = lesson
        self.index = index
        self.bestScore = bestScore
        self.stars = stars
        self.attempts = attempts
        self.completedAt = completedAt
    }

    static func key(lesson: Int, index: Int) -> String { "\(lesson)/\(index)" }

    var isPassed: Bool { completedAt != nil }

    /// Record an attempt, keeping the better score. Returns the stored row.
    @discardableResult
    static func record(lesson: Int, index: Int, score: Int, context: ModelContext) -> ChallengeResult {
        let key = Self.key(lesson: lesson, index: index)
        let descriptor = FetchDescriptor<ChallengeResult>(predicate: #Predicate { $0.id == key })
        let row = (try? context.fetch(descriptor).first)
            ?? {
                let fresh = ChallengeResult(lesson: lesson, index: index)
                context.insert(fresh)
                return fresh
            }()

        row.attempts += 1
        if score > row.bestScore {
            row.bestScore = score
            row.stars = Challenge.stars(score: score)
        }
        // Stamped once, on the first pass — this is the "when did I unlock the next
        // one" marker, so a later replay shouldn't move it.
        if row.completedAt == nil && score >= Challenge.passScore { row.completedAt = .now }

        try? context.save()
        return row
    }

    /// Every stored result for a lesson, keyed by challenge index — one fetch for a
    /// whole ladder instead of one per rung.
    static func byIndex(lesson: Int, context: ModelContext) -> [Int: ChallengeResult] {
        let descriptor = FetchDescriptor<ChallengeResult>(predicate: #Predicate { $0.lesson == lesson })
        let rows = (try? context.fetch(descriptor)) ?? []
        return Dictionary(rows.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Challenge `index` is unlocked when the one before it has been passed. Challenge
    /// 1 is always open, so a lesson can always be started.
    static func isUnlocked(index: Int, results: [Int: ChallengeResult]) -> Bool {
        index <= 1 || results[index - 1]?.isPassed == true
    }

    /// Challenges passed in a lesson — the numerator of the lesson progress ring.
    static func passedCount(results: [Int: ChallengeResult]) -> Int {
        results.values.filter(\.isPassed).count
    }
}
