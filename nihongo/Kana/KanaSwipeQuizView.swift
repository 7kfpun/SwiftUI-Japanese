import SwiftUI
import SwiftData

/// Tinder-style kana quiz: one prompt card + two candidate readings (left / right).
/// Swipe the card left to choose the left option, right to choose the right option.
struct KanaSwipeQuizView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.pronouncer) private var pronouncer
    @AppStorage(Pref.soundOn) private var soundOn = true
    @State private var model: KanaQuizModel
    @State private var drag: CGSize = .zero
    @State private var lastCorrect: Bool? = nil

    private let threshold: CGFloat = 90

    init(table: KanaTable) {
        _model = State(initialValue: KanaQuizModel(pool: table.rows.flatMap { $0 }, optionCount: 2))
    }

    private var leftOption: K { model.options.first ?? K("", "", "") }
    private var rightOption: K { model.options.count > 1 ? model.options[1] : K("", "", "") }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Button(model.from.label) { model.swapFrom() }
                Image(systemName: "arrow.right")
                Button(model.to.label) { model.swapTo() }
            }
            .font(.subheadline).buttonStyle(.bordered)
            .disabled(model.picked != nil)

            // Prompt card (draggable) — fills the available height. The peek stack
            // behind it is static (same visual language as the flashcard decks);
            // only the prompt card itself moves with the drag.
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
        .overlay { if let lastCorrect { AnswerBadge(correct: lastCorrect) } }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { autoPlay(); Track.screen("kana_quiz_swipe") }
        .toolbar {
            ToolbarItem(placement: .principal) { ScoreBadge(correct: model.correct, total: model.total) }
            ToolbarItem(placement: .topBarTrailing) { SoundToggle() }
        }
    }

    /// Kana audio can never reveal the answer — hiragana/katakana/romaji share one sound.
    private func autoPlay() {
        if soundOn { pronouncer.speak(kana: model.answer) }
    }

    /// Same content-follows-script rule as the classic quiz — see `KanaQuizView.promptFont`
    /// for why KanjiStrokeOrders is wrong for romaji even though it renders it cleanly.
    private var promptFont: Font {
        model.from.isJapanese ? Theme.jpStrokes(150) : Theme.display(150)
    }

    private var promptCard: some View {
        SwipeCard(drag: drag,
                  threshold: threshold,
                  leftStamp: ("arrow.left", Theme.accent),
                  rightStamp: ("arrow.right", Theme.accent),
                  showsStamps: model.picked == nil) {
            Text(model.from.value(model.answer))
                .font(promptFont)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(.horizontal, 16)
        }
        .onTapGesture { pronouncer.speak(kana: model.answer) }
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

    /// Kana readings are one to three characters, so they take a much larger face than
    /// Train's vocab glosses — the only thing this screen varies on the shared chip.
    ///
    /// The face follows the script too, matching the classic quiz: kana on `jpBold`, romaji
    /// on the rounded Latin face — so the same two answers don't look like two quizzes.
    private func optionChip(_ opt: K, side: Int) -> some View {
        SwipeOptionChip(text: opt.romaji.isEmpty ? "" : model.to.value(opt),
                        side: side,
                        picked: model.picked,
                        isAnswer: opt.romaji == model.answer.romaji,
                        font: model.to.isJapanese ? Theme.jpBold(30)
                                                  : Theme.display(30, weight: .semibold)) { decide(side) }
    }

    private func decide(_ side: Int) {
        guard model.picked == nil, model.options.count > side else { return }
        model.choose(side, context: context)
        // Its own name, like the other two kana quizzes — a swipe between two options is
        // a different exercise from picking one of four, and the name says so on its own.
        Track.event("kana_swipe_answer", ["correct": model.isCorrectOption(side)])
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
