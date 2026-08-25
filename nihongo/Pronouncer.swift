import SwiftUI
import AVFoundation

/// A short reaction to a finished challenge — praise for a pass, encouragement for a
/// miss — spoken *and* shown, in Japanese with its reading and meaning.
///
/// **Three fields because they answer to different rules.** `text` is content in the
/// language being learned, like a vocabulary word: it stays Japanese in every locale and
/// belongs nowhere near `UIStrings.json`. `key` is a filename and a reading. `meaning` is
/// interface, so it goes through `L.t` and owes all 18 languages like every other string.
///
/// Showing all three is what turns sixteen decorations into sixteen phrases a learner
/// actually ends up knowing — they arrive at the one moment their sense is unmistakable,
/// which is worth more than the same words met on a list.
struct Cheer: Equatable {
    /// **Kana only, no kanji.** Partly because a beginner meeting these dozens of times
    /// should meet phrases they could plausibly read, and partly because the generator
    /// synthesises from exactly this string: bare kanji is ambiguous to a TTS engine
    /// (see the submodule's `generate-audio` skill, "synthesise from kana, never kanji").
    let text: String
    /// Romaji reading, which doubles as the stem of a bundled clip (`cheer-<key>.m4a`).
    /// The clips come from the submodule's `voices/cheer-<voice>-<key>.m4a` via
    /// `build-minna-data.py`, which derives the key by globbing — so renaming one here
    /// without renaming the clip drops that phrase to live TTS, which
    /// `cheersVaryAndCanNameAClip` is there to catch. Hyphens separate words, so `romaji`
    /// renders it without a second copy of the reading.
    let key: String
    /// English source string for the gloss, passed through `L.t` — so this one field
    /// *is* interface and does owe all 18 languages, unlike `text`.
    let meaning: String

    /// The reading as it's shown: `yoku-dekimashita` → `yoku dekimashita`.
    var romaji: String { key.replacingOccurrences(of: "-", with: " ") }

    /// After a pass. Eight ways to say it rather than one: a learner clears several rungs
    /// in a sitting, so a short list is a catchphrase by the third one, and praise you can
    /// predict has stopped being praise. はなまる is the flower-circle a Japanese teacher
    /// draws on perfect work — no learner will know it the first time, which is rather
    /// the point of putting it where its meaning is unmistakable.
    static let passed = [
        Cheer(text: "すごい",         key: "sugoi",            meaning: "Amazing"),
        Cheer(text: "よくできました",  key: "yoku-dekimashita", meaning: "Well done"),
        Cheer(text: "いいですね",      key: "ii-desu-ne",       meaning: "Nice"),
        Cheer(text: "やったね",       key: "yatta-ne",         meaning: "You did it"),
        Cheer(text: "じょうずですね",  key: "jouzu-desu-ne",    meaning: "You're good at this"),
        Cheer(text: "そのちょうし",    key: "sono-choushi",     meaning: "That's the spirit"),
    ]

    /// Held back for a clean sweep. はなまる is the flower-circle a teacher draws on
    /// perfect work and かんぺき says so outright; both name *full marks*, so hearing
    /// either after two right out of three reads as the app not watching — praise that
    /// outranks the score is worth less than no praise. They stay in the pass pool's
    /// place only when the run actually earned three stars.
    static let perfect = [
        Cheer(text: "はなまる",       key: "hanamaru",         meaning: "Full marks"),
        Cheer(text: "かんぺき",       key: "kanpeki",          meaning: "Perfect"),
    ]

    /// After a miss. Encouragement, never correction — the screen already lists the words
    /// to review, so the voice's only job is to make trying again feel ordinary. がんばろう
    /// is the inclusive form of がんばって ("let's keep going"), which is why both are here:
    /// eight rungs of being told to try harder wants at least one voice standing alongside.
    static let missed = [
        Cheer(text: "がんばって",      key: "ganbatte",        meaning: "Keep at it"),
        Cheer(text: "おしい",         key: "oshii",           meaning: "So close"),
        Cheer(text: "だいじょうぶ",    key: "daijoubu",        meaning: "It's all right"),
        Cheer(text: "もういちど",      key: "mou-ichido",      meaning: "Once more"),
        Cheer(text: "つぎはできる",    key: "tsugi-wa-dekiru", meaning: "You'll get it next time"),
        Cheer(text: "あきらめないで",  key: "akiramenaide",    meaning: "Don't give up"),
        Cheer(text: "もうすこし",      key: "mou-sukoshi",     meaning: "A little further"),
        Cheer(text: "がんばろう",      key: "ganbarou",        meaning: "Let's keep going"),
    ]

    /// Pick one, never the one just used. Pure, so the no-repeat rule is testable —
    /// "varied" that can repeat immediately is the case people actually notice.
    static func pick(from phrases: [Cheer], avoiding last: Cheer?) -> Cheer? {
        (phrases.filter { $0 != last }.randomElement() ?? phrases.randomElement())
    }

