import SwiftUI
import SwiftData
import AVFoundation

/// How much of each word "Play all" reads out.
enum ReadMode: String {
    /// The Japanese only — what this feature has always done, and free for everyone.
    case japanese
    /// Japanese, then the meaning in the learner's own language. Premium.
    case withMeaning
    /// Japanese, the meaning, then the word's **example sentence** — the recorded one
    /// where it exists. Premium, and the longest of the three: a lesson takes roughly
    /// three times as long as Japanese-only, which is the point. This is the mode for
    /// listening with your hands full.
    case withExample

    /// Whether this mode reads anything beyond the word itself. The gate is on *that*,
    /// not on the specific mode — a fourth mode reading something else would still be
    /// paid, and `Gating` shouldn't need editing to know it.
    var readsBeyondTheWord: Bool { self != .japanese }
}

/// Plays a whole lesson end-to-end (the old "Read All" mode), advancing on each
/// clip's completion. Bundled Kyoko clip first, TTS fallback when a clip is absent.
///
/// Playback loops by default: the list is meant to run in the background while someone
/// washes up, and stopping after one pass turned that into a two-minute session. The one
/// caller that must *not* loop is the locked meanings preview — see `loops`.
@MainActor
@Observable
final class LessonPlayer: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var mode: ReadMode = .japanese

    /// Which pass through the list is playing: 1 on the first, 2 after the first wrap.
    /// Reset by `start`, so a fresh tap counts from one again.
    private(set) var lap = 1

    /// Which half of the current word is playing. `withMeaning` plays two utterances per
    /// entry, so "did the audio finish" is no longer the same question as "is this word
    /// done" — without this the meaning would be skipped and the list would race ahead.
    private enum Part { case japanese, meaning, example, exampleMeaning }
    private var part: Part = .japanese

    /// Paused rather than stopped: the queue, the index and the lap all stand, and
    /// `resume()` picks the current word up from its start. Distinct from `stop()`,
    /// which clears the run — a listener who pauses has not finished.
    private(set) var isPaused = false

    /// Called when the list runs out on its own. **Not** called by `stop()`: a listener
    /// who taps stop hasn't reached the end, and the meaning preview hangs a paywall off
    /// this — putting one on screen because someone chose to stop would be the same
    /// interruption the whole-lesson rule exists to avoid.
    ///
    /// A looping player never reaches an end, so this only ever fires for `loops == false`.
    var onFinished: (() -> Void)?

    /// Called on each wrap back to the first word, with the lap now starting (2, 3, …).
    /// The player doesn't know which lesson it is holding, so the analytics event is the
    /// caller's to send — the same split as `onFinished`.
    var onLap: ((Int) -> Void)?

    /// Playback speed multiplier (design 3b). Applies to the clip being started and,
    /// when changed mid-word, to the one already playing; the TTS fallback scales its
    /// utterance rate by the same factor.
    var rate: Double = 1.0 {
        didSet { player?.rate = Float(rate) }
    }

    /// Whether the end of the list wraps back to the start instead of stopping.
    ///
    /// `Gating.loopsForever` decides it, and since 2026-08 that means **subscribers
    /// only** — a free listener hears the lesson through once and the player stops. It
    /// must stay false for the un-subscribed meanings preview in particular: that
    /// paywall hangs off `onFinished`, which a looping player never reaches.
    private var loops = true

    private var entries: [Vocab] = []
    private var meaningLocale = Speech.meaningLocale(VocabStore.defaultLanguage)
    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()

    /// Pauses. Long enough to say the word back before the next one starts — that gap is
    /// the practice, not dead air. The meaning follows its Japanese more closely than the
    /// next word follows the meaning, so the ear can group the pair.
    static let betweenWords: TimeInterval = 1.2
    static let beforeMeaning: TimeInterval = 0.65

    /// The word being read — the player owns the (possibly filtered, possibly
    /// truncated) list it was handed, so the view can't re-derive it.
    var currentWord: Vocab? { currentIndex.flatMap { $0 < entries.count ? entries[$0] : nil } }
    var count: Int { entries.count }

    /// `AVSpeechUtterance.rate` is not a multiplier, so scale the house rate and clamp
    /// to the synthesizer's own bounds.
    private func scaled(_ u: AVSpeechUtterance) -> AVSpeechUtterance {
        u.rate = min(max(u.rate * Float(rate), AVSpeechUtteranceMinimumSpeechRate),
                     AVSpeechUtteranceMaximumSpeechRate)
        return u
    }

    override init() { super.init(); synth.delegate = self }

    /// Tapping the mode that is already playing stops it; any other tap (a different
    /// mode, or from stopped) starts fresh. The read-along segments call this directly,
    /// so the same-mode branch is live — a lit segment's second tap must mean "stop",
    /// never "start over from word 1".
    func toggle(_ list: [Vocab], mode: ReadMode, language: String, loops: Bool = true) {
        let wasPlayingSameMode = isPlaying && self.mode == mode
        if isPlaying { stop() }
        guard !wasPlayingSameMode else { return }
        start(list, mode: mode, language: language, loops: loops)
    }

    private func start(_ list: [Vocab], mode: ReadMode, language: String, loops: Bool) {
        entries = list
        self.mode = mode
        self.loops = loops
        lap = 1
        meaningLocale = Speech.meaningLocale(language)
        PlaybackSession.activate()
        isPlaying = true
        play(0)
    }

    /// Jump straight to a word — the playlist's whole point. Restarts the run's clock,
    /// since elapsed time against a total means nothing once you've skipped ahead.
    func play(word i: Int) {
        guard isPlaying, entries.indices.contains(i) else { return }
        play(i)
    }

    func stop() {
        isPlaying = false
        isPaused = false
        currentIndex = nil
        part = .japanese
        player?.delegate = nil; player?.stop(); player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    /// What playback does once word `i` of a `count`-word list has been read.
    ///
    /// Pure and `nonisolated` so the wrap can be tested without audio, a view or a main
    /// actor — the sequencing is the part that has to be right, and everything around it
    /// needs a running screen to exercise.
    enum Step: Equatable {
        /// Read this word next.
        case next(Int)
        /// The list ran out and playback loops: start over at word 0, one lap further on.
        case wrap
        /// The list ran out and playback doesn't loop: this is the end.
        case end
    }

    nonisolated static func step(after i: Int, count: Int, loops: Bool) -> Step {
        if i + 1 < count { return .next(i + 1) }
        // `count > 0` so an empty list can't wrap onto itself forever, silently, with
        // nothing to play and no way for the user to tell it apart from a hang.
        return loops && count > 0 ? .wrap : .end
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
            p.enableRate = true
            p.rate = Float(rate)
            player = p; p.delegate = self; p.play()
        } else {
            if Course.current.hasBundledAudio { Track.audioMissing(v.id) }
            synth.speak(scaled(Speech.utterance(v.kana)))
        }
    }

    /// The Japanese half finished. Either speak the meaning, or move on.
    private func finishedJapanese(at i: Int) {
        guard mode.readsBeyondTheWord else { return advance(from: i, after: Self.betweenWords) }
        let meaning = entries[i].translation
        // A word with no meaning in this language behaves like the Japanese-only mode
        // rather than pausing for silence.
        guard !meaning.isEmpty else { return finishedMeaning(at: i) }
        part = .meaning
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.beforeMeaning) { [weak self] in
            guard let self, self.isPlaying, !self.isPaused, self.currentIndex == i, self.part == .meaning else { return }
            self.synth.speak(self.scaled(Speech.utterance(meaning, locale: self.meaningLocale)))
        }
    }

    /// After the meaning: the sentence, in the `withExample` mode only.
    ///
    /// Plays the *recorded* sentence where the word has one and speaks it otherwise —
    /// the same clip-or-synthesise rule as the word itself, so a course shipping no
    /// sentence recordings still gets the mode rather than silence.
    private func finishedMeaning(at i: Int) {
        guard mode == .withExample, i < entries.count,
              let spoken = entries[i].example?.spoken else {
            return advance(from: i, after: Self.betweenWords)
        }
        part = .example
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.beforeMeaning) { [weak self] in
            guard let self, self.isPlaying, !self.isPaused, self.currentIndex == i, self.part == .example else { return }
            if let url = VocabStore.exampleAudioURL(for: self.entries[i]),
               let p = try? AVAudioPlayer(contentsOf: url) {
                p.enableRate = true
                p.rate = Float(self.rate)
                p.delegate = self
                self.player = p
                p.play()
            } else {
                self.synth.speak(self.scaled(Speech.utterance(spoken)))
            }
        }
    }

    /// Hold the run where it is. The current word is cut off rather than faded — this is
    /// a pause button, and a listener who presses it wants the voice to stop now.
    ///
    /// Every deferred step (`advance` and the three per-leg `asyncAfter`s) also guards
    /// on `!isPaused`. Without that, a pause landing in one of the gaps *between*
    /// sounds — a large fraction of any run — let the pending block fire anyway:
    /// playback carried on under a toolbar showing "play", and `resume()` then had
    /// nothing to resume. The block simply dies; `resume()` restarts the current word,
    /// which its own doc already promises.
    func pause() {
        guard isPlaying, !isPaused else { return }
        isPaused = true
        player?.pause()
        if synth.isSpeaking { synth.pauseSpeaking(at: .immediate) }
    }

    /// Pick the current word up from its start.
    ///
    /// Restarting the word rather than resuming mid-syllable: `AVAudioPlayer` could
    /// resume exactly, but the synthesiser's pause lands wherever it lands, and half a
    /// word is worse than the word again — the pauses in this feature are the practice.
    func resume() {
        guard isPlaying, isPaused else { return }
        isPaused = false
        if synth.isPaused { synth.continueSpeaking(); return }
        if let p = player, p.currentTime > 0 { p.play(); return }
        if let i = currentIndex { play(i) }
    }

    private func advance(from i: Int, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isPlaying, !self.isPaused, self.currentIndex == i else { return }
            switch Self.step(after: i, count: self.entries.count, loops: self.loops) {
            case .next(let n):
                self.play(n)
            case .wrap:
                self.lap += 1
                self.onLap?(self.lap)
                // After the callback: it can't stop playback today, but if one ever does
                // (a cap, a paywall) the guard is what keeps this from playing anyway.
                if self.isPlaying { self.play(0) }
            case .end:
                // `play` past the end is still how the finish runs, so `onFinished` and
                // its paywall keep firing from exactly one place.
                self.play(i + 1)
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard let i = self.currentIndex else { return }
            // Which leg just ended decides what follows — the word's clip and the
            // sentence's clip both arrive here.
            if self.part == .example { self.finishedExample(at: i) }
            else { self.finishedJapanese(at: i) }
        }
    }

    /// After the sentence: what the sentence *means*.
    ///
    /// Without this the mode read a Japanese sentence at a learner who had just been
    /// told the word — the one part of the sequence they could not work out for
    /// themselves was the part left silent. A sentence is only listening practice if you
    /// know what it says.
    private func finishedExample(at i: Int) {
        guard i < entries.count, let meaning = entries[i].exampleTranslation,
              !meaning.isEmpty else {
            return advance(from: i, after: Self.betweenWords)
        }
        part = .exampleMeaning
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.beforeMeaning) { [weak self] in
            guard let self, self.isPlaying, !self.isPaused, self.currentIndex == i,
                  self.part == .exampleMeaning else { return }
            self.synth.speak(self.scaled(Speech.utterance(meaning, locale: self.meaningLocale)))
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            guard let i = self.currentIndex else { return }
            switch self.part {
            case .japanese:       self.finishedJapanese(at: i)
            case .meaning:        self.finishedMeaning(at: i)
            case .example:        self.finishedExample(at: i)
            case .exampleMeaning: self.advance(from: i, after: Self.betweenWords)
            }
        }
    }
}

