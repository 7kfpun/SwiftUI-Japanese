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
            // Direction toggles
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

            // The two options, left and right — large tappable chips.
            HStack(spacing: 12) {
                optionChip(leftOption, side: 0)
                optionChip(rightOption, side: 1)
            }
        }
        .padding()
        .background(Theme.canvas)
        .overlay { if let lastCorrect { resultBadge(lastCorrect) } }
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

    private var promptCard: some View {
        SwipeCard(drag: drag,
                  threshold: threshold,
                  leftStamp: ("arrow.left", Theme.accent),
                  rightStamp: ("arrow.right", Theme.accent),
                  showsStamps: model.picked == nil) {
            Text(model.from.value(model.answer))
                .font(Theme.jpStrokes(150))
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
    private func optionChip(_ opt: K, side: Int) -> some View {
        SwipeOptionChip(text: opt.romaji.isEmpty ? "" : model.to.value(opt),
                        side: side,
                        picked: model.picked,
                        isAnswer: opt.romaji == model.answer.romaji,
                        font: .system(size: 30, weight: .semibold)) { decide(side) }
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


    private func decide(_ side: Int) {
        guard model.picked == nil, model.options.count > side else { return }
        model.choose(side, context: context)
        Track.event("kana_quiz_answer", ["correct": model.isCorrectOption(side), "mode": "swipe"])
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
