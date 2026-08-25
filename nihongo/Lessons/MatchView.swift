import SwiftUI

/// Endless pair-matching over a lesson's vocabulary: five words down the left, their five
/// meanings shuffled down the right, tap one from each side to clear the pair. Clear all
/// five and the next five deal themselves — like Practice it never ends, because this is
/// rehearsal rather than a test, and the Challenge ladder is where results count.
///
/// **Tap order is free**: left-then-right and right-then-left both work. Fixing the order
/// would make the mode partly about remembering the rule, and someone who scans the
/// meanings first and hunts for the word is doing recall — the harder and more valuable
/// direction of the two, so it would be perverse to forbid it.
@Observable
final class MatchModel {
    /// Pairs on screen at once. Five is the most that fits two readable columns at the
    /// larger Dynamic Type sizes without either side scrolling, and a round you have to
    /// scroll is a round you can't scan — which is the entire exercise.
    static let pairsPerRound = 5

    enum Side { case left, right }

    struct Tile: Identifiable, Equatable {
        /// The vocab id. Matching compares *these*, never the displayed text, so a pair
        /// is right because it is the same word and not because two glosses read alike.
        let id: String
        let text: String
        /// Which face draws it — the left column is Japanese, the right is prose in the
        /// meanings language. Same rule as `VForm.isJapanese`: the face follows the
        /// content's script, not the column.
        let isJapanese: Bool
        var cleared = false
    }

    let vocab: [Vocab]
    private(set) var left: [Tile] = []
    private(set) var right: [Tile] = []
    private(set) var pickedLeft: Int?
    private(set) var pickedRight: Int?
    /// True only while a wrong pair is on screen. The model holds feedback state no
    /// longer than it is drawn, and the *view* clears it — a model that arms its own
    /// timers is a model you can't test without waiting for them.
    private(set) var wrong = false
    /// The id of the pair just cleared, for the view's green flash. Reset on each deal
    /// so a new board never opens with a stale celebration on it.
    private(set) var lastMatched: String?
    /// True once every pair is cleared, until the view calls `dealNext()`. The deal is
    /// deferred rather than done inside `resolve()` because the fifth match deserves the
    /// same treatment as the other four: dealing synchronously inside the tap replaced
    /// `round` before the view could speak the word or show the green flash — the last
    /// pair of every round was silently swallowed by its own success.
    private(set) var roundCleared = false
    private(set) var matched = 0
    private(set) var attempts = 0
    private(set) var rounds = 0

    /// The words of the current round, so the view can speak a tile without a lookup
    /// through the whole lesson.
    private var round: [Vocab] = []
    /// Words not yet dealt in this pass, shuffled — the same bag Train used, and
    /// for the same reason: independent random draws re-deal words you just saw while
    /// others never appear at all.
    private var bag: [Vocab] = []

    init(vocab: [Vocab]) {
        self.vocab = vocab
        deal()
    }

    func word(id: String) -> Vocab? { round.first { $0.id == id } }

    /// How the most recent pick arrived — "tap" or "drag" — carried onto
    /// `match_answer`, since the connect-a-line drag is the design's headline gesture
    /// and its adoption was unmeasurable while both routes resolved identically.
    private(set) var lastVia = "tap"

    /// Tap a tile. Ignored while a miss is showing, on a tile already cleared, and in
    /// the gap between the last match and the next deal.
    func pick(side: Side, index: Int, via: String = "tap") {
        guard !wrong, !roundCleared else { return }
        lastVia = via
        switch side {
        case .left:
            guard left.indices.contains(index), !left[index].cleared else { return }
            pickedLeft = index
        case .right:
            guard right.indices.contains(index), !right[index].cleared else { return }
            pickedRight = index
        }
        resolve()
    }

    /// Dismiss a shown miss and free both columns again.
    func clearMiss() {
        wrong = false
        pickedLeft = nil
        pickedRight = nil
    }

    private func resolve() {
        guard let l = pickedLeft, let r = pickedRight else { return }
        attempts += 1
        guard left[l].id == right[r].id else { wrong = true; return }
        left[l].cleared = true
        right[r].cleared = true
        lastMatched = left[l].id
        matched += 1
        pickedLeft = nil
        pickedRight = nil
        // `!left.isEmpty` guards the degenerate case: an empty round satisfies
        // `allSatisfy` vacuously, which would flag a cleared round on empty data.
        if !left.isEmpty, left.allSatisfy(\.cleared) { roundCleared = true }
    }

