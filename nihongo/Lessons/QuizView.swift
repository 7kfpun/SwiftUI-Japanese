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

@Observable
final class QuizModel {
    let vocab: [Vocab]
    var from: VForm
    var to: VForm
    private(set) var options: [Vocab] = []
    private(set) var answer: Vocab
    private(set) var picked: Int? = nil
    private(set) var correct = 0
    private(set) var total = 0

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
        guard let ans = vocab.randomElement() else { return }
        var opts = [ans]
        var guardCount = 0
        while opts.count < min(4, vocab.count) && guardCount < 2000 {
            guardCount += 1
            let c = vocab.randomElement()!
            if !opts.contains(where: { $0.kana == c.kana }) { opts.append(c) }
        }
        answer = ans
        options = opts.shuffled()
    }

    /// The prompt can be any form incl. audio; the answer options can't be audio.
    func cycleFrom() { from = Self.nextForm(after: from, in: VForm.allCases, avoiding: to) }
    func cycleTo()   { to = Self.nextForm(after: to, in: VForm.answerForms, avoiding: from) }

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

struct QuizView: View {
    @State private var model: QuizModel
    @State private var showPaywall = false
    @Environment(\.pronouncer) private var pronouncer
    @Environment(Store.self) private var store
    @AppStorage(Pref.soundOn) private var soundOn = true
    private let lessonNumber: Int
    private let screenName: String

    /// `from: .audio` opens the "Listening" variant — prompt is the clip, pick the word.
    init(lesson: Lesson, from: VForm = .kana) {
        lessonNumber = lesson.number
        screenName = from == .audio ? "listening" : "quiz"
        let pool: [Vocab]
        if from == .audio {
            let audible = lesson.entries.filter { $0.audio != nil }
            pool = audible.count >= 4 ? audible : lesson.entries
        } else {
            pool = lesson.entries
        }
        _model = State(initialValue: QuizModel(vocab: pool, from: from))
    }

    /// Locked lessons give `freeTrialCards` questions before the paywall.
    private var reachedLimit: Bool {
        Gating.trialLimit(lesson: lessonNumber, isPremium: store.isPremium)
            .map { model.total >= $0 } ?? false
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Button(model.from.label) { model.cycleFrom() }
                Image(systemName: "arrow.right")
                Button(model.to.label) { model.cycleTo() }
            }
            .font(.subheadline).buttonStyle(.bordered)
            .disabled(model.picked != nil)

            prompt

            OptionGrid(count: model.options.count) { i in
                QuizOptionButton(text: model.to.value(model.options[i]),
                                 border: optionBorder(i),
                                 disabled: model.picked != nil || reachedLimit) {
                    model.choose(i)
                    Track.event("\(screenName)_answer", ["correct": model.isCorrectOption(i)])
                }
            }

            if reachedLimit {
                Button { showPaywall = true } label: {
                    Label(L.t("Unlock to continue"), systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button { model.next(); autoPlay() } label: { Text(L.t("Next")).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.picked == nil)
            }
        }
        .padding()
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { ScoreBadge(correct: model.correct, total: model.total) }
            ToolbarItem(placement: .topBarTrailing) { SoundToggle() }
        }
        .onAppear {
            autoPlay()
            Track.screen(screenName, ["lesson": lessonNumber])
            if !store.isPremium { Ads.preloadInterstitial() }
        }
        .onChange(of: model.from) { autoPlay() }
        .onChange(of: model.total) {
            if reachedLimit {
                showPaywall = true
                Track.event("trial_limit", ["mode": screenName, "lesson": lessonNumber])
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        // A popup ad on the way out of the quiz — non-premium only, throttled.
        .onDisappear { if !store.isPremium && model.total > 0 { Ads.showInterstitialIfReady() } }
    }

    /// Listening prompts always speak — the audio IS the question. Text prompts speak
    /// too when sound is on, unless that would reveal the answer (translation prompt).
    private func autoPlay() {
        if model.from.isAudio { pronouncer.speak(model.answer) }
        else if soundOn, QuizModel.promptAudioSafe(from: model.from) { pronouncer.speak(model.answer) }
    }

    /// The prompt: a big speaker for the audio form, otherwise the word text.
    /// Tapping always (re)plays the pronunciation.
    private var prompt: some View {
        Group {
            if model.from.isAudio {
                VStack(spacing: 12) {
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 64))
                    Text(L.t("Hear it, pick the word"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .foregroundStyle(Theme.accent)
            } else {
                Text(model.from.value(model.answer))
                    .font(Theme.jp(38))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { pronouncer.speak(model.answer) }
    }

    private func optionBorder(_ i: Int) -> Color {
        guard model.picked != nil else { return Color(.separator) }
        if model.isCorrectOption(i) { return Theme.correct }
        if model.picked == i { return Theme.wrong }
        return Color(.separator)
    }
}
