import Foundation
import Observation

/// How far a word has climbed in Practice.
///
/// Raw values are the on-disk wire format — **append-only, never renumber**. The ladder
/// is deliberately simple: self-assessing "got it" promotes to `.recognized`, one correct
/// quiz answer proves it and lands `.memorized`, and a wrong quiz answer demotes back to
/// `.seen`, so a lucky guess self-corrects the next time the word comes around. No dates:
/// the Challenge ladder is the test — this only decides which *face* a word shows next.
enum WordStage: Int, Codable, Comparable {
    case unseen = 0, seen = 1, recognized = 2, memorized = 3

    static func < (a: WordStage, b: WordStage) -> Bool { a.rawValue < b.rawValue }
}

/// Per-word Practice state, keyed by `Vocab.id`.
///
/// **Local-only, on purpose.** The other progress stores are CloudKit `@Model`s, and a
/// new one would need its schema deployed to Production in both containers before
/// release — ship without that step and it silently never syncs (the `StudyDay` trap).
/// Practice stages are unscored study metadata: losing them costs a learner a few
/// re-assessments, not history, so they stay on this device by decision, not oversight.
///
/// **A JSON file, not `UserDefaults`.** JLPT is 7,972 words; a well-practiced map is a
/// few hundred kilobytes that would otherwise sit inside the defaults plist and be
/// rewritten whole on every swipe. `Pref` stays what it is — scalars.
@Observable
final class PracticeProgress {
    /// Absent word — the common case forever, since only practiced words get a row.
    func stage(of word: String) -> WordStage { stages[word] ?? .unseen }

    private(set) var stages: [String: WordStage] = [:]

    func set(_ stage: WordStage, for word: String) {
        guard stages[word] != stage else { return }
        if stage == .unseen { stages.removeValue(forKey: word) } else { stages[word] = stage }
        scheduleSave()
    }

    /// The hero card's numbers, for one lesson's entries. O(lesson size) dictionary
    /// lookups — never a scan of the whole map, which is what keeps a 201-lesson course
    /// as cheap as a 50-lesson one.
    ///
    /// Three buckets, not four: `seen` folds into `unseen` for display. The canvas shows
    /// a three-number line, and "seen but not yet self-assessed" is still a word the
    /// learner has to come back for — counting it "unseen" understates progress rather
    /// than overstating it, which is the direction this app always errs.
    struct Counts: Equatable {
        var memorized = 0
        var recognized = 0
        var unseen = 0
    }

    func counts(for entries: [Vocab]) -> Counts {
        var c = Counts()
        for word in entries {
            switch stage(of: word.id) {
            case .memorized:  c.memorized += 1
            case .recognized: c.recognized += 1
            case .seen, .unseen: c.unseen += 1
            }
        }
        return c
    }

    // MARK: - Persistence

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private static let version = 1

    private struct File: Codable {
        let v: Int
        let words: [String: Int]
    }

    /// `directory` is injectable so tests write to a temp dir instead of the real
    /// Application Support. The default creates the directory if missing — a fresh
    /// install has neither it nor the file, and both absences mean "empty store".
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("PracticeProgress.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return }
        // Best-effort whatever the version: raw ints clamp into the known ladder, so a
        // newer format degrades to the stages this build understands rather than to
        // nothing. Unparseable files start empty — this is practice metadata, and an
        // error dialog about it would cost more than the loss does.
        stages = file.words.compactMapValues {
            WordStage(rawValue: min(max($0, 0), WordStage.memorized.rawValue))
        }
    }

    /// Debounced: a Practice session writes once a second at most, not once a swipe.
    /// `PracticeView.onDisappear` calls `saveNow()` so the last grade always lands.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let file = File(v: Self.version, words: stages.mapValues(\.rawValue))
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