    /// Deal the next round, once the view has let the last match land. Model-side state,
    /// view-side timing — same split as `clearMiss`, and for the same reason: a model
    /// that arms its own timers is a model you can't test without waiting for them.
    func dealNext() {
        guard roundCleared else { return }
        deal()
    }

    /// Deal the next round.
    ///
    /// A candidate is rejected if it repeats a word already dealt *or* reads the same on
    /// either side. Two tiles with the same text make one of the two pairings arbitrary,
    /// and a miss the learner could not have avoided is the app's fault, not theirs —
    /// なん/なに and words sharing a gloss are the usual culprits.
    private func deal() {
        guard !vocab.isEmpty else { left = []; right = []; round = []; return }
        rounds += 1
        lastMatched = nil
        roundCleared = false
        var picks: [Vocab] = []
        var guardCount = 0
        let want = min(Self.pairsPerRound, vocab.count)
        while picks.count < want, guardCount < 2000 {
            guardCount += 1
            let c = drawFromBag()
            guard !picks.contains(where: {
                $0.id == c.id || $0.kana == c.kana || $0.translation == c.translation
            }) else { continue }
            picks.append(c)
        }

        round = picks
        left = picks.map { Tile(id: $0.id, text: $0.kana, isJapanese: true) }
        // Reversed rather than reshuffled on a collision: with five tiles the shuffle
        // lands in the original order about once in 120 rounds, and a round where the
        // columns already line up isn't a puzzle.
        var shuffled = picks.shuffled()
        if picks.count > 1, shuffled.map(\.id) == picks.map(\.id) { shuffled.reverse() }
        right = shuffled.map { Tile(id: $0.id, text: $0.translation, isJapanese: false) }

        pickedLeft = nil
        pickedRight = nil
        wrong = false
    }

    private func drawFromBag() -> Vocab {
        if bag.isEmpty { bag = vocab.shuffled() }
        return bag.removeLast()
    }
}

/// Match — two columns, tap a word and its meaning to clear the pair.
struct MatchView: View {
    @State private var model: MatchModel
    @Environment(\.pronouncer) private var pronouncer
    @Environment(Store.self) private var store
    @AppStorage(Pref.soundOn) private var soundOn = true
    private let lessonNumber: Int

    init(lesson: Lesson) {
        lessonNumber = lesson.number
        _model = State(initialValue: MatchModel(vocab: lesson.entries))
    }

    /// The pair whose green moment is still on screen. View state, not model state: the
    /// model records *what* matched, the view decides how long that is worth looking at.
    @State private var flashID: String?

    // MARK: - Connect-the-lines state (design 3d)

    /// One tile's slot on the board, the key the geometry is filed under.
    /// `fileprivate` so the preference key below can name it.
    fileprivate struct Anchor: Hashable {
        let side: MatchModel.Side
        let index: Int
    }

    /// Every tile's frame in the board's coordinate space, kept fresh by preference —
    /// the lines need real geometry, and a `List`-free custom board is the one place
    /// in the app that has to know where its views actually are.
    @State private var frames: [Anchor: CGRect] = [:]
    /// The tile a finger is currently dragging a line out of, and where the finger is.
    @State private var dragFrom: Anchor?
    @State private var dragPoint: CGPoint?

