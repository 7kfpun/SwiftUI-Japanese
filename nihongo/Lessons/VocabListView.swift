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

    /// Called when the list runs out on its own. **Not** called by `stop()`: a listener
    /// who taps stop hasn't reached the end, and the meaning preview hangs a paywall off
    /// this — putting one on screen because someone chose to stop would be the same
    /// interruption the whole-lesson rule exists to avoid.
    var onFinished: (() -> Void)?

    private var entries: [Vocab] = []
    private var meaningLocale = Speech.meaningLocale(VocabStore.defaultLanguage)
    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()

    /// Pauses. Long enough to say the word back before the next one starts — that gap is
    /// the practice, not dead air. The meaning follows its Japanese more closely than the
    /// next word follows the meaning, so the ear can group the pair.
    private static let betweenWords: TimeInterval = 1.2
    private static let beforeMeaning: TimeInterval = 0.65

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
        guard isPlaying else { stop(); return }
        guard i < entries.count else {
            // `i > 0` so an empty list can't fire this. Running out having played nothing
            // isn't "finished", and a paywall on an empty lesson would be pure noise.
            let reachedEnd = i > 0
            stop()
            if reachedEnd { onFinished?() }
            return
        }
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

    /// Reading the meanings aloud is premium. On a free lesson it plays the lesson through;
    /// on a locked one it plays `Gating.freeMeaningPreview` words properly and *then* asks.
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
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "read_all_meanings", lesson: lesson.number)
        }
        // `onFinished` closes over this view, which owns the player — clearing it here
        // breaks that cycle, and stops a paywall arriving on a screen already left.
        .onDisappear { player.stop(); player.onFinished = nil }
    }

    private func play(_ mode: ReadMode) {
        // A locked lesson gets a taste, not a closed door. The paywall is triggered by the
        // preview *reaching its end*, never by a timer and never by the tap itself, so a
        // listener who stops early is left alone.
        let limit = Gating.wordsToRead(mode: mode, count: entries.count, isLocked: meaningLocked)
        let list = Array(entries.prefix(limit))
        // "Preview" means literally that the list was cut short, so the paywall can only
        // follow playback the user didn't get all of.
        let isPreview = limit < entries.count

        player.onFinished = isPreview ? {
            Track.event("locked_read_all", ["lesson": lesson.number,
                                            "heard": list.count])
            showPaywall = true
        } : nil

        player.toggle(list, mode: mode, language: language)
        if player.isPlaying {
            Track.event("read_all", ["lesson": lesson.number, "mode": mode.rawValue,
                                     "preview": isPreview])
        }
    }
}