struct VocabListView: View {
    /// Off by default (design 3a): every example expanded left four words per screen,
    /// which is the opposite of a scannable list. The sentences are one tap away on the
    /// toolbar toggle, and the choice persists once made.
    @AppStorage(Pref.examplesShown) private var examplesShown = false

    /// The preference **and** the dataset agreeing. The stored flag is per-app, so it can
    /// only ever be true here if this app's own switch set it — but the switch is hidden
    /// when the course has no sentences, and reading the preference alone would leave a
    /// caption promising "examples shown" above rows that show none.
    private var showsExamples: Bool { examplesShown && VocabStore.hasExamples }
    let lesson: Lesson
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.deviceDefaultLanguage
    @Environment(PracticeProgress.self) private var practice
    @Environment(\.modelContext) private var context

    /// The three cuts of the list (design 3a). "Not memorized" reads the same
    /// per-word stages Practice writes, so the list can answer "what do I still owe
    /// this lesson" without opening a mode; "Bookmarked" is the user's own shelf.
    private enum Cut: String, CaseIterable {
        case all, notMemorized, bookmarked

        var title: String {
            switch self {
            case .all:          return L.t("All")
            case .notMemorized: return L.t("Not memorized")
            case .bookmarked:   return L.t("Bookmarked")
            }
        }
    }

