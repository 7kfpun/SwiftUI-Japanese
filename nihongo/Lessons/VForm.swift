import SwiftUI

/// The forms a vocabulary question can show — shared by the Challenge ladder and
/// Practice. Lived inside TrainView.swift until Train merged into Practice; it moved
/// out first because `Challenge.forms`, `ChallengeQuestion` and the ladder's autoplay
/// rule all depend on it, and deleting Train must not touch the scored ladder.
enum VForm: Int, CaseIterable {
    case kana, kanji, romaji, translation, audio
    var label: String {
        switch self {
        case .kana: return "kana"; case .kanji: return "kanji"
        case .romaji: return "romaji"; case .translation: return "meaning"
        case .audio: return "audio"
        }
    }
    func value(_ v: Vocab) -> String {
        switch self {
        case .kana: return v.kana; case .kanji: return v.kanji
        case .romaji: return v.romaji; case .translation: return v.translation
        case .audio: return v.kana   // never shown — the audio prompt uses a speaker
        }
    }
    var isAudio: Bool { self == .audio }

    /// Whether this form's value is written in Japanese script — i.e. whether a Japanese
    /// face may draw it. Both Train and the Challenge ladder can put a *translation* in
    /// the prompt slot, so without this a German, Thai or Tamil sentence went through
    /// `Theme.jp` (Hiragino Maru): plain-looking in the Latin languages, and in the nine
    /// non-Latin ones a run of Hiragino punctuation and digits spliced into the script's
    /// own fallback face. `.audio` answers true because its value is the kana — it is
    /// never displayed anyway.
    var isJapanese: Bool { self != .romaji && self != .translation }

    /// The face a prompt in this form takes — shared by Train and the Challenge ladder,
    /// which pose the same question at different sizes.
    ///
    /// Japanese keeps `Theme.jp` at the screen's own fixed size. Romaji takes the rounded
    /// Latin face at that *same* size, so switching between the two doesn't resize the
    /// card. A translation takes the plain system font at a Dynamic Type style instead:
    /// it's prose in the UI language, which is the one thing here that has no business
    /// carrying a fixed point size, and neutral is how every other translation in the app
    /// is set (`SwipeOptionChip`, the card faces, the vocab rows).
    func promptFont(wordSize: CGFloat, translationStyle: Font.TextStyle) -> Font {
        switch self {
        case .kana, .kanji, .audio: return Theme.jp(wordSize)
        case .romaji:               return Theme.display(wordSize, weight: .semibold)
        case .translation:          return .system(translationStyle, weight: .semibold)
        }
    }
}

extension VForm {
    /// Whether auto-playing the answer's pronunciation is safe for a prompt form.
    /// Hearing the word identifies it — fine when the prompt IS the word (kana/kanji/
    /// romaji/audio), but a translation prompt with word options would be given away.
    /// (Moved verbatim from TrainModel when Train merged into Practice.)
    static func promptAudioSafe(from: VForm) -> Bool { from != .translation }

    /// The same question asked of the whole pair, because the prompt is only half of it:
    /// hearing the word also hands over any answer that *is* the word's sound. A kana or
    /// romaji answer is therefore safe only when the prompt already carries that sound —
    /// an audio rung, or the reading itself.
    ///
    /// The ladder's pairs are unaffected (`.audio → .kana` is a listening question, and
    /// `.translation → .kana` was already refused). Practice is where it bites: its pair
    /// sheet and Mixed can ask kanji → kana, and auto-play read the answer out loud
    /// before the learner could pick it.
    static func promptAudioSafe(from: VForm, to: VForm) -> Bool {
        guard promptAudioSafe(from: from) else { return false }
        guard to == .kana || to == .romaji else { return true }
        return from == .audio || from == .kana || from == .romaji
    }
}
