import Foundation

/// Lightweight app-UI localization, driven by the `appLanguage` setting (separate
/// from the vocabulary/meanings language). Strings live in the bundled
/// `UIStrings.json` (one map per language). RootView applies `.id(appLanguage)` so a
/// language change rebuilds the tree and every `L.t(...)` re-reads instantly.
enum L {
    /// The order both language pickers use, roughly by how many people learn Japanese in
    /// each language — Japan Foundation learner-survey territories, not speaker counts.
    ///
    /// English leads because it is the fallback everywhere and the default when the
    /// device language isn't shipped, not because it is the largest. The two Chinese
    /// variants sit together: they are one decision to a reader, and separating them by
    /// half a list makes the picker look broken.
    ///
    /// This is the *only* ordering. Both `L.availableLanguages` and
    /// `VocabStore.availableLanguages` filter it, so the interface picker and the meanings
    /// picker can never disagree — they did, alphabetical against data-file order, and it
    /// read as two unrelated lists of the same languages.
    static let languageOrder = [
        "en",                                   // default and universal fallback
        "zh", "zh-Hant",                        // China, then Taiwan and Hong Kong
        "id", "ko", "vi", "th", "fil", "my",    // the rest of the Asian learner base
        "hi", "bn", "ta", "te",                 // the subcontinent, kept as a block
        "es", "fr", "de", "ru",                 // Europe and the Americas
    ]

    /// Sorts `codes` into `languageOrder`, appending anything unlisted alphabetically.
    ///
    /// Unknown codes are appended rather than dropped: a language added to the data or to
    /// `UIStrings.json` and forgotten here should look misplaced, not disappear.
    static func ordered(_ codes: [String]) -> [String] {
        let rank = Dictionary(uniqueKeysWithValues: languageOrder.enumerated().map { ($1, $0) })
        return codes.sorted {
            (rank[$0] ?? .max, $0) < (rank[$1] ?? .max, $1)
        }
    }

    /// The UI languages, read out of `UIStrings.json` itself.
    ///
    /// Deliberately **not** `VocabStore.availableLanguages`, which it used to be. The
    /// two lists were the same 17 codes while Minna was the only course, so one could
    /// stand in for the other — but JLPT ships meanings in two languages against the
    /// same 17-language UI. Defining the UI list in terms of the vocab list would have
    /// silently dropped a JLPT user's Vietnamese *interface* because the dataset has no
    /// Vietnamese *meanings*. They are separate questions and are now separate lists —
    /// but they share `languageOrder`, so they still read as one family.
    static let availableLanguages = ordered(Array(table.keys))

    private static let table: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "UIStrings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return [:] }
        return decoded
    }()

    /// First-launch default: the device language if we ship it, else English.
    static let deviceDefault: String = {
        let lang = Locale.current.language
        // Any Chinese device language defaults to Traditional (users can switch to zh).
        if lang.languageCode?.identifier == "zh" { return "zh-Hant" }
        let code = lang.languageCode?.identifier ?? "en"
        return availableLanguages.contains(code) ? code : "en"
    }()

    static var current: String {
        UserDefaults.standard.string(forKey: Pref.appLanguage) ?? deviceDefault
    }

    /// Localized string for `key`, falling back to English then the key itself.
    static func t(_ key: String) -> String {
        table[current]?[key] ?? table["en"]?[key] ?? key
    }

    /// Localized format string with `%@` placeholders filled in.
    static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}
