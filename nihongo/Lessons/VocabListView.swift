import SwiftUI
import AVFoundation

/// How much of each word "Play all" reads out.
enum ReadMode: String {
    /// The Japanese only — what this feature has always done, and free for everyone.
    case japanese
    /// Japanese, then the meaning in the learner's own language. Premium, under the same
    /// whole-lesson rule as everything else: lessons 1…`freeLessonLimit` are free in full.
    case withMeaning
}

/// Plays a whole lesson end-to-end (the old "Read All" mode), advancing on each
/// clip's completion. Bundled Kyoko clip first, TTS fallback when a clip is absent.
@MainActor
@Observable
final class LessonPlayer: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var mode: ReadMode = .japanese

    /// Which half of the current word is playing. `withMeaning` plays two utterances per
    /// entry, so "did the audio finish" is no longer the same question as "is this word
    /// done" — without this the meaning would be skipped and the list would race ahead.
    private enum Part { case japanese, meaning }
    private var part: Part = .japanese

    private var entries: [Vocab] = []
    private var meaningLocale = Speech.meaningLocale(VocabStore.defaultLanguage)
    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()

    /// Pauses. Long enough to say the word back before the next one starts — that gap is
    /// the practice, not dead air. The meaning follows its Japanese more closely than the
    /// next word follows the meaning, so the ear can group the pair.
    private static let betweenWords: TimeInterval = 0.9
    private static let beforeMeaning: TimeInterval = 0.45

    override init() { super.init(); synth.delegate = self }

    /// The toolbar collapses to a single stop button while playing, so in practice this
    /// is only ever called from a stopped state. The restart branch is kept because the
    /// alternative — silently doing nothing — is the worse failure if that ever changes.
    func toggle(_ list: [Vocab], mode: ReadMode, language: String) {
        let wasPlayingSameMode = isPlaying && self.mode == mode
        if isPlaying { stop() }
        guard !wasPlayingSameMode else { return }
        start(list, mode: mode, language: language)
    }

    private func start(_ list: [Vocab], mode: ReadMode, language: String) {
        entries = list
        self.mode = mode
        meaningLocale = Speech.meaningLocale(language)
        PlaybackSession.activate()
        isPlaying = true
        play(0)
    }

    func stop() {
        isPlaying = false
        currentIndex = nil
        part = .japanese
        player?.delegate = nil; player?.stop(); player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    private func play(_ i: Int) {
        guard isPlaying, i < entries.count else { stop(); return }
        currentIndex = i
        part = .japanese
        let v = entries[i]
        // Same clip-or-speak policy as `AudioPronouncer`, via `Speech` — this player
        // only adds the delegate it needs to know when to advance.
        if let p = Speech.clipPlayer(for: v) {
            player = p; p.delegate = self; p.play()
        } else {
            if Course.current.hasBundledAudio { Track.audioMissing(v.id) }
            synth.speak(Speech.utterance(v.kana))
        }
    }

    /// The Japanese half finished. Either speak the meaning, or move on.
    private func finishedJapanese(at i: Int) {
        guard mode == .withMeaning else { return advance(from: i, after: Self.betweenWords) }
        let meaning = entries[i].translation
        // A word with no meaning in this language behaves like the Japanese-only mode
        // rather than pausing for silence.
        guard !meaning.isEmpty else { return advance(from: i, after: Self.betweenWords) }
        part = .meaning
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.beforeMeaning) { [weak self] in
            guard let self, self.isPlaying, self.currentIndex == i, self.part == .meaning else { return }
            self.synth.speak(Speech.utterance(meaning, locale: self.meaningLocale))
        }
    }

    private func advance(from i: Int, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isPlaying, self.currentIndex == i else { return }
            self.play(i + 1)
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if let i = self.currentIndex { self.finishedJapanese(at: i) } }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            guard let i = self.currentIndex else { return }
            switch self.part {
            case .japanese: self.finishedJapanese(at: i)
            case .meaning:  self.advance(from: i, after: Self.betweenWords)
            }
        }
    }
}

struct VocabListView: View {
    let lesson: Lesson
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.deviceDefaultLanguage
    @State private var player = LessonPlayer()
    @State private var showPaywall = false
    @Environment(Store.self) private var store

    // Re-resolve by lesson number so meanings update immediately when the language changes.
    private var entries: [Vocab] { VocabStore.lesson(lesson.number, language).entries }

    /// Reading the meanings aloud is premium — under the *same* whole-lesson rule as every
    /// other paid mode, not a rule of its own. Lessons 1…3 read both halves for free, so
    /// the feature can be heard before it is bought rather than only described.
    ///
    /// The Vocab List itself stays free at every lesson. This gates one button on it.
    private var meaningLocked: Bool {
        Gating.isLocked(lesson: lesson.number, isPremium: store.isPremium)
    }

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
                // A menu rather than two buttons: the modes are alternatives, not
                // independent actions, and while something is playing the only thing
                // anyone wants is one tap that stops it.
                if player.isPlaying {
                    Button { player.stop() } label: {
                        Label(L.t("Play all"), systemImage: "stop.fill")
                    }
                } else {
                    Menu {
                        Button { play(.japanese) } label: {
                            Label(L.t("Play all"), systemImage: "speaker.wave.2")
                        }
                        Button { play(.withMeaning) } label: {
                            Label {
                                Text(L.t("Play with meanings"))
                            } icon: {
                                Image(systemName: meaningLocked ? "lock.fill" : "text.bubble")
                            }
                        }
                    } label: {
                        Label(L.t("Play all"), systemImage: "play.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(source: "read_all_meanings") }
        .onDisappear { player.stop() }
    }

    private func play(_ mode: ReadMode) {
        if mode == .withMeaning && meaningLocked {
            showPaywall = true
            Track.event("locked_read_all", ["lesson": lesson.number])
            return
        }
        player.toggle(entries, mode: mode, language: language)
        if player.isPlaying {
            Track.event("read_all", ["lesson": lesson.number, "mode": mode.rawValue])
        }
    }
}