    var body: some View {
        VStack(spacing: 8) {
            // A `Grid`, not two independent columns. Each column used to distribute its
            // own height, so a long gloss on the right made that side's rows taller than
            // the left's and the two lists drifted out of step — tiles no longer sat
            // opposite anything, which is fatal on a screen whose whole job is pairing.
            // A grid row is one row: both tiles share its height, whatever is in them.
            Grid(horizontalSpacing: 34, verticalSpacing: 10) {
                ForEach(0..<max(model.left.count, model.right.count), id: \.self) { i in
                    GridRow {
                        if i < model.left.count {
                            tileButton(model.left[i], side: .left, index: i)
                        }
                        if i < model.right.count {
                            tileButton(model.right[i], side: .right, index: i)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "match")
            .onPreferenceChange(TileFramesKey.self) { frames = $0 }
            // The lines draw over the board but swallow nothing: never hit-tested,
            // so a tap on the tile beneath them still lands.
            .overlay { lines.allowsHitTesting(false) }

            // The gesture is invisible until tried, so say it once, quietly — and name
            // the fallback underneath, because the drag is the better way rather than
            // the only one, and a learner who can't manage it should not be stuck.
            VStack(spacing: 3) {
                Text(L.t("Drag a word to its meaning"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(L.t("Or tap one on each side"))
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // `rounds` counts deals, and the first deal happens in `init` — so it is
                // already 1 while the first round is on screen. Adding one opened the
                // mode on "Round 2".
                // Pairs cleared out of attempts — one number over another, which is
                // what this screen's score actually is. `ScoreBadge`'s third figure is
                // just the difference between the two, and the width it cost is what
                // pushed a two-digit count into wrapping on a real device.
                TallyBadge(icon: "link", done: model.matched, total: model.attempts,
                           tint: Theme.accent,
                           caption: L.t("Round %@ · %@ pairs",
                                        "\(model.rounds)", "\(model.left.count)"))
            }
            // No flag on Match: no single word is "the" word on a board of five pairs.
            FlagAndSoundToolbar()
        }
        .onAppear {
            Track.screen("match", ["lesson": lessonNumber])
            ModeVisits.mark(lesson: lessonNumber, mode: "match")
            if !store.isPremium { Ads.preloadInterstitial() }
        }
        .onDisappear {
            if !store.isPremium, model.attempts > 0 { Ads.showInterstitialIfReady() }
        }
        // The miss flash lives here rather than in the model: long enough to see which
        // two tiles were wrong, short enough that it never feels like a penalty.
        .onChange(of: model.wrong) {
            guard model.wrong else { return }
            Track.event("match_answer", ["lesson": lessonNumber, "correct": false,
                                         "via": model.lastVia])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeOut(duration: 0.15)) { model.clearMiss() }
            }
        }
        // The green moment. Keyed on `matched` (a count) rather than `lastMatched` (an
        // id), because the last pair of one round and the first of the next could be the
        // same word — an id that doesn't change wouldn't re-fire.
        .onChange(of: model.matched) {
            guard let id = model.lastMatched else { return }
            Track.event("match_answer", ["lesson": lessonNumber, "correct": true,
                                         "via": model.lastVia])
            withAnimation(.easeOut(duration: 0.15)) { flashID = id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                // A later match may already be flashing; only clear our own.
                if flashID == id {
                    withAnimation(.easeOut(duration: 0.3)) { flashID = nil }
                }
                // The last pair gets the same 0.6s as the other four before the board
                // turns over — the deal is deferred in the model precisely so this
                // moment (the flash, and the word still speaking) isn't swallowed.
                if model.roundCleared {
                    // The round that just closed, logged before the deal bumps `rounds`.
                    // `attempts` is the running total, so consecutive rows say what each
                    // successive board cost in taps — the mode is endless, and how deep
                    // anyone goes is the only session length it has.
                    Track.event("match_round", ["lesson": lessonNumber,
                                                "round": model.rounds,
                                                "attempts": model.attempts])
                    withAnimation(.easeOut(duration: 0.25)) { model.dealNext() }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.matched)
    }

    @ViewBuilder
    private func tileButton(_ tile: MatchModel.Tile, side: MatchModel.Side, index: Int) -> some View {
        let picked = (side == .left ? model.pickedLeft : model.pickedRight) == index
        let missed = picked && model.wrong
        let flashing = flashID == tile.id

        Button {
            // Resolved *before* the pick: a pick that completes the round flags the
            // board for re-dealing, and the word must be the one that was tapped, not
            // whatever the lookup finds after the state has moved on.
            let word = model.word(id: tile.id)
            model.pick(side: side, index: index)
            // Only the Japanese side speaks. The meaning is prose in the interface
            // language, and a Japanese voice reading a German gloss is not accented,
            // it is unintelligible — the same rule `Speech.utterance` documents.
            if side == .left, soundOn, let word {
                pronouncer.speak(word)
            }
        } label: {
            Text(tile.text)
                .font(tile.isJapanese ? Theme.jp(20) : .system(.subheadline, weight: .medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 56)   // the design's tile: a comfortable two-line box
                .padding(.vertical, 8)
                .padding(.horizontal, 7)
                .background(
                    // Green is answer feedback, which a correct match genuinely is — the
                    // one place a fill is allowed. It rides on the flash, not on
                    // `cleared`, so the board doesn't fill up with green as it empties.
                    flashing ? Theme.correct.opacity(0.15) : Theme.surface,
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    // Selection stays an accent *border*; a miss takes the red it earned.
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(flashing ? Theme.correct : (missed ? Theme.wrong : Theme.accent),
                                      lineWidth: (picked || flashing) ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
        .disabled(tile.cleared)
        // A miss shakes the tile it happened on. The red border says *which* two were
        // wrong; the shake says a thing happened — and it is over in 0.22s, before it
        // can start feeling like a telling-off.
        .modifier(ShakeEffect(shakes: missed ? 1 : 0))
        .animation(.easeInOut(duration: 0.22), value: missed)
        // Dealt in rather than appearing: five pairs replacing five pairs in the same
        // ten boxes is otherwise indistinguishable from nothing having happened.
        .transition(AnyTransition.opacity.combined(with: .offset(y: 8)))
        // File this tile's frame under its slot, for the lines and the drop test.
        .background(GeometryReader { geo in
            Color.clear.preference(key: TileFramesKey.self,
                                   value: [Anchor(side: side, index: index):
                                           geo.frame(in: .named("match"))])
        })
        // The drag rides *beside* the tap (`simultaneousGesture`, a real minimum
        // distance): press-and-release is still a pick, movement becomes a line.
        // Either side can be the start — the same freedom the taps have, and for the
        // same reason: meanings-first is recall, the more valuable direction.
        .simultaneousGesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .named("match"))
                .onChanged { value in
                    guard !tile.cleared, !model.wrong, !model.roundCleared else { return }
                    if dragFrom == nil {
                        dragFrom = Anchor(side: side, index: index)
                        // The line starts by saying its word, like a tap would.
                        if side == .left, soundOn, let word = model.word(id: tile.id) {
                            pronouncer.speak(word)
                        }
                    }
                    guard dragFrom == Anchor(side: side, index: index) else { return }
                    dragPoint = value.location
                }
                .onEnded { value in
                    defer { dragFrom = nil; dragPoint = nil }
                    guard let from = dragFrom, from == Anchor(side: side, index: index),
                          !model.wrong, !model.roundCleared else { return }
                    let targetSide: MatchModel.Side = from.side == .left ? .right : .left
                    let tiles = targetSide == .left ? model.left : model.right
                    // Where the finger let go decides; a release over nothing (or over
                    // a cleared tile) just lets the line snap back, no penalty.
                    guard let hit = frames.first(where: { anchor, rect in
                        anchor.side == targetSide && rect.contains(value.location)
                            && tiles.indices.contains(anchor.index)
                            && !tiles[anchor.index].cleared
                    }) else { return }
                    // Drop any tile still selected from an earlier tap. A pick left on
                    // the *opposite* side resolves against the drag's first `pick` —
                    // scoring a wrong answer the learner never made, and then swallowing
                    // the drop, because `pick` refuses while a miss is showing.
                    model.clearMiss()
                    model.pick(side: from.side, index: from.index, via: "drag")
                    model.pick(side: targetSide, index: hit.key.index, via: "drag")
                }
        )
        // Cleared pairs stay in place rather than collapsing: tiles that reflow under
        // your thumb make the next tap land on something you didn't aim at. They keep
        // their footprint and *empty* — 0.2 opacity left grey text floating on the
        // background, which read as broken rendering rather than as a cleared slot.
        .opacity(flashing ? 1 : (tile.cleared ? 0 : 1))
        .overlay {
            if tile.cleared, !flashing {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.line.opacity(0.35))
            }
        }
        .animation(.easeOut(duration: 0.2), value: tile.cleared)
        .accessibilityLabel(tile.text)
        .accessibilityHint(tile.cleared ? L.t("Complete!") : "")
    }

    /// The drawn layer: the line following the finger, and the one that has just been
    /// completed.
    ///
    /// **Only the newest match keeps a line.** The design leaves every cleared pair's
    /// line on the board, and with five pairs in random positions that is four or five
    /// long diagonals crossing each other and the tiles — a scribble rather than a
    /// record. One line, in the green of the match it belongs to, reads as what it is:
    /// feedback for the pair just made.
    private var lines: some View {
        Canvas { context, _ in
            if let id = flashID,
               let i = model.left.firstIndex(where: { $0.id == id }),
               let j = model.right.firstIndex(where: { $0.id == id }),
               let a = frames[Anchor(side: .left, index: i)],
               let b = frames[Anchor(side: .right, index: j)] {
                var path = Path()
                path.move(to: CGPoint(x: a.maxX, y: a.midY))
                path.addLine(to: CGPoint(x: b.minX, y: b.midY))
                context.stroke(path, with: .color(Theme.correct),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if let from = dragFrom, let point = dragPoint,
               let rect = frames[from] {
                var path = Path()
                path.move(to: CGPoint(x: from.side == .left ? rect.maxX : rect.minX,
                                      y: rect.midY))
                path.addLine(to: point)
                context.stroke(path, with: .color(Theme.accent),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }
}

/// Tile frames in the board's space — merged across tiles, latest write wins.
private struct TileFramesKey: PreferenceKey {
    static var defaultValue: [MatchView.Anchor: CGRect] { [:] }
    static func reduce(value: inout [MatchView.Anchor: CGRect],
                       nextValue: () -> [MatchView.Anchor: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
