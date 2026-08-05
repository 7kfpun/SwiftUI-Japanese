import SwiftUI

enum AnswerState { case inProgress, correct, wrong }

struct Tile: Identifiable, Hashable { let id: Int; let text: String }

@Observable
final class LearnModel {
    let vocab: [Vocab]
    var index = 0
    private(set) var tiles: [Tile] = []
    private(set) var answer: [String] = []
    private(set) var state: AnswerState = .inProgress

    var current: Vocab { vocab[index] }
    var target: String { cleanWord(current.kana) }
    /// Some entries are sentence-length and exceed the tile cap (e.g. L14). Bail gracefully.
    var isPlayable: Bool { !tiles.isEmpty || target.count <= 15 }

    init(vocab: [Vocab]) {
        self.vocab = vocab
        loadTiles()
    }

    func loadTiles() {
        answer = []
        state = .inProgress
        let clean = Array(target)
        guard let first = clean.first else { tiles = []; return }
        var length = 10 - clean.count
        if length < 0 { length = 15 - clean.count }
        if length < 0 { tiles = []; return }        // sentence-length → no tile game
        let pool = KanaData.hiraganaPool.contains(String(first))
            ? KanaData.hiraganaPool : KanaData.katakanaPool
        let distractors = Array(pool.shuffled().prefix(length))
        let all = distractors + clean.map(String.init)
        tiles = all.shuffled().enumerated().map { Tile(id: $0.offset, text: $0.element) }
    }

    func tap(_ tile: Tile) {
        guard state == .inProgress, answer.count < target.count else { return }
        answer.append(tile.text)
        let built = answer.joined()
        if built == target { state = .correct }
        else if !target.hasPrefix(built) { state = .wrong }
    }

    func clearAnswer() { answer = []; state = .inProgress }
    func next()   { index = (index + 1) % vocab.count; loadTiles() }
    func prev()   { index = (index - 1 + vocab.count) % vocab.count; loadTiles() }
    func random() { index = Int.random(in: 0..<vocab.count); loadTiles() }
}

struct LearnView: View {
    @State private var model: LearnModel
    @State private var options = CardOptions()
    @AppStorage("isOrdered") private var ordered = true
    @Environment(\.pronouncer) private var pronouncer

    init(lesson: Lesson) {
        _model = State(initialValue: LearnModel(vocab: lesson.entries))
    }

    var body: some View {
        VStack(spacing: 16) {
            CardOptionsBar()

            card

            if model.isPlayable {
                tileGrid
            } else {
                Text(L.t("This entry is a full sentence — no tile game."))
                    .font(.footnote).foregroundStyle(.secondary)
            }

            controls
        }
        .padding()
        .background(Theme.canvas)
        .navigationTitle("\(model.index + 1) / \(model.vocab.count)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var card: some View {
        VStack(spacing: 10) {
            // assembled reading (the task)
            HStack(spacing: 4) {
                Text(model.answer.joined())
                    .font(.system(size: 34, weight: .semibold))
                Image(systemName: stateIcon).foregroundStyle(stateColor)
                    .opacity(model.state == .inProgress ? 0 : 1)
            }
            .frame(height: 46)

            if options.showKanji && model.current.displaysKanji {
                Text(model.current.kanji).font(.title3)
            }
            if options.showRomaji {
                Text(model.current.romaji).foregroundStyle(.secondary)
            }
            if options.showTranslation {
                Text(model.current.translation).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { pronouncer.speak(model.current) }
    }

    private var tileGrid: some View {
        let cols = Array(repeating: GridItem(.flexible()), count: 5)
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(model.tiles) { tile in
                Button { model.tap(tile) } label: {
                    Text(tile.text)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
                .buttonStyle(.plain)
            }
        }
        .disabled(model.state != .inProgress)
    }

    @ViewBuilder private var controls: some View {
        HStack {
            if model.state == .wrong {
                Button(L.t("Clear")) { model.clearAnswer() }.buttonStyle(.bordered)
            }
            Spacer()
            if ordered {
                Button { model.prev() } label: { Image(systemName: "chevron.left") }
                Button { model.next() } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { model.random() } label: {
                    Label("Random", systemImage: "shuffle")
                }.buttonStyle(.borderedProminent)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { ordered.toggle() } label: {
                    Image(systemName: ordered ? "arrow.right.to.line" : "shuffle")
                }
            }
        }
    }

    private var stateIcon: String {
        model.state == .correct ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    private var stateColor: Color {
        model.state == .correct ? Theme.correct : Theme.wrong
    }
}
