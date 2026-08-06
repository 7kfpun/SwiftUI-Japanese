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

/// Plays the bundled Kyoko clip for a vocab word; falls back to live
/// `AVSpeechSynthesizer` (ja-JP) for the 2 clip-less words and for bare kana tiles.
final class AudioPronouncer: Pronouncer {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    func speak(_ vocab: Vocab) {
        stop()
        PlaybackSession.activate()
        if let url = VocabStore.audioURL(for: vocab),
           let p = try? AVAudioPlayer(contentsOf: url) {
            player = p
            p.volume = 1
            p.prepareToPlay()
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

    private func speakLive(_ text: String) {
        let u = AVSpeechUtterance(string: cleanWord(text))
        // Prefer an installed Japanese voice; falls back to the language default.
        u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
            ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("ja") }
        u.rate = 0.4
        synth.speak(u)
    }
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
