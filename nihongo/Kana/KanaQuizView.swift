import SwiftUI
import SwiftData

enum KForm: Int, CaseIterable {
    case hiragana = 0, katakana, romaji
    var label: String {
        switch self {
        case .hiragana: return "hiragana"
        case .katakana: return "katakana"
        case .romaji:   return "romaji"
        }
    }
    func value(_ k: K) -> String {
        switch self {
        case .hiragana: return k.hiragana
        case .katakana: return k.katakana
        case .romaji:   return k.romaji
        }
    }
}

@Observable
final class KanaQuizModel {
    let pool: [K]
    let optionCount: Int
    var from: KForm = .hiragana
    var to: KForm = .romaji
    var other: KForm = .katakana
    private(set) var options: [K] = []
    private(set) var answer: K = K("", "", "")
    private(set) var picked: Int? = nil
    private(set) var correct = 0
    private(set) var total = 0

    init(pool: [K], optionCount: Int = 4) {
        self.pool = pool.filter { !$0.isEmpty }
        self.optionCount = optionCount
        next()
    }

    func swapFrom() { swap(&from, &other) }
    func swapTo()   { swap(&to, &other) }

    func next() {
        picked = nil
        guard let ans = pool.randomElement() else { return }
        var opts = [ans]
        var guardCount = 0
        while opts.count < min(optionCount, pool.count) && guardCount < 1000 {
            guardCount += 1
            let c = pool.randomElement()!
            if !opts.contains(where: { $0.romaji == c.romaji }) { opts.append(c) }
        }
        answer = ans
        options = opts.shuffled()
    }

    func isCorrectOption(_ i: Int) -> Bool { options[i].romaji == answer.romaji }

    func choose(_ i: Int, context: ModelContext) {
        guard picked == nil else { return }
        picked = i
        let right = isCorrectOption(i)
        total += 1
        if right { correct += 1 }
        KanaResult.record(romaji: answer.romaji, isCorrect: right, context: context)
    }
}

struct KanaQuizView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.pronouncer) private var pronouncer
    @AppStorage(Pref.soundOn) private var soundOn = true
    @State private var model: KanaQuizModel
    private let listening: Bool

    init(table: KanaTable, listening: Bool = false) {
        self.listening = listening
        _model = State(initialValue: KanaQuizModel(pool: table.rows.flatMap { $0 }))
    }

    /// Kana audio can never reveal the answer — hiragana/katakana/romaji share one
    /// sound. In listening mode the sound IS the question, so it ignores the toggle.
    private func autoPlay() {
        if listening || soundOn { pronouncer.speak(kana: model.answer) }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Direction toggles (in listening mode the prompt side is the audio)
            HStack(spacing: 8) {
                if listening {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent)
                } else {
                    Button(model.from.label) { model.swapFrom() }
                }
                Image(systemName: "arrow.right")
                Button(model.to.label) { model.swapTo() }
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
            .disabled(model.picked != nil)

            // Question prompt: the kana glyph, or a speaker in listening mode.
            Group {
                if listening {
                    VStack(spacing: 12) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 64)).foregroundStyle(Theme.accent)
                        Text(L.t("Hear it, pick the word"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text(model.from.value(model.answer))
                        .font(Theme.jpStrokes(120))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .onTapGesture { pronouncer.speak(kana: model.answer) }

            OptionGrid(count: model.options.count) { i in
                QuizOptionButton(text: model.to.value(model.options[i]),
                                 border: optionBorder(i),
                                 disabled: model.picked != nil,
                                 font: Theme.jpBold(26)) {
                    model.choose(i, context: context)
                    Track.event("kana_quiz_answer",
                               ["correct": model.isCorrectOption(i), "mode": listening ? "listening" : "classic"])
                }
            }

            Button(action: { model.next(); autoPlay() }) {
                Text(L.t("Next")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.picked == nil)
        }
        .padding()
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { autoPlay(); Track.screen(listening ? "kana_quiz_listening" : "kana_quiz_classic") }
        .toolbar {
            ToolbarItem(placement: .principal) { ScoreBadge(correct: model.correct, total: model.total) }
            ToolbarItem(placement: .topBarTrailing) { SoundToggle() }
        }
    }

    private func optionBorder(_ i: Int) -> Color {
        guard model.picked != nil else { return Theme.line }
        if model.isCorrectOption(i) { return Theme.correct }
        if model.picked == i { return Theme.wrong }
        return Theme.line
    }
}
