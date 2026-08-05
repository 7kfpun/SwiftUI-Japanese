import Foundation

/// Reads the `minna` submodule directly from the app bundle (added as a folder
/// reference at `minna/`) and exposes lessons + a flat search index, resolved into
/// any of the bundled translation languages. No build-time codegen — the raw
/// `vocab/{n}.json` + `{lang}/{n}.json` files are the single source of truth.
enum VocabStore {
    /// Default translation language; all ship in the bundle.
    static let defaultLanguage = "en"
    static let availableLanguages = ["en", "zh", "zh-Hant", "vi", "de", "th", "my"]
    static let lessonRange = 1...50

    private struct VocabFile: Codable { let data: [VocabEntry] }

    /// Decode a JSON resource from a subdirectory of the bundled `minna/` folder.
    private static func decode<T: Decodable>(_ subdirectory: String, _ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json",
                                        subdirectory: subdirectory),
              let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: raw)
    }

    private static func build(_ language: String) -> [Lesson] {
        lessonRange.map { n in
            let file: VocabFile = decode("minna/vocab", "\(n)") ?? VocabFile(data: [])
            let tr: [String: String] = decode("minna/\(language)", "\(n)") ?? [:]
            let items = file.data.map { e in
                Vocab(lesson: n,
                      kanji: e.kanji, kana: e.kana, romaji: e.romaji,
                      dictionary: e.dictionary, useKana: e.useKana ?? false,
                      translation: tr[e.romaji] ?? "",
                      audio: e.audio?["kyoko"])
            }
            return Lesson(number: n, entries: items)
        }
    }

    /// Every language's lessons, built once. `static let` init is thread-safe and
    /// runs exactly once, so reads are lock-free and race-free (Swift Testing runs
    /// test cases in parallel — a mutable cache here would data-race and crash).
    private static let catalog: [String: [Lesson]] = {
        var dict: [String: [Lesson]] = [:]
        for lang in availableLanguages { dict[lang] = build(lang) }
        return dict
    }()

    /// All 50 lessons with translations resolved for `language`.
    static func lessons(_ language: String = defaultLanguage) -> [Lesson] {
        catalog[language] ?? catalog[defaultLanguage] ?? []
    }

    static func allVocab(_ language: String = defaultLanguage) -> [Vocab] {
        lessons(language).flatMap(\.entries)
    }

    static func lesson(_ n: Int, _ language: String = defaultLanguage) -> Lesson {
        lessons(language)[n - 1]
    }

    /// Resolve a vocab's Kyoko clip in the bundle from its relative path,
    /// e.g. "audio/kyoko/1/watashi.m4a" → minna/audio/kyoko/1 + "watashi".
    static func audioURL(for vocab: Vocab) -> URL? {
        guard let rel = vocab.audio else { return nil }
        let path = rel as NSString
        let dir = "minna/" + path.deletingLastPathComponent
        let file = (path.lastPathComponent as NSString).deletingPathExtension
        let ext = path.pathExtension.isEmpty ? "m4a" : path.pathExtension
        return Bundle.main.url(forResource: file, withExtension: ext, subdirectory: dir)
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