    @State private var cut: Cut = .all
    /// The entry a swipe asked to report, and the sheet's presentation state in one —
    /// non-nil *is* "the sheet is up", so the two can't disagree.
    @State private var reporting: Feedback.Item?
    /// Bookmarked words and their **tier**, re-read on appear so stars changed elsewhere
    /// update the chip and the marks. A tier rather than a `Set` because the swipe
    /// cycles ★1 → ★2 → ★3 → none, and the row has to show which one it is on.
    @State private var bookmarked: [String: Int] = [:]

    // Re-resolve by lesson number so meanings update immediately when the language changes.
    private var entries: [Vocab] { VocabStore.lesson(lesson.number, language).entries }

    /// The rows the current cut shows — and what Read along reads: playing the words
    /// you filtered to (your bookmarks, your gaps) is the point of filtering.
    private var shown: [Vocab] {
        switch cut {
        case .all:          return entries
        case .notMemorized: return entries.filter { practice.stage(of: $0.id) != .memorized }
        case .bookmarked:   return entries.filter { bookmarked[$0.id] != nil }
        }
    }

    private func count(_ c: Cut) -> Int {
        switch c {
        case .all:          return entries.count
        case .notMemorized: return entries.count { practice.stage(of: $0.id) != .memorized }
        case .bookmarked:   return entries.count { bookmarked[$0.id] != nil }
        }
    }

