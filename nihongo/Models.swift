import Foundation

/// One vocabulary entry as stored in the bundled data (mirrors `minna/vocab/{n}.json`).
struct VocabEntry: Codable, Hashable {
    let kanji: String
    let kana: String
    let romaji: String
    let dictionary: String?
    let useKana: Bool?
    let audio: String?             // bundled clip basename (no extension), e.g. "1-watashi"
    /// Stable per-entry key, and the key the translation map is keyed by.
    ///
    /// Absent in Minna data, where romaji is unique within a lesson and does both jobs.
    /// The JLPT dataset needs it: it joins on a content hash, and its lessons
    /// deliberately group same-reading words (掻く／描く／欠く all read かく), so romaji
    /// is *not* unique within a lesson there and `Vocab.id` would collide.
    let key: String?
}

/// A vocabulary item enriched with its lesson number and resolved translation.
/// This is what the UI renders and what search indexes.
struct Vocab: Identifiable, Hashable {
    let lesson: Int
    let kanji: String
    let kana: String
    let romaji: String
    let dictionary: String?
    let useKana: Bool
    let translation: String
    let audio: String?          // bundled clip basename (no extension), or nil
    /// See `VocabEntry.key` — nil for Minna, where romaji already identifies an entry.
    let key: String?

    /// romaji is only unique *within* a lesson, so id must include the lesson. Courses
    /// whose romaji isn't unique even then supply `key`; Minna's ids are unchanged.
    var id: String { "\(lesson)/\(key ?? romaji)" }

    /// Show kana instead of kanji when the source says so, or when they're identical.
    var displaysKanji: Bool { !useKana && kanji != kana }
}

struct Lesson: Identifiable, Hashable {
    let number: Int
    let entries: [Vocab]
    var id: Int { number }
}
