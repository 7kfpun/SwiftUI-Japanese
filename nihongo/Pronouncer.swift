import SwiftUI
import AVFoundation

/// Word-pronunciation seam. Audio is deferred (v1), so the default implementation
/// does nothing. Every "tap to hear" path calls this, so audio can be added later
/// (planned: macOS `say -v Kyoko` pre-generated clips, or live `AVSpeechSynthesizer`)
/// without touching any view.
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
    static func utterance(_ text: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: cleanWord(text))
        u.voice = AVSpeechSynthesisVoice(language: locale)
            ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(languageCode) }
        u.rate = 0.4
        return u
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
/// `AVSpeechSynthesizer` for the 2 clip-less words and for bare kana tiles.
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
            Track.audioMissing(vocab.id)
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
