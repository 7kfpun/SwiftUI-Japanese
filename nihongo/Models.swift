import Foundation

/// One vocabulary entry as stored in the bundled data (mirrors `minna/vocab/{n}.json`).
struct VocabEntry: Codable, Hashable {
    let kanji: String
    let kana: String
    let romaji: String
    let dictionary: String?
    let useKana: Bool?
    let audio: String?             // bundled clip basename (no extension), e.g. "1-watashi"
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

    /// romaji is only unique *within* a lesson, so id must include the lesson.
    var id: String { "\(lesson)/\(romaji)" }

    /// Show kana instead of kanji when the source says so, or when they're identical.
    var displaysKanji: Bool { !useKana && kanji != kana }
}

struct Lesson: Identifiable, Hashable {
    let number: Int
    let entries: [Vocab]
    var id: Int { number }
}
