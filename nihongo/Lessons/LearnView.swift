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
    @State private var drag: CGFloat = 0
    @State private var viewed = 1          // cards seen so far (first card is showing)
    @State private var showPaywall = false
    // Read the visibility flags directly so the current card updates the instant a toggle flips.
    @AppStorage("isKanjiShown")       private var showKanji = true
    @AppStorage("isKanaShown")        private var showKana = true
    @AppStorage("isRomajiShown")      private var showRomaji = true
    @AppStorage("isTranslationShown") private var showTranslation = true
    @AppStorage("isOrdered") private var ordered = true
    @AppStorage("isSoundOn") private var soundOn = true
    @Environment(\.pronouncer) private var pronouncer
    @Environment(Store.self) private var store

    private let swipeThreshold: CGFloat = 80
    private let lessonNumber: Int

    init(lesson: Lesson) {
        lessonNumber = lesson.number
        _model = State(initialValue: LearnModel(vocab: lesson.entries))
    }

    /// Locked lessons let you page through `freeTrialCards` cards before the paywall.
    private var reachedLimit: Bool {
        Gating.trialLimit(lesson: lessonNumber, isPremium: store.isPremium)
            .map { viewed >= $0 } ?? false
    }

    var body: some View {
        VStack(spacing: 16) {
            CardOptionsBar()

            Picker("", selection: $ordered) {
                Text(L.t("Ordered")).tag(true)
                Text(L.t("Random")).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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
        // Auto-play the word on each page when sound is on (mirrors RN assessment.js).
        .onAppear { autoPlay(); Track.screen("learn", ["lesson": lessonNumber]) }
        .onChange(of: model.index) { autoPlay() }
        .onChange(of: model.state) {
            if model.state == .correct { Track.event("learn_answer", ["correct": true]) }
            else if model.state == .wrong { Track.event("learn_answer", ["correct": false]) }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private func autoPlay() {
        if soundOn { pronouncer.speak(model.current) }
    }

    /// Swipe the card to move: left/right = next/prev (ordered) or shuffle (random).
    private func handleSwipe(_ width: CGFloat) {
        guard abs(width) > swipeThreshold else { withAnimation(.spring) { drag = 0 }; return }
        if reachedLimit {                           // out of free cards on a locked lesson
            withAnimation(.spring) { drag = 0 }
            showPaywall = true
            Track.event("trial_limit", ["mode": "learn", "lesson": lessonNumber])
            return
        }
        let dir: CGFloat = width < 0 ? -1 : 1
        withAnimation(.easeOut(duration: 0.18)) { drag = dir * 500 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if ordered { width < 0 ? model.next() : model.prev() } else { model.random() }
            viewed += 1
            drag = -dir * 500                       // new card enters from the opposite side
            withAnimation(.spring) { drag = 0 }
        }
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

            if showKana {
                Text(model.target).font(.title3.weight(.medium))   // the reading (hint / reveal)
            }
            if showKanji && model.current.displaysKanji {
                Text(model.current.kanji).font(.title3)
            }
            if showRomaji {
                Text(model.current.romaji).foregroundStyle(.secondary)
            }
            if showTranslation {
                Text(model.current.translation).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottom) {
            if ordered {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.compact.left")
                    Text(L.t("Swipe"))
                    Image(systemName: "chevron.compact.right")
                }
                .font(.caption).foregroundStyle(.tertiary).padding(.bottom, 8)
            }
        }
        .contentShape(Rectangle())
        .offset(x: drag)
        .rotationEffect(.degrees(Double(drag / 30)))
        .onTapGesture { pronouncer.speak(model.current) }
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation.width }
                .onEnded { handleSwipe($0.translation.width) }
        )
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
        if reachedLimit {
            Button { showPaywall = true } label: {
                Label(L.t("Unlock to continue"), systemImage: "lock.open.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            HStack {
                if model.state == .wrong {
                    Button(L.t("Clear")) { model.clearAnswer() }.buttonStyle(.bordered)
                }
                Spacer()
                if !ordered {
                    Button { handleSwipe(-200) } label: {
                        Label(L.t("Random"), systemImage: "shuffle")
                    }
                    .buttonStyle(.borderedProminent)
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
