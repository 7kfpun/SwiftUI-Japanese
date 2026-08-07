import SwiftUI

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

    /// Forms that can appear as answer options (audio can only be the prompt).
    static let answerForms: [VForm] = [.kana, .kanji, .romaji, .translation]
}

/// Endless practice loop behind the Train mode (the old Quiz + Listening, merged —
/// Listening was always this model with an audio prompt). Untested and unscored
/// beyond the session badge; the Challenge ladder is where results count.
@Observable
final class TrainModel {
    let vocab: [Vocab]
    var from: VForm
    var to: VForm
    private(set) var options: [Vocab] = []
    private(set) var answer: Vocab
    private(set) var picked: Int? = nil
    private(set) var correct = 0
    private(set) var total = 0

    /// Two candidates, one swipe — not four buttons like a challenge. Train sits
    /// between Flashcards and Learn in the study funnel, so it stays fast and
    /// physical: the 50/50 choice is the gentlest form of being asked.
    static let optionCount = 2

    /// Walk the lesson front to back (wrapping) instead of jumping randomly.
    /// Random is the default: a fixed order soon becomes its own memory cue — you
    /// start knowing what comes *next*, not the word. The ordered walk is the right
    /// tool for a first sweep of a fresh lesson. Turning it on mid-run resumes from
    /// the word on screen rather than snapping back to the start.
    var ordered = false {
        didSet {
            guard ordered else { return }
            cursor = vocab.firstIndex { $0.id == answer.id } ?? -1
        }
    }
    private var cursor = -1

    init(vocab: [Vocab], from: VForm = .kana) {
        self.vocab = vocab
        self.from = from
        // Audio/translation prompts pair with the written word; else default to meaning.
        self.to = (from == .translation || from == .audio) ? .kana : .translation
        // Degrade gracefully on empty data (bad regen) instead of crashing at launch.
        self.answer = vocab.first ?? Vocab(lesson: 0, kanji: "", kana: "", romaji: "",
                                           dictionary: nil, useKana: false, translation: "", audio: nil)
        next()
    }

    func next() {
        picked = nil
        guard !vocab.isEmpty else { return }
        if ordered {
            cursor = (cursor + 1) % vocab.count
            answer = vocab[cursor]
        } else {
            answer = vocab.randomElement()!
        }
        rebuildOptions()
    }

    /// The prompt can be any form incl. audio; the answer options can't be audio.
    /// Cycling re-deals the distractor: it was chosen to be distinct under the *old*
    /// form pair, and with only two chips a collision under the new one is fatal.
    func cycleFrom() { from = Self.nextForm(after: from, in: VForm.allCases, avoiding: to); rebuildOptions() }
    func cycleTo()   { to = Self.nextForm(after: to, in: VForm.answerForms, avoiding: from); rebuildOptions() }

    /// Deal `optionCount` candidates around the kept answer. A distractor must differ
    /// on *both* faces: matching the displayed side makes the question unanswerable,
    /// matching the prompt side (homophones, shared glosses like なん/なに) makes it a
    /// second right answer that would be marked wrong.
    private func rebuildOptions() {
        var opts = [answer]
        var guardCount = 0
        while opts.count < min(Self.optionCount, vocab.count) && guardCount < 2000 {
            guardCount += 1
            let c = vocab.randomElement()!
            guard !opts.contains(where: { $0.id == c.id }),
                  to.value(c) != to.value(answer),
                  from.value(c) != from.value(answer) else { continue }
            opts.append(c)
        }
        options = opts.shuffled()
    }

    private static func nextForm(after f: VForm, in forms: [VForm], avoiding other: VForm) -> VForm {
        guard let start = forms.firstIndex(of: f) else { return forms.first { $0 != other } ?? f }
        var n = start
        repeat { n = (n + 1) % forms.count } while forms[n] == other
        return forms[n]
    }

    func isCorrectOption(_ i: Int) -> Bool { options[i].id == answer.id }

    /// Whether auto-playing the answer's pronunciation is safe for a prompt form.
    /// Hearing the word identifies it — fine when the prompt IS the word (kana/kanji/
    /// romaji/audio), but a translation prompt with word options would be given away.
    static func promptAudioSafe(from: VForm) -> Bool { from != .translation }

