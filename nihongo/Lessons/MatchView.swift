import SwiftUI

/// Endless pair-matching over a lesson's vocabulary: five words down the left, their five
/// meanings shuffled down the right, tap one from each side to clear the pair. Clear all
/// five and the next five deal themselves — like Train it never ends, because this is
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
    /// Words not yet dealt in this pass, shuffled — the same bag `TrainModel` uses, and
    /// for the same reason: independent random draws re-deal words you just saw while
    /// others never appear at all.
    private var bag: [Vocab] = []

    init(vocab: [Vocab]) {
        self.vocab = vocab
        deal()
    }

    func word(id: String) -> Vocab? { round.first { $0.id == id } }

    /// Tap a tile. Ignored while a miss is showing, on a tile already cleared, and in
    /// the gap between the last match and the next deal.
    func pick(side: Side, index: Int) {
        guard !wrong, !roundCleared else { return }
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(model.left, side: .left)
            column(model.right, side: .right)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScoreBadge(correct: model.matched, total: model.attempts)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                SoundToggle()
            }
        }
        .onAppear {
            Track.screen("match", ["lesson": lessonNumber])
            if !store.isPremium { Ads.preloadInterstitial() }
        }
        .onDisappear {
            if !store.isPremium, model.attempts > 0 { Ads.showInterstitialIfReady() }
        }
        // The miss flash lives here rather than in the model: long enough to see which
        // two tiles were wrong, short enough that it never feels like a penalty.
        .onChange(of: model.wrong) {
            guard model.wrong else { return }
            Track.event("match_answer", ["lesson": lessonNumber, "correct": false])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeOut(duration: 0.15)) { model.clearMiss() }
            }
        }
        // The green moment. Keyed on `matched` (a count) rather than `lastMatched` (an
        // id), because the last pair of one round and the first of the next could be the
        // same word — an id that doesn't change wouldn't re-fire.
        .onChange(of: model.matched) {
            guard let id = model.lastMatched else { return }
            Track.event("match_answer", ["lesson": lessonNumber, "correct": true])
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
                    withAnimation(.easeOut(duration: 0.25)) { model.dealNext() }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.matched)
    }

    /// Tiles split the column's full height between them, so five pairs own the page
    /// instead of huddling under the toolbar — and the tap targets grow with the screen,
    /// which suits a mode that is entirely tapping.
    private func column(_ tiles: [MatchModel.Tile], side: MatchModel.Side) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                tileButton(tile, side: side, index: index)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .frame(minHeight: 44)
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
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
        // Cleared pairs stay in place rather than collapsing: tiles that reflow under
        // your thumb make the next tap land on something you didn't aim at. They keep
        // their footprint and fade — but not while their green moment is still showing.
        .opacity(tile.cleared && !flashing ? 0.2 : 1)
        .animation(.easeOut(duration: 0.2), value: tile.cleared)
        .accessibilityLabel(tile.text)
        .accessibilityHint(tile.cleared ? L.t("Complete!") : "")
    }
}
