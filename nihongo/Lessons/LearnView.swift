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
    @State private var fling: Int? = nil   // programmatic CardPager trigger (Random button)
    @State private var viewed = 1          // cards seen so far (first card is showing)
    @State private var showPaywall = false
    // Read the visibility flags directly so the current card updates the instant a toggle flips.
    @AppStorage(Pref.kanjiShown)       private var showKanji = true
    @AppStorage(Pref.kanaShown)        private var showKana = true
    @AppStorage(Pref.romajiShown)      private var showRomaji = true
    @AppStorage(Pref.translationShown) private var showTranslation = true
    @AppStorage(Pref.ordered) private var ordered = true
    @AppStorage(Pref.soundOn) private var soundOn = true
    @Environment(\.pronouncer) private var pronouncer
    @Environment(Store.self) private var store
    @State private var tileGridWidth: CGFloat = 0

    private let lessonNumber: Int
    private let tileCols = 5
    private let tileSpacing: CGFloat = 8

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
            .onChange(of: ordered) { Track.event("learn_order_mode", ["ordered": ordered]) }

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
        // Paging speaks explicitly in turnPage — onChange(of: index) would silently skip
        // when random() happens to land on the same card.
        .onAppear { autoPlay(); Track.screen("learn", ["lesson": lessonNumber]) }
        .onChange(of: model.state) {
            if model.state == .correct { Track.event("learn_answer", ["correct": true]) }
            else if model.state == .wrong { Track.event("learn_answer", ["correct": false]) }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(source: "learn_trial_limit") }
    }

    private func autoPlay() {
        if soundOn { pronouncer.speak(model.current) }
    }

    /// Swipe/fling handler: next/prev (ordered) or shuffle (random).
    private func turnPage(_ dir: Int) {
        if ordered { dir > 0 ? model.next() : model.prev() } else { model.random() }
        viewed += 1
        autoPlay()   // explicit: every completed page-turn speaks the new word
    }

    private var card: some View {
        VStack(spacing: 10) {
            // assembled reading (the task)
            HStack(spacing: 4) {
                Text(model.answer.joined())
                    .font(Theme.jp(32))
                Image(systemName: stateIcon).foregroundStyle(stateColor)
                    .opacity(model.state == .inProgress ? 0 : 1)
            }
            .frame(height: 46)

            if showKana {
                Text(model.target).font(Theme.jp(20))   // the reading (hint / reveal)
            }
            if showKanji && model.current.displaysKanji {
                Text(model.current.kanji).font(Theme.jp(20))
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
        .onTapGesture { pronouncer.speak(model.current) }
        .cardPager(fling: $fling,
                   canPage: { !reachedLimit },
                   onBlocked: {
                       showPaywall = true
                       Track.event("trial_limit", ["mode": "learn", "lesson": lessonNumber])
                   },
                   page: turnPage)
    }

    /// Explicit square size, computed from the measured grid width — matches the
    /// Kana table tiles: `.aspectRatio(1, .fit)` combined with flexible grid
    /// columns doesn't reliably divide space into even squares.
    private var tileSize: CGFloat {
        guard tileGridWidth > 0 else { return 44 }
        return (tileGridWidth - tileSpacing * CGFloat(tileCols - 1)) / CGFloat(tileCols)
    }

    private var tileGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: tileSpacing), count: tileCols)
        return LazyVGrid(columns: cols, spacing: tileSpacing) {
            ForEach(model.tiles) { tile in
                Button { model.tap(tile) } label: {
                    Text(tile.text)
                        .font(.title3)
                        .frame(width: tileSize, height: tileSize)
                        .contentShape(Rectangle())
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { tileGridWidth = $0 }
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
                    Button { fling = 1 } label: {
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
