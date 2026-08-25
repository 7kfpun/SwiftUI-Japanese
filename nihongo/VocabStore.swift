import Foundation

/// Loads the bundled `MinnaData.json` (compiled from the `minna` submodule by
/// `scripts/build-minna-data.py`) plus flat `<lesson>-<slug>.m4a` audio clips.
/// Generated files live in the app's Resources so the synchronized group copies them
/// incrementally (fast rebuilds), unlike a whole-submodule folder reference.
enum VocabStore {
    /// Default translation language; all ship in the bundle. Stays "en" on purpose:
    /// it's the fallback for callers that name no language at all (and for missing
    /// translation data), not the user-facing first-launch choice.
    static let defaultLanguage = "en"

    /// First-launch default for `Pref.translationLanguage`: the device language, so a
    /// Vietnamese user gets Vietnamese meanings without first finding Settings →
    /// Meanings.
    ///
    /// `L.deviceDefault` resolves the device language against the *UI* list, which is 17
    /// codes for both apps. The meanings list is per-course and can be shorter — three
    /// for JLPT — so the answer has to be re-checked against this dataset before it is
    /// used, or a Vietnamese phone would select a language the data has no rows for.
    static var deviceDefaultLanguage: String {
        let ui = L.deviceDefault
        return availableLanguages.contains(ui) ? ui : defaultLanguage
    }

    private struct LessonDTO: Codable { let number: Int; let entries: [VocabEntry] }
    private struct MinnaData: Codable {
        let languages: [String]
        let lessons: [LessonDTO]
        let translations: [String: [String: [String: String]]]  // lang -> lessonNo -> romaji -> text
        /// Example-sentence translations, same shape as `translations`. Optional twice
        /// over: the JLPT data file has no key at all, and Minna carries only a few
        /// languages so far.
        let examples: [String: [String: [String: String]]]?
    }

