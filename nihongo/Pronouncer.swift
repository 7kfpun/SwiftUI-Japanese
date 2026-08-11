import SwiftUI
import AVFoundation

/// Word-pronunciation seam: every "tap to hear" path goes through it, so no view knows
/// how a word is played. `AudioPronouncer` (below) is the real one — bundled `say -v
/// Kyoko` clips with live `AVSpeechSynthesizer` as the fallback; `SilentPronouncer` is
/// the environment default, so previews and tests make no sound.
protocol Pronouncer {
    func speak(_ vocab: Vocab)
    func speak(kana: K)
    func stop()
}

/// No-op — used in previews/tests where audio isn't wanted.
struct SilentPronouncer: Pronouncer {
    func speak(_ vocab: Vocab) {}
    func speak(kana: K) {}
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

    /// A player primed for the word's bundled clip, or nil when it has none (2 of the
    /// 2089 words) — the caller then falls back to `utterance(_:)`. Callers that need
    /// completion callbacks set `delegate` on the result themselves.
    static func clipPlayer(for vocab: Vocab) -> AVAudioPlayer? {
        guard let url = VocabStore.audioURL(for: vocab),
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

    func speak(_ vocab: Vocab) {
        stop()
        PlaybackSession.activate()
        if let p = Speech.clipPlayer(for: vocab) {
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
