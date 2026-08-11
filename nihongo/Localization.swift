import Foundation

/// Lightweight app-UI localization, driven by the `appLanguage` setting (separate
/// from the vocabulary/meanings language). Strings live in the bundled
/// `UIStrings.json` (one map per language). RootView applies `.id(appLanguage)` so a
/// language change rebuilds the tree and every `L.t(...)` re-reads instantly.
enum L {
    /// The UI languages, read out of `UIStrings.json` itself.
    ///
    /// Deliberately **not** `VocabStore.availableLanguages`, which it used to be. The
    /// two lists were the same 17 codes while Minna was the only course, so one could
    /// stand in for the other — but JLPT ships meanings in three languages against the
    /// same 17-language UI. Defining the UI list in terms of the vocab list would have
    /// silently dropped a JLPT user's Vietnamese *interface* because the dataset has no
    /// Vietnamese *meanings*. They are separate questions and are now separate lists.
    static let availableLanguages = table.keys.sorted()

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
