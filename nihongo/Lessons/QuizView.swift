import SwiftUI

enum VForm: Int, CaseIterable {
    case kana, kanji, romaji, translation
    var label: String {
        switch self {
        case .kana: return "kana"; case .kanji: return "kanji"
        case .romaji: return "romaji"; case .translation: return "meaning"
        }
    }
    func value(_ v: Vocab) -> String {
        switch self {
        case .kana: return v.kana; case .kanji: return v.kanji
        case .romaji: return v.romaji; case .translation: return v.translation
        }
    }
}

@Observable
final class QuizModel {
    let vocab: [Vocab]
    var from: VForm = .kana
    var to: VForm = .translation
    private(set) var options: [Vocab] = []
    private(set) var answer: Vocab
    private(set) var picked: Int? = nil
    private(set) var correct = 0
    private(set) var total = 0

    init(vocab: [Vocab]) {
        self.vocab = vocab
        self.answer = vocab.first!
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

    /// Cycle a form through the 4 options, skipping the value used by the other side.
    func cycleFrom() { from = Self.nextForm(after: from, avoiding: to) }
    func cycleTo()   { to = Self.nextForm(after: to, avoiding: from) }

    private static func nextForm(after f: VForm, avoiding other: VForm) -> VForm {
        var n = f
        repeat {
            n = VForm(rawValue: (n.rawValue + 1) % VForm.allCases.count)!
        } while n == other
        return n
    }

    func isCorrectOption(_ i: Int) -> Bool { options[i].id == answer.id }

    func choose(_ i: Int) {
        guard picked == nil else { return }
        picked = i
        total += 1
        if isCorrectOption(i) { correct += 1 }
    }
}

struct QuizView: View {
    @State private var model: QuizModel
    @Environment(\.pronouncer) private var pronouncer

    init(lesson: Lesson) {
        _model = State(initialValue: QuizModel(vocab: lesson.entries))
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

            Text(model.from.value(model.answer))
                .font(.system(size: 40, weight: .light))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
                .onTapGesture { pronouncer.speak(model.answer) }

            OptionGrid(count: model.options.count) { i in
                QuizOptionButton(text: model.to.value(model.options[i]),
                                 border: optionBorder(i),
                                 disabled: model.picked != nil) { model.choose(i) }
            }

            Button { model.next() } label: { Text(L.t("Next")).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.picked == nil)
        }
        .padding()
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { ScoreBadge(correct: model.correct, total: model.total) } }
    }

    private func optionBorder(_ i: Int) -> Color {
        guard model.picked != nil else { return Color(.separator) }
        if model.isCorrectOption(i) { return Theme.correct }
        if model.picked == i { return Theme.wrong }
        return Color(.separator)
    }
}
