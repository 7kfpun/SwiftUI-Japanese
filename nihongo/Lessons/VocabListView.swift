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

    override init() { super.init(); synth.delegate = self }

    func toggle(_ list: [Vocab]) { isPlaying ? stop() : start(list) }

    private func start(_ list: [Vocab]) {
        entries = list
        PlaybackSession.activate()
        isPlaying = true
        play(0)
    }

    func stop() {
        isPlaying = false
        currentIndex = nil
        player?.delegate = nil; player?.stop(); player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    private func play(_ i: Int) {
        guard isPlaying, i < entries.count else { stop(); return }
        currentIndex = i
        let v = entries[i]
        // Same clip-or-speak policy as `AudioPronouncer`, via `Speech` — this player
        // only adds the delegate it needs to know when to advance.
        if let p = Speech.clipPlayer(for: v) {
            player = p; p.delegate = self; p.play()
        } else {
            Track.audioMissing(v.id)
            synth.speak(Speech.utterance(v.kana))
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
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.defaultLanguage
    @State private var player = LessonPlayer()

    // Re-resolve by lesson number so meanings update immediately when the language changes.
    private var entries: [Vocab] { VocabStore.lesson(lesson.number, language).entries }

    var body: some View {
        ScrollViewReader { proxy in
            List(Array(entries.enumerated()), id: \.element.id) { i, v in
                VocabRow(vocab: v)
                    .listRowBackground(player.currentIndex == i ? Theme.accent.opacity(0.12) : nil)
            }
            .onChange(of: player.currentIndex) { _, new in
                if let new {
                    withAnimation { proxy.scrollTo(entries[new].id, anchor: .center) }
                }
            }
        }
        .navigationTitle(L.t("Lesson %@", "\(lesson.number)"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Track.screen("vocab_list", ["lesson": lesson.number]) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    player.toggle(entries)
                    if player.isPlaying { Track.event("read_all", ["lesson": lesson.number]) }
                } label: {
                    Label(L.t("Play all"),
                          systemImage: player.isPlaying ? "stop.fill" : "play.fill")
                }
            }
        }
        .onDisappear { player.stop() }
    }
}
