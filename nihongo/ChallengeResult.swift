import Foundation
import SwiftData

/// Persisted best result for one challenge, keyed `"<lesson>/<index>"`.
///
/// Only bests are kept, never a full attempt history: the ladder asks "how far have I
/// got, how well", and storing every run would grow without bound for no extra answer.
/// A retry can raise the score and stars but never lower them, so replaying a passed
/// challenge is always safe.
///
/// No `@Attribute(.unique)` on `id`, deliberately: CloudKit-backed SwiftData forbids
/// unique constraints, so one-row-per-challenge is enforced by `record`'s
/// fetch-then-update instead. Two devices playing offline can still merge into
/// duplicate rows for the same challenge — every reader resolves that through
/// `better(_:_:)`, which keeps the strongest result, so a sync race can inflate
/// nothing and lose nothing.
@Model
final class ChallengeResult {
    var id: String = ""
    var lesson: Int = 0
    var index: Int = 0
    var bestScore: Int = 0      // percent
    var stars: Int = 0
    var attempts: Int = 0
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

    /// Which of two rows for the *same* challenge to believe after a sync merge:
    /// the higher best score, then the earlier first-pass date (it's a "first
    /// passed" stamp, so earlier is more truthful), then the higher attempt count.
    static func better(_ a: ChallengeResult, _ b: ChallengeResult) -> ChallengeResult {
        if a.bestScore != b.bestScore { return a.bestScore > b.bestScore ? a : b }
        switch (a.completedAt, b.completedAt) {
        case let (x?, y?): return x <= y ? a : b
        case (_?, nil):    return a
        case (nil, _?):    return b
        default:           return a.attempts >= b.attempts ? a : b
        }
    }

    /// Record an attempt, keeping the better score. Returns the stored row.
    @discardableResult
    static func record(lesson: Int, index: Int, score: Int, context: ModelContext) -> ChallengeResult {
        let key = Self.key(lesson: lesson, index: index)
        let descriptor = FetchDescriptor<ChallengeResult>(predicate: #Predicate { $0.id == key })
        let matches = (try? context.fetch(descriptor)) ?? []
        let row = matches.dropFirst().reduce(matches.first) { best, next in
            best.map { Self.better($0, next) } ?? next
        } ?? {
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

        // Any attempt counts toward the streak, passed or not — the streak measures
        // showing up, and only rewarding passes would punish the harder rungs.
        StudyDay.record(context: context)
        try? context.save()
        return row
    }

    /// Every stored result for a lesson, keyed by challenge index — one fetch for a
    /// whole ladder instead of one per rung. Duplicate rows (sync merge) collapse to
    /// the strongest.
    static func byIndex(lesson: Int, context: ModelContext) -> [Int: ChallengeResult] {
        let descriptor = FetchDescriptor<ChallengeResult>(predicate: #Predicate { $0.lesson == lesson })
        let rows = (try? context.fetch(descriptor)) ?? []
        return Dictionary(rows.map { ($0.index, $0) }, uniquingKeysWith: better)
    }

    /// Challenge `index` is unlocked when the one before it has been passed. Challenge
    /// 1 is always open, so a lesson can always be started.
    static func isUnlocked(index: Int, results: [Int: ChallengeResult]) -> Bool {
        index <= 1 || results[index - 1]?.isPassed == true
    }

    /// Challenges passed in a lesson — the numerator of the lesson progress bar.
    static func passedCount(results: [Int: ChallengeResult]) -> Int {
        results.values.filter(\.isPassed).count
    }

    /// Rungs passed across every lesson — how far into the app someone actually is,
    /// used to decide whether they've done enough to be worth asking for a rating.
    ///
    /// Deduped by `id` first: a sync merge can leave two rows for one rung, which would
    /// otherwise inflate the count and let the prompt fire early.
    static func totalPassed(context: ModelContext) -> Int {
        let rows = (try? context.fetch(FetchDescriptor<ChallengeResult>())) ?? []
        return Set(rows.filter(\.isPassed).map(\.id)).count
    }

    /// Three stars on every rung of lessons 1…`Gating.freeLessonLimit`, which earns the
    /// course's first band free — see `Gating.hasEarnedFirstGroup`.
    ///
    /// One fetch for all of it, deduped by `id` first: a sync merge can leave two rows
    /// for one rung, and counting both would let four three-starred rungs pass for five.
    static func hasEarnedFirstGroup(context: ModelContext) -> Bool {
        let limit = Gating.freeLessonLimit
        guard limit >= 1 else { return false }

        let rows = (try? context.fetch(FetchDescriptor<ChallengeResult>())) ?? []
        var best: [String: ChallengeResult] = [:]
        for row in rows where row.lesson <= limit {
            best[row.id] = best[row.id].map { better($0, row) } ?? row
        }

        var rungs: [Int: Int] = [:]
        var swept: [Int: Int] = [:]
        for lesson in 1...limit {
            rungs[lesson] = Challenge.count(wordCount: VocabStore.lesson(lesson).entries.count)
            swept[lesson] = best.values.filter { $0.lesson == lesson && $0.stars >= 3 }.count
        }
        return Gating.hasEarnedFirstGroup(rungs: rungs, threeStarred: swept)
    }

    /// How much of the earned unlock is done — for the progress line that tells people
    /// the offer exists. Returns (three-starred rungs, total rungs) over the free lessons.
    static func firstGroupProgress(context: ModelContext) -> (swept: Int, total: Int) {
        let limit = Gating.freeLessonLimit
        guard limit >= 1 else { return (0, 0) }
        let rows = (try? context.fetch(FetchDescriptor<ChallengeResult>())) ?? []
        var best: [String: ChallengeResult] = [:]
        for row in rows where row.lesson <= limit {
            best[row.id] = best[row.id].map { better($0, row) } ?? row
        }
        let total = (1...limit).reduce(0) { $0 + Challenge.count(wordCount: VocabStore.lesson($1).entries.count) }
        return (best.values.filter { $0.stars >= 3 }.count, total)
    }

    /// The lowest rung not yet passed, or nil once the whole ladder is cleared —
    /// where the Today deck points its study cards.
    static func firstUnpassed(total: Int, results: [Int: ChallengeResult]) -> Int? {
        guard total >= 1 else { return nil }
        return (1...total).first { results[$0]?.isPassed != true }
    }
}
