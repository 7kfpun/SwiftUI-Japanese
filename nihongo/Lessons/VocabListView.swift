import SwiftUI
import AVFoundation

/// Plays a whole lesson end-to-end (the old "Read All" mode), advancing on each
/// clip's completion. Bundled Kyoko clip first, TTS fallback for the clip-less words.
@MainActor
@Observable
final class LessonPlayer: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false

    private var entries: [Vocab] = []
    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    private var sessionActivated = false

    override init() { super.init(); synth.delegate = self }

    func toggle(_ list: [Vocab]) { isPlaying ? stop() : start(list) }

    private func start(_ list: [Vocab]) {
        entries = list
        activateSession()
        isPlaying = true
        play(0)
    }

    func stop() {
        isPlaying = false
        currentIndex = nil
        player?.delegate = nil; player?.stop(); player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    /// Configure the session lazily and mixably, so background music keeps playing.
    private func activateSession() {
        guard !sessionActivated else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
        sessionActivated = true
    }

    private func play(_ i: Int) {
        guard isPlaying, i < entries.count else { stop(); return }
        currentIndex = i
        let v = entries[i]
        if let url = VocabStore.audioURL(for: v), let p = try? AVAudioPlayer(contentsOf: url) {
            player = p; p.delegate = self; p.volume = 1; p.prepareToPlay(); p.play()
        } else {
            let u = AVSpeechUtterance(string: cleanWord(v.kana))
            u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
                ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("ja") }
            u.rate = 0.4
            synth.speak(u)
        }
    }

    private func advance(from i: Int) {
        // A short beat between words, then the next one (unless stopped meanwhile).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.isPlaying, self.currentIndex == i else { return }
            self.play(i + 1)
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if let i = self.currentIndex { self.advance(from: i) } }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in if let i = self.currentIndex { self.advance(from: i) } }
    }
}

struct VocabListView: View {
    let lesson: Lesson
    @State private var player = LessonPlayer()

    var body: some View {
        ScrollViewReader { proxy in
            List(Array(lesson.entries.enumerated()), id: \.element.id) { i, v in
                VocabRow(vocab: v)
                    .listRowBackground(player.currentIndex == i ? Theme.accent.opacity(0.12) : nil)
            }
            .onChange(of: player.currentIndex) { _, new in
                if let new {
                    withAnimation { proxy.scrollTo(lesson.entries[new].id, anchor: .center) }
                }
            }
        }
        .navigationTitle(L.t("Lesson %@", "\(lesson.number)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { player.toggle(lesson.entries) } label: {
                    Label(L.t("Play all"),
                          systemImage: player.isPlaying ? "stop.fill" : "play.fill")
                }
            }
        }
        .onDisappear { player.stop() }
    }
}
