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
        upsert(romaji: answer.romaji, isCorrect: right, context: context)
    }

    private func upsert(romaji: String, isCorrect: Bool, context: ModelContext) {
        let descriptor = FetchDescriptor<KanaResult>(predicate: #Predicate { $0.romaji == romaji })
        if let existing = try? context.fetch(descriptor).first {
            existing.isCorrect = isCorrect
            existing.timestamp = .now
        } else {
            context.insert(KanaResult(romaji: romaji, isCorrect: isCorrect))
        }
        try? context.save()
    }
}

struct KanaQuizView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.pronouncer) private var pronouncer
    @State private var model: KanaQuizModel

    init(table: KanaTable) {
        _model = State(initialValue: KanaQuizModel(pool: table.rows.flatMap { $0 }))
    }

    var body: some View {
        VStack(spacing: 16) {
            // Direction toggles
            HStack(spacing: 8) {
                Button(model.from.label) { model.swapFrom() }
                Image(systemName: "arrow.right")
                Button(model.to.label) { model.swapTo() }
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
            .disabled(model.picked != nil)

            // Question prompt
            Text(model.from.value(model.answer))
                .font(.system(size: 80, weight: .light))
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
                .onTapGesture { pronouncer.speak(kana: model.answer.hiragana) }

            OptionGrid(count: model.options.count) { i in
                QuizOptionButton(text: model.to.value(model.options[i]),
                                 border: optionBorder(i),
                                 disabled: model.picked != nil) { model.choose(i, context: context) }
            }

            Button(action: { model.next() }) {
                Text(L.t("Next")).frame(maxWidth: .infinity)
            }
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