    var body: some View {
        List {
            if shown.isEmpty {
                // A cut that filters everything out has to say *why* — an empty list
                // under a chip reading "Bookmarked 0" looks like a screen that failed
                // to load rather than a shelf nobody has put anything on yet.
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 8)
            }
            ForEach(shown, id: \.id) { v in
                VocabRow(vocab: v, showExample: showsExamples,
                         stage: practice.stage(of: v.id),
                         savedTier: bookmarked[v.id],
                         onTierChange: { _ in reloadBookmarks() })
                    // Swiping reports a mistake in the entry — a wrong reading, a wrong
                    // meaning, a clip that says something else.
                    //
                    // Bookmarking moved back to the star under the speaker, where one tap
                    // cycles the tiers; a swipe could only ever have done one step of that
                    // cycle per gesture, because the drawer closes on tap. That freed the
                    // swipe for the thing this screen had no room for: the vocab list is
                    // where a learner *reads* the data closely enough to notice it is
                    // wrong, and until now the flag lived only on quiz screens.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            // Logged on the swipe, not on the send: this is the one
                            // report path that isn't a toolbar flag, and how often the
                            // gesture is *found* is a separate question from how often
                            // it turns into a submitted report.
                            Track.event("report_swipe", ["lesson": v.lesson])
                            reporting = Feedback.Item(lesson: v.lesson, romaji: v.romaji)
                        } label: {
                            Label(L.t("Report"), systemImage: "flag")
                        }
                        .tint(Color.streak)
                    }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { cutChips }
        .sheet(item: $reporting) { item in
            FeedbackView(source: .card, item: item)
        }
        .navigationTitle(L.t("Vocab List"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Track.screen("vocab_list", ["lesson": lesson.number])
            ModeVisits.mark(lesson: lesson.number, mode: "vocab_list")
            reloadBookmarks()
        }
        .toolbar {
            // Which lesson, under the screen's own name — the title used to *be* the
            // lesson number, which said nothing about what the screen is.
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(L.t("Vocab List")).font(Theme.title(.headline))
                    Text("\(L.t("Lesson %@", "\(lesson.number)")) · \(L.t("%@ words", "\(entries.count)"))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            // One control, not a menu of modes: choosing Japanese-only vs
            // Japanese-plus-meaning now happens on the player screen, where the
            // difference can be heard and switched mid-run (design 3b). Filled and
            // accented because it is the screen's one real action — the examples
            // toggle moved down to the chip row, where it belongs beside the cuts.
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ReadAlongView(lesson: lesson, words: shown)
                } label: {
                    // A bare glyph. iOS 26 already draws every toolbar item in its own
                    // circular chrome, so a filled circle here sat *inside* that one —
                    // a teal disc in a white disc, which is why it read as a button
                    // wearing a second button. The back chevron and `SoundToggle` are
                    // plain glyphs for the same reason; the tint is what marks this as
                    // the screen's action.
                    Image(systemName: "play.fill")
                        .foregroundStyle(Theme.accent)
                }
                .disabled(shown.isEmpty)
                .accessibilityLabel(L.t("Read along"))
            }
        }
    }

    /// The cut chips, and the examples switch beside them (design "Vocab List").
    ///
    /// Counts on every chip, so a cut that would show an empty list says so before it is
    /// tapped. Selection is an accent border, per the house rule; a horizontal scroll
    /// because four labels in nineteen languages will not always fit one row.
    private var cutChips: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Cut.allCases, id: \.self) { c in
                        chip(c.title,
                             count: count(c),
                             icon: c == .bookmarked ? "star.fill" : nil,
                             selected: cut == c) {
                            withAnimation(.easeOut(duration: 0.15)) { cut = c }
                            Track.event("vocab_cut", ["cut": c.rawValue, "lesson": lesson.number])
                        }
                    }

                    // The examples switch rides at the end of the same row: it filters
                    // what each row *shows* exactly as the chips filter which rows
                    // appear, so it belongs beside them rather than behind a toolbar
                    // glyph. The divider marks it as the different kind of control.
                    // Both only where the dataset has sentences to show — JLPT has none,
                    // and a switch that reveals nothing reads as a broken switch.
                    if VocabStore.hasExamples {
                        Divider().frame(height: 20).padding(.horizontal, 2)

                        examplesSwitch
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // The swipe is invisible until tried; one quiet line teaches it once.
            Text(showsExamples ? L.t("Tap the star to save · examples shown")
                               : L.t("Tap the star to save · swipe to report a mistake"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
        }
        .background(Theme.canvas)
    }

    /// One cut chip: optional leading glyph, label, count.
    ///
    /// **A solid fill, not an accent border.** `Theme`'s selection rule (border, never
    /// fill) exists to stop accent fills competing with answer feedback — this fill is
    /// `Color.primary`, carries no verdict, and is what the design specifies. A row of
    /// four capsules distinguished only by border weight is genuinely hard to read at a
    /// glance, which is the case the rule was not written for.
    private func chip(_ title: String, count: Int?, icon: String?, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                if let count {
                    Text("\(count)")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .opacity(selected ? 0.7 : 1)
                        .foregroundStyle(selected ? Color(.systemBackground) : .secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(selected ? Color(.systemBackground) : .primary)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(selected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Theme.surface),
                    in: Capsule())
        .overlay(Capsule().stroke(selected ? Color.clear : Theme.line, lineWidth: 1))
    }

    /// Examples is not a cut, so it does not look like one: a label and a real switch,
    /// in the same capsule shell. The chips answer "which words"; this answers "how much
    /// of each word" — a different question, and a toggle is what says so.
    private var examplesSwitch: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { examplesShown.toggle() }
            Track.event("examples_shown", ["on": examplesShown])
        } label: {
            HStack(spacing: 8) {
                Text(L.t("Examples")).font(.subheadline)
                // A drawn switch at its real size, not a `Toggle` scaled down.
                //
                // A system toggle is ~50×31 and would not fit a 34pt chip, so it was
                // wearing a `scaleEffect(0.78)` — which left it ~40pt tall inside a 34pt
                // capsule, filling it edge to edge and reading as a pill crammed into a
                // pill (and softly blurred, since a scaled UIKit control resamples). At
                // 36×20 it sits *inside* the chip the way the design draws it, and it is
                // sharp because nothing is scaled.
                Capsule()
                    .fill(examplesShown ? Theme.accent : Theme.line)
                    .frame(width: 36, height: 20)
                    .overlay(alignment: examplesShown ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .padding(2)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                    }
            }
            .padding(.leading, 13)
            .padding(.trailing, 5)
            .frame(height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.t("Show examples"))
        .accessibilityAddTraits(examplesShown ? [.isButton, .isSelected] : .isButton)
    }

    /// Why this cut is empty — different reasons want different sentences.
    private var emptyText: String {
        switch cut {
        case .bookmarked:   return L.t("Nothing saved yet. Swipe any word left to shelve it.")
        case .notMemorized: return L.t("Every word in this lesson is memorized.")
        case .all:          return L.t("No words here.")
        }
    }

    private func reloadBookmarks() {
        bookmarked = Dictionary(
            Bookmark.all(context: context)
                .filter { $0.lesson == lesson.number }
                .map { ($0.word, Bookmark.clamp($0.stars)) },
            // `Bookmark.all` already collapses merge duplicates by word, so this only
            // guards the type — but keeping the higher tier is the right tie-break if
            // that ever changes.
            uniquingKeysWith: max)
    }

}
