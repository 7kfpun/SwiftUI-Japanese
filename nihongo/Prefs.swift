import Foundation

/// Central registry of UserDefaults / @AppStorage keys — one place, no scattered
/// string literals (a typo would silently create a brand-new setting).
enum Pref {
    static let appLanguage         = "appLanguage"
    static let translationLanguage = "translationLanguage"
    static let soundOn             = "isSoundOn"
    static let ordered             = "isOrdered"
    static let kanjiShown          = "isKanjiShown"
    static let kanaShown           = "isKanaShown"
    static let romajiShown         = "isRomajiShown"
    static let translationShown    = "isTranslationShown"
    static let kanaTileScript      = "kanaTileScript"
    /// Train's word order — false (random) by default; Learn's `ordered` key defaults
    /// the other way, so the two modes deliberately don't share a switch.
    static let trainOrdered        = "trainOrdered"
    /// Per-device opt-out of analytics collection, independent of DEBUG/Release —
    /// toggled via a long-press on the version footer in Settings. Lets the
    /// developer exclude their own TestFlight/Release usage without a rebuild.
    static let analyticsExcluded   = "analyticsExcluded"
}