    /// Which pool a run has earned. Three tiers, not two: see `perfect`.
    enum Tier: Hashable { case perfect, passed, missed }

    static func tier(stars: Int, passed: Bool) -> Tier {
        if stars >= 3 { return .perfect }
        return passed ? .passed : .missed
    }

    static func pool(_ tier: Tier) -> [Cheer] {
        switch tier {
        case .perfect: return perfect
        case .passed:  return Self.passed
        case .missed:  return missed
        }
    }

    /// The last of each kind, so the tiers don't silence each other — they are separate
    /// pools and a repeat across them isn't a repeat to the ear.
    @MainActor private static var last: [Tier: Cheer] = [:]

    @MainActor
    static func next(stars: Int, passed: Bool) -> Cheer? {
        let tier = tier(stars: stars, passed: passed)
        guard let choice = pick(from: pool(tier), avoiding: last[tier]) else { return nil }
        last[tier] = choice
        return choice
    }
}

/// Word-pronunciation seam: every "tap to hear" path goes through it, so no view knows
/// how a word is played. `AudioPronouncer` (below) is the real one — bundled `say -v
/// Kyoko` clips with live `AVSpeechSynthesizer` as the fallback; `SilentPronouncer` is
/// the environment default, so previews and tests make no sound.
protocol Pronouncer {
    func speak(_ vocab: Vocab, voice: Speech.Voice)
    func speak(kana: K)
    func speak(cheer: Cheer)
    /// An example sentence. Live TTS only, deliberately: the upstream clips exist but
    /// bundling ~4,200 of them is a 50MB+ app-size decision that hasn't been made —
    /// the synthesiser keeps the feature offline either way, and swapping in bundled
    /// clips later changes this one implementation, not the callers.
    func speak(sentence: String)
    /// The example sentence of a specific word — prefers that word's bundled recording
    /// and falls back to speaking `sentence`. Separate from `speak(sentence:)` because
    /// only a caller holding the `Vocab` can name the clip.
    func speak(example vocab: Vocab)
    func stop()
}

extension Pronouncer {
    /// The default voice — what every screen but the Challenge ladder wants, so no call
    /// site had to change when the alternate arrived.
    func speak(_ vocab: Vocab) { speak(vocab, voice: .default) }
}

/// No-op — used in previews/tests where audio isn't wanted.
struct SilentPronouncer: Pronouncer {
    func speak(_ vocab: Vocab, voice: Speech.Voice) {}
    func speak(kana: K) {}
    func speak(cheer: Cheer) {}
    func speak(sentence: String) {}
    func speak(example vocab: Vocab) {}
    func stop() {}
}

/// One-time, mixable audio-session activation shared by every playback path
/// (`AudioPronouncer`, `LessonPlayer`). `.mixWithOthers` keeps the user's background
/// music playing (and lets the word be heard even with the silent switch on) instead
/// of taking over audio at launch.
enum PlaybackSession {
    private static var activated = false
    static func activate() {
        guard !activated else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        activated = true
    }

}

/// How a word gets played, in one place: which bundled clip, and — when there isn't
/// one — what voice says it and how fast.
///
/// Two paths play audio and they can't share a class: `AudioPronouncer` is fire-and-
/// forget, while `LessonPlayer` sequences a whole lesson and needs delegate callbacks
/// to advance. They *can* share the policy, which is what kept drifting: both carried
/// their own copy of the voice lookup, the 0.4 rate and the `cleanWord` call, and
/// nothing made them agree.
enum Speech {
    /// Which recorded voice a clip comes from.
    ///
    /// Minna bundles two: a default used everywhere, and an alternate the Challenge
    /// ladder mixes in. That mix is the reason the alternate exists — with one voice a
    /// listening rung can be passed by recognising the waveform instead of the word, so
    /// the clip quietly becomes the answer key. Two voices make it a listening test again.
    ///
    /// `suffix` is the filename tail `build-minna-data.py` writes, and the default's is
    /// empty on purpose: its clips keep the bare name, so `Vocab.audio` is already its
    /// filename and nothing outside this type has to know voices exist. JLPT ships one
    /// voice, and `audioURL` falls back to the default, so `.alternate` is harmless there.
    enum Voice: CaseIterable {
        case `default`, alternate

        var suffix: String {
            switch self {
            case .default:   return ""
            case .alternate: return "-kenzaki"
            }
        }

        /// One of the two, for a ladder question that wants an unpredictable voice.
        static func random() -> Voice { Bool.random() ? .default : .alternate }
    }

    /// The course's language. The `hasPrefix` fallback catches devices where the exact
    /// region tag isn't installed but some voice for the language is.
    static let locale = "ja-JP"
    private static var languageCode: String { String(locale.prefix(2)) }

