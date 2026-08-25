import Foundation

/// One vocabulary entry as stored in the bundled data (mirrors `minna/vocab/{n}.json`).
struct VocabEntry: Codable, Hashable {
    let kanji: String
    let kana: String
    let romaji: String
    let dictionary: String?
    let useKana: Bool?
    let audio: String?             // bundled clip basename (no extension), e.g. "1-watashi"
    /// A short Japanese sentence using the word. Optional because the JLPT dataset
    /// doesn't carry them (yet); readers must treat absence as normal.
    let example: ExampleSentence?
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
    /// `var` with defaults, unlike the fields above, so the memberwise init keeps its
    /// existing shape — the two graceful-degradation call sites (Train, Learn) and the
    /// tests construct a `Vocab` without naming these.
    var example: ExampleSentence? = nil
    var exampleTranslation: String? = nil

    /// romaji is only unique *within* a lesson, so id must include the lesson. Courses
    /// whose romaji isn't unique even then supply `key`; Minna's ids are unchanged.
    var id: String { "\(lesson)/\(key ?? romaji)" }

    /// Show kana instead of kanji when the source says so, or when they're identical.
    var displaysKanji: Bool { !useKana && kanji != kana }
}

/// One example sentence, split into index-aligned phrases (one element per bunsetsu).
///
/// Three arrays rather than one string because Japanese has no spaces — kanji are what
/// mark where words start, so the all-kana line is the *hardest* to read, and romaji
/// alone never teaches which kana spell which sound. Zipped into columns (kanji over
/// kana over romaji) the alignment does the teaching. There is deliberately no flat
/// `sentence` copy: joining an array reproduces it, and a stored copy could only ever
/// disagree with its parts.
struct ExampleSentence: Codable, Hashable {
    let kanji: [String]
    let kana: [String]
    let romaji: [String]

    /// What the synthesiser reads: the kana, which is what the sentences were authored
    /// in — UniDic-style kanji readings get 何時 wrong where the author meant なんじ.
    var spoken: String { kana.joined() }

    /// The furigana for phrase `i`, or nil when nothing needs annotating.
    ///
    /// Real furigana marks only the kanji: 学生です。 takes がくせい, never
    /// がくせいです。 — the trailing です。 is already kana on the main line, and
    /// repeating it reads as a typo. The phrases arrive whole, so this trims the
    /// characters the two strings share at either end (です。 suffixes, お〜 honorific
    /// prefixes) and annotates what differs. Identical phrases annotate nothing.
    func reading(at i: Int) -> String? { annotated(at: i)?.reading }

    /// Phrase `i` split for furigana layout: the shared prefix, the kanji core the
    /// reading annotates, the shared suffix, and the reading itself. Nil when nothing
    /// needs annotating. `reading(at:)` is this minus the positions — the split exists
    /// so the view can centre the reading over the *core* (本) rather than over the
    /// whole phrase (本です。), which parked ほん visibly off its kanji.
    func annotated(at i: Int) -> (prefix: String, core: String, suffix: String, reading: String)? {
        guard kanji.indices.contains(i), kana.indices.contains(i) else { return nil }
        var written = Array(kanji[i]), read = Array(kana[i])
        guard written != read else { return nil }
        var prefix: [Character] = [], suffix: [Character] = []
        while let w = written.first, let r = read.first, w == r {
            prefix.append(w); written.removeFirst(); read.removeFirst()
        }
        while let w = written.last, let r = read.last, w == r,
              read.count > 1 || written.count > 1 {
            suffix.insert(w, at: 0); written.removeLast(); read.removeLast()
        }
        guard !read.isEmpty else { return nil }
        return (String(prefix), String(written), String(suffix), String(read))
    }
}

struct Lesson: Identifiable, Hashable {
    let number: Int
    let entries: [Vocab]
    var id: Int { number }
}