    // Timed: this is the app's largest single launch cost, it blocks the first screen that
    // needs a word, and it is the one number that differs by course rather than by device
    // — 2,100 entries for Minna against 7,972 for JLPT, from the same code. A regression
    // here (a bigger dataset, a slower decode) looks like "the app got slow to open",
    // which is exactly the report that arrives without a cause attached.
    private static let data: MinnaData = Track.trace("vocab_decode") {
        guard let url = Bundle.main.url(forResource: Course.current.dataResource, withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(MinnaData.self, from: raw)
        else { fatalError("\(Course.current.dataResource).json missing — run scripts/build-minna-data.py") }
        return decoded
    }

    /// The meaning languages this course ships, in the app's one canonical order.
    ///
    /// Sorted rather than taken as-is from the data file: the file's order is whatever
    /// the build script's `LANGS`/`ORDER` happened to be, and the meanings picker sitting
    /// in a different order from the interface picker made two lists of the same
    /// languages look unrelated. See `L.languageOrder`.
    static let availableLanguages: [String] = L.ordered(data.languages)

    /// Whether this course's dataset carries example sentences at all.
    ///
    /// Derived from the data, never hardcoded per course: JLPT ships 7,972 entries and
    /// **not one example**, so every example-dependent control — Read along's
    /// "+ Example" rung, the Vocab List examples switch — was a button that did nothing
    /// in Bonsai JLPT. Reading it off the file rather than off `Course.current` means the
    /// day `build-jlpt-data.py` starts emitting sentences the features appear on their
    /// own, with no second place to remember to flip.
    ///
    /// Scans the decoded DTOs, so it touches no translation and builds no `Vocab`; it
    /// short-circuits on the first example a course has.
    static let hasExamples: Bool = data.lessons.contains { dto in
        dto.entries.contains { $0.example != nil }
    }

    private static func build(_ language: String) -> [Lesson] {
        // Fall back to English wholesale rather than per-entry: a stored preference can
        // name a language this course doesn't carry (someone switching between the two
        // apps, or a course that later drops a language), and the alternative is every
        // word rendering with a blank meaning — which looks like broken data, not like
        // a missing translation.
        let tr = data.translations[language] ?? data.translations[defaultLanguage] ?? [:]
        // **No English fallback here**, unlike the meanings above — a deliberate
        // asymmetry. A missing word-meaning leaves the row useless, so it borrows
        // English; a missing example translation just leaves the sentence standing on
        // its own (Japanese, furigana, romaji — all still shown), and an English line
        // under it for a Thai learner read as data in the wrong language rather than a
        // graceful fallback. Sixteen of the nineteen languages carry none yet; every
        // reader of `exampleTranslation` nil-guards, and the read-along's fourth leg
        // skips itself when the meaning is absent.
        let ex = data.examples?[language] ?? [:]
        return data.lessons.map { dto in
            // Keyed by romaji for Minna, by `key` for courses whose romaji isn't unique.
            let byKey = tr[String(dto.number)] ?? [:]
            let exByKey = ex[String(dto.number)] ?? [:]
            let items = dto.entries.map { e in
                Vocab(lesson: dto.number,
                      kanji: e.kanji, kana: e.kana, romaji: e.romaji,
                      dictionary: e.dictionary, useKana: e.useKana ?? false,
                      translation: byKey[e.key ?? e.romaji] ?? "",
                      audio: e.audio, key: e.key,
                      example: e.example,
                      exampleTranslation: exByKey[e.key ?? e.romaji])
            }
            return Lesson(number: dto.number, entries: items)
        }
    }

    // Per-language cache, built lazily (only the language actually shown — not all 17)
    // so launch doesn't decode 17×2100 entries. Guarded by a lock because Swift
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

    /// Resolve a vocab's clip in the bundle by its flat basename, e.g. "1-watashi".
    ///
    /// `voice` appends the suffix the build script wrote — the default voice's clips carry
    /// none, so `Vocab.audio` is already its filename. A voice with no clip for this word
    /// falls back to the default rather than to live TTS: the whole point of the alternate
    /// is that it is the *same* word in another voice, and dropping to a synthesiser mid-run
    /// would be a bigger change than simply repeating the default.
    static func audioURL(for vocab: Vocab, voice: Speech.Voice = .default) -> URL? {
        guard let name = vocab.audio else { return nil }
        return Bundle.main.url(forResource: name + voice.suffix, withExtension: "m4a")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    /// The bundled recording of this word's example sentence, or nil.
    ///
    /// Derived from the word's own clip name — one name locates both recordings and the
    /// data carries no second path.
    ///
    /// **`ex-` prefixed, and no subdirectory.** Xcode's synchronized folders add every
    /// resource individually, so the bundle is flat: without the prefix this file and
    /// the word's own clip would both be `1-watashi.m4a` at the root and one would
    /// silently win. Same reason `kana-` and `cheer-` exist. Looking it up by
    /// `subdirectory:` would find nothing at all.
    ///
    /// `PRIMARY` voice only: the alternate exists to make a *listening* rung a real
    /// test, and no rung asks a sentence — a second copy would be 47MB for nothing.
    static func exampleAudioURL(for vocab: Vocab) -> URL? {
        guard let name = vocab.audio, vocab.example != nil else { return nil }
        return Bundle.main.url(forResource: "ex-" + name, withExtension: "m4a")
    }

    /// How many words lesson `n` holds, read straight off the decoded data.
    ///
    /// Deliberately **not** `lesson(n).entries.count`. A word count doesn't depend on
    /// the meanings language, but that spelling does — it builds the whole language's
    /// `Vocab` array to read one number. Every caller that wanted it (rung counts,
    /// progress totals) passed no language at all, so they defaulted to `"en"` and made
    /// a Vietnamese user construct, and permanently retain, a second English corpus they
    /// never read. This touches no translation and constructs no `Vocab`.
    ///
    /// Out-of-range returns 0 rather than trapping: the callers loop over
    /// `Course.lessonCount`, and a course/dataset drift should degrade, not crash.
    static func wordCount(_ n: Int) -> Int { wordCounts[n] ?? 0 }

    private static let wordCounts: [Int: Int] =
        Dictionary(uniqueKeysWithValues: data.lessons.map { ($0.number, $0.entries.count) })

    /// Resolve a cheer's clip, e.g. "sugoi" → "cheer-sugoi.m4a" (or `-kenzaki`).
    ///
    /// Same naming rule and same fallback as `audioURL`: the default voice's clips carry
    /// no suffix, and a voice missing a phrase drops to the default rather than to live
    /// TTS. JLPT bundles the Minna-built set, so both voices are present in both apps.
    static func cheerAudioURL(_ key: String, voice: Speech.Voice = .default) -> URL? {
        guard !key.isEmpty else { return nil }
        return Bundle.main.url(forResource: "cheer-\(key)" + voice.suffix, withExtension: "m4a")
            ?? Bundle.main.url(forResource: "cheer-\(key)", withExtension: "m4a")
    }

    /// Resolve a kana's pre-generated Kyoko clip, e.g. "ka" → "kana-ka.m4a".
    static func kanaAudioURL(_ romaji: String) -> URL? {
        guard !romaji.isEmpty else { return nil }
        return Bundle.main.url(forResource: "kana-\(romaji)", withExtension: "m4a")
    }

    /// Localized display name for a language code, e.g. "zh-Hant" → "Chinese, Traditional".
    static func displayName(_ code: String) -> String {
        // `zh` is Simplified in this data set, but the system localizes the bare code as just
        // "Chinese" / 中文 — which sits in the picker directly above `zh-Hant`'s "Chinese,
        // Traditional" / 繁体中文 and reads as though the first one were the generic choice.
        // Ask for `zh-Hans` instead so it names itself: "Chinese, Simplified" / 简体中文.
        //
        // The *label* only. The stored value stays `zh`, because that's the key in
        // `MinnaData.json`'s translation map and in `UIStrings.json` — renaming it would
        // orphan every existing user's setting and both bundled data files.
        let identifier = code == "zh" ? "zh-Hans" : code
        return Locale.current.localizedString(forIdentifier: identifier) ?? code
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