    /// A spoken utterance for `text` — annotations stripped, voice resolved, rate set.
    ///
    /// `locale` defaults to Japanese, the only thing this app spoke until meanings could
    /// be read aloud. A meaning must be spoken in *its* language: an English gloss pushed
    /// through a Japanese voice is not accented, it is unintelligible.
    static func utterance(_ text: String, locale: String = Speech.locale) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: cleanWord(text))
        let code = String(locale.prefix(2))
        u.voice = AVSpeechSynthesisVoice(language: locale)
            ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(code) }
        u.rate = 0.4
        return u
    }

    /// The BCP-47 tag to speak a meaning in, for one of the app's translation languages.
    ///
    /// Most codes are already valid tags; the ones that aren't are the ones that would
    /// silently pick no voice at all. `zh` is Simplified in this data set, so it must ask
    /// for `zh-CN` rather than the bare code, and `fil` has no voice under that tag —
    /// Apple ships Filipino as `fil-PH`.
    static func meaningLocale(_ language: String) -> String {
        switch language {
        case "zh":      return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "en":      return "en-US"
        case "fil":     return "fil-PH"
        default:        return language
        }
    }

    /// A player primed for the word's bundled clip, or nil when it has none — the caller
    /// then falls back to `utterance(_:)`. Callers that need completion callbacks set
    /// `delegate` on the result themselves.
    static func clipPlayer(for vocab: Vocab, voice: Voice = .default) -> AVAudioPlayer? {
        guard let url = VocabStore.audioURL(for: vocab, voice: voice),
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.volume = 1
        p.prepareToPlay()
        return p
    }
}

/// Plays the bundled Kyoko clip for a vocab word; falls back to live
/// `AVSpeechSynthesizer` for any word whose clip is absent and for bare kana tiles.
final class AudioPronouncer: Pronouncer {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    func speak(_ vocab: Vocab, voice: Speech.Voice = .default) {
        stop()
        PlaybackSession.activate()
        if let p = Speech.clipPlayer(for: vocab, voice: voice) {
            player = p
            p.play()
        } else {
            // Only an anomaly for a course that ships clips. Both do today, but the flag
            // is what stops this firing on every single tap the day one doesn't — the
            // event is calibrated for a handful of words in thousands, and a clip-less
            // course would drown the signal that catches a genuinely missing clip.
            if Course.current.hasBundledAudio { Track.audioMissing(vocab.id) }
            speakLive(vocab.kana)
        }
    }

    func speak(kana: K) {
        stop()
        PlaybackSession.activate()
        // Prefer the bundled kana clip (reliable, incl. simulator); TTS backup.
        if let url = VocabStore.kanaAudioURL(kana.romaji),
           let p = try? AVAudioPlayer(contentsOf: url) {
            player = p
            p.volume = 1
            p.prepareToPlay()
            p.play()
        } else {
            Track.audioMissing("kana-\(kana.romaji)")
            speakLive(kana.hiragana)
        }
    }

    /// Same clip-then-synthesiser order as everything else, with a **random voice**.
    ///
    /// Both voices are bundled for every phrase, so two readings of eight phrases is
    /// sixteen distinct reactions for no extra work. Unlike the Challenge ladder — where
    /// alternating voices is what stops a listening rung being passable by recognising
    /// the waveform — here it is purely variety, and `cheerAudioURL` falls back to the
    /// default voice, so a course shipping one voice degrades to eight rather than
    /// breaking.
    ///
    /// No `audioMissing` event, unlike the two above: that signal is calibrated for a
    /// handful of missing words in thousands, and sixteen phrases would drown it.
    func speak(cheer: Cheer) {
        stop()
        PlaybackSession.activate()
        if let url = VocabStore.cheerAudioURL(cheer.key, voice: .random()),
           let p = try? AVAudioPlayer(contentsOf: url) {
            player = p
            p.volume = 1
            p.prepareToPlay()
            p.play()
        } else {
            speakLive(cheer.text)
        }
    }

    func speak(sentence: String) {
        stop()
        PlaybackSession.activate()
        speakLive(sentence)
    }

    /// The recorded sentence when the word has one, the synthesiser when it doesn't.
    ///
    /// Both exist on purpose. All 2,100 Minna entries ship a clip, but a future course
    /// may ship none — and the fallback is what keeps "tap the sentence to hear it"
    /// working rather than silently doing nothing. Same clip-or-speak shape as
    /// `speak(_:voice:)`; still synthesised audio, VOICEVOX rather than a reader.
    func speak(example vocab: Vocab) {
        stop()
        PlaybackSession.activate()
        if let url = VocabStore.exampleAudioURL(for: vocab),
           let p = try? AVAudioPlayer(contentsOf: url) {
            p.volume = 1
            p.prepareToPlay()
            player = p
            p.play()
            return
        }
        if let spoken = vocab.example?.spoken { speakLive(spoken) }
    }

    func stop() {
        player?.stop(); player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    private func speakLive(_ text: String) { synth.speak(Speech.utterance(text)) }
}

private struct PronouncerKey: EnvironmentKey {
    static let defaultValue: Pronouncer = SilentPronouncer()
}

extension EnvironmentValues {
    var pronouncer: Pronouncer {
        get { self[PronouncerKey.self] }
        set { self[PronouncerKey.self] = newValue }
    }
}