    func choose(_ i: Int) {
        guard picked == nil else { return }
        picked = i
        total += 1
        if isCorrectOption(i) { correct += 1 }
    }
}

/// Train — Tinder-style practice over a lesson's vocab: one prompt card, two
/// candidates left and right, swipe toward the one that matches. The prompt cycles
/// through every form including audio (the old Listening mode lives in that cycle),
/// and it never ends: this is the Learn side's rehearsal room, not the test.
struct TrainView: View {
    @State private var model: TrainModel
    @Environment(\.pronouncer) private var pronouncer
    @Environment(Store.self) private var store
    @AppStorage(Pref.soundOn) private var soundOn = true
    @AppStorage(Pref.trainOrdered) private var ordered = false
    @State private var drag: CGSize = .zero
    @State private var lastCorrect: Bool? = nil
    private let lessonNumber: Int

    private let threshold: CGFloat = 90

    init(lesson: Lesson, from: VForm = .kana) {
        lessonNumber = lesson.number
        let pool: [Vocab]
        if from == .audio {
            let audible = lesson.entries.filter { $0.audio != nil }
            pool = audible.count >= TrainModel.optionCount ? audible : lesson.entries
        } else {
            pool = lesson.entries
        }
        _model = State(initialValue: TrainModel(vocab: pool, from: from))
    }

