import Foundation

/// Loads the bundled `MinnaData.json` (compiled from the `minna` submodule by
/// `scripts/build-minna-data.py`) plus flat `<lesson>-<slug>.m4a` audio clips.
/// Generated files live in the app's Resources so the synchronized group copies them
/// incrementally (fast rebuilds), unlike a whole-submodule folder reference.
enum VocabStore {
    /// Default translation language; all ship in the bundle.
    static let defaultLanguage = "en"

    private struct LessonDTO: Codable { let number: Int; let entries: [VocabEntry] }
    private struct MinnaData: Codable {
        let languages: [String]
        let lessons: [LessonDTO]
        let translations: [String: [String: [String: String]]]  // lang -> lessonNo -> romaji -> text
    }

    private static let data: MinnaData = {
        guard let url = Bundle.main.url(forResource: "MinnaData", withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(MinnaData.self, from: raw)
        else { fatalError("MinnaData.json missing — run scripts/build-minna-data.py") }
        return decoded
    }()

    static var availableLanguages: [String] { data.languages }

    private static func build(_ language: String) -> [Lesson] {
        let tr = data.translations[language] ?? [:]
        return data.lessons.map { dto in
            let byRomaji = tr[String(dto.number)] ?? [:]
            let items = dto.entries.map { e in
                Vocab(lesson: dto.number,
                      kanji: e.kanji, kana: e.kana, romaji: e.romaji,
                      dictionary: e.dictionary, useKana: e.useKana ?? false,
                      translation: byRomaji[e.romaji] ?? "",
                      audio: e.audio)
            }
            return Lesson(number: dto.number, entries: items)
        }
    }

    // Per-language cache, built lazily (only the language actually shown — not all 7)
    // so launch doesn't decode 7×2089 entries. Guarded by a lock because Swift
    // Testing runs cases in parallel; an unlocked mutable static would data-race.
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [String: [Lesson]] = [:]

    /// All 50 lessons with translations resolved for `language` (built once, on demand).
    static func lessons(_ language: String = defaultLanguage) -> [Lesson] {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[language] { return cached }
        let built = build(language)
        cache[language] = built
        return built
    }

    static func allVocab(_ language: String = defaultLanguage) -> [Vocab] {
        lessons(language).flatMap(\.entries)
    }

    static func lesson(_ n: Int, _ language: String = defaultLanguage) -> Lesson {
        lessons(language)[n - 1]
    }

    /// Resolve a vocab's Kyoko clip in the bundle by its flat basename, e.g. "1-watashi".
    static func audioURL(for vocab: Vocab) -> URL? {
        guard let name = vocab.audio else { return nil }
        return Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    /// Resolve a kana's pre-generated Kyoko clip, e.g. "ka" → "kana-ka.m4a".
    static func kanaAudioURL(_ romaji: String) -> URL? {
        guard !romaji.isEmpty else { return nil }
        return Bundle.main.url(forResource: "kana-\(romaji)", withExtension: "m4a")
    }

    /// Localized display name for a language code, e.g. "zh-Hant" → "Chinese, Traditional".
    static func displayName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}

// MARK: - Text cleaning (port of RN utils/helpers.js `cleanWord`)

/// Strips display annotations before tiling/speaking:
/// removes （…）［…］「…」[…] and the ～ / 。 marks.
func cleanWord(_ text: String) -> String {
    var s = text
    for pattern in ["（.*?）", "［.*?］", "「.*?」", "\\[.*\\]"] {
        s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
    s = s.replacingOccurrences(of: "～", with: "")
    s = s.replacingOccurrences(of: "。", with: "")
    return s
}

// MARK: - Search (simple contains across the 4 fields; RN used fuse.js)

func searchVocab(_ query: String, in all: [Vocab] = VocabStore.allVocab()) -> [Vocab] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return [] }
    return all.filter { v in
        [v.kanji, v.kana, v.romaji, v.translation]
            .contains { $0.lowercased().contains(q) }
    }
}