    private var leftOption: Vocab? { model.options.first }
    private var rightOption: Vocab? { model.options.count > 1 ? model.options[1] : nil }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                // Which directions people actually rehearse — recognition vs recall vs
                // listening. The mode's whole point is that the pair is switchable, so
                // untracked it's the one thing about Train we'd know nothing about.
                Button(model.from.label) { model.cycleFrom(); autoPlay(); trackForm() }
                Image(systemName: "arrow.right")
                Button(model.to.label) { model.cycleTo(); trackForm() }
            }
            .font(.subheadline).buttonStyle(.bordered)
            .disabled(model.picked != nil)

            // Same switch LearnView offers, persisted separately (Pref.trainOrdered)
            // because the two default opposite ways — Learn ordered, Train random.
            Picker("", selection: $ordered) {
                Text(L.t("Ordered")).tag(true)
                Text(L.t("Random")).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: ordered) {
                model.ordered = ordered
                Track.event("train_order_mode", ["ordered": ordered])
            }

            // Prompt card (draggable) over the static peek stack — the same deck
            // language as Flashcards and the kana swipe quiz.
            ZStack {
                CardStackPeek()
                promptCard
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                optionChip(leftOption, side: 0)
                optionChip(rightOption, side: 1)
            }
        }
        .padding()
        .background(Theme.canvas)
        .overlay { if let lastCorrect { resultBadge(lastCorrect) } }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { ScoreBadge(correct: model.correct, total: model.total) }
            ToolbarItem(placement: .topBarTrailing) { SoundToggle() }
        }
        .onAppear {
            model.ordered = ordered   // apply the persisted preference to this run
            autoPlay()
            Track.screen("train", ["lesson": lessonNumber])
            if !store.isPremium { Ads.preloadInterstitial() }
        }
        // A popup ad on the way out — non-premium only, throttled.
        .onDisappear { if !store.isPremium && model.total > 0 { Ads.showInterstitialIfReady() } }
    }

    private func trackForm() {
        Track.event("train_form", ["from": model.from.label, "to": model.to.label,
                                   "lesson": lessonNumber])
    }

    /// Audio prompts always speak — the clip IS the question. Other prompts respect
    /// the toggle, and a translation prompt never speaks: the chips are the Japanese
    /// words, so pronouncing the answer would read the correct one aloud.
    private func autoPlay() {
        if model.from.isAudio { pronouncer.speak(model.answer) }
        else if soundOn, TrainModel.promptAudioSafe(from: model.from) { pronouncer.speak(model.answer) }
    }

    private var promptCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(cardBorder, lineWidth: 3))
                .shadow(color: Theme.shadow, radius: 8, y: 4)

            if model.from.isAudio {
                VStack(spacing: 12) {
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 64))
                    Text(L.t("Hear it, pick the word"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .foregroundStyle(Theme.accent)
            } else {
                Text(model.from.value(model.answer))
                    .font(Theme.jp(44))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.35)
                    .padding(20)
            }
        }
        .overlay(alignment: .topTrailing) {
            SwipeStamp(systemImage: "arrow.right", color: Theme.accent, rotation: 8)
                .opacity(model.picked == nil && drag.width > 0 ? min(drag.width / threshold, 1) : 0)
                .padding(16)
        }
        .overlay(alignment: .topLeading) {
            SwipeStamp(systemImage: "arrow.left", color: Theme.accent, rotation: -8)
                .opacity(model.picked == nil && drag.width < 0 ? min(-drag.width / threshold, 1) : 0)
                .padding(16)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.compact.left")
                Text(L.t("Swipe"))
                Image(systemName: "chevron.compact.right")
            }
            .font(.caption).foregroundStyle(.tertiary).padding(.bottom, 8)
        }
        .offset(x: drag.width, y: drag.height / 8)
        .rotationEffect(.degrees(Double(drag.width / 22)))
        .contentShape(Rectangle())
        .onTapGesture { pronouncer.speak(model.answer) }
        .gesture(
            DragGesture()
                .onChanged { if model.picked == nil { drag = $0.translation } }
                .onEnded { value in
                    if value.translation.width > threshold { decide(1) }
                    else if value.translation.width < -threshold { decide(0) }
                    else { withAnimation(.spring) { drag = .zero } }
                }
        )
    }

    /// One of the two candidates.
    ///
    /// The word is the content and gets the weight; the arrow is only an instruction,
    /// so it shrinks to a chevron and moves to the chip's *outer* edge — pointing the
    /// way you'd swipe, which the old centred arrow said less clearly while competing
    /// with the text for attention. Once answered the chevron gives way to a
    /// check/cross, so the verdict isn't carried by colour alone.
    private func optionChip(_ opt: Vocab?, side: Int) -> some View {
        let show = model.picked != nil
        let isAnswer = opt?.id == model.answer.id
        let isPicked = model.picked == side
        let color: Color = show
            ? (isAnswer ? Theme.correct : (isPicked ? Theme.wrong : Theme.line))
            : Theme.accent

        return HStack(spacing: 6) {
            if side == 0 { marker(show: show, isAnswer: isAnswer, isPicked: isPicked, side: side) }
            Text(opt.map { model.to.value($0) } ?? "")
                .font(.title3.weight(.semibold))
                .foregroundStyle(show ? color : .primary)   // the word reads as text, not as a link
                .minimumScaleFactor(0.4)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if side == 1 { marker(show: show, isAnswer: isAnswer, isPicked: isPicked, side: side) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 96)   // min, not fixed: long glosses need room
        .choiceChip(color)
    }

    /// Direction chevron before answering, verdict icon after.
    @ViewBuilder
    private func marker(show: Bool, isAnswer: Bool, isPicked: Bool, side: Int) -> some View {
        Group {
            if show {
                if isAnswer { Image(systemName: "checkmark.circle.fill") }
                else if isPicked { Image(systemName: "xmark.circle.fill") }
                else { Image(systemName: "circle").opacity(0.25) }
            } else {
                Image(systemName: side == 0 ? "chevron.left" : "chevron.right")
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .frame(width: 18)
    }

    private func resultBadge(_ ok: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 72))
            Text(ok ? L.t("Correct!") : L.t("Wrong")).font(.title.bold())
        }
        .foregroundStyle(ok ? Theme.correct : Theme.wrong)
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .transition(.scale.combined(with: .opacity))
        .allowsHitTesting(false)
    }

    private var cardBorder: Color {
        if let lastCorrect { return lastCorrect ? Theme.correct : Theme.wrong }
        return Theme.line
    }

    private func decide(_ side: Int) {
        guard model.picked == nil, model.options.count > side else { return }
        model.choose(side)
        Track.event("train_answer", ["correct": model.isCorrectOption(side), "lesson": lessonNumber])
        withAnimation(.spring(duration: 0.2)) { lastCorrect = model.isCorrectOption(side) }
        withAnimation(.easeOut(duration: 0.25)) { drag.width = side == 1 ? 700 : -700 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            model.next()
            withAnimation(.spring) {
                lastCorrect = nil
                drag = .zero
            }
            autoPlay()   // explicit: every new card speaks (answer may repeat, so no onChange)
        }
    }
}
