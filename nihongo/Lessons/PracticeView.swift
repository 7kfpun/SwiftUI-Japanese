import SwiftUI

/// The merged practice queue — Flashcards and Train were one gesture with two scorers,
/// and the resolution is that **only one scorer survives: the app**.
///
/// A left/right swipe always means *this answer*, never *I knew it*. Every card is the
/// same card — the question and two options — whatever the word's stage: a word you have
/// never met is asked like any other, because being asked is how the app finds out, and
/// the teaching lives in the reveal (miss a word and the meaning, reading and example
/// appear on the back of the same card). There is no separate teaching card to tap past.
///
/// Self-assessment is gone on purpose. It was the difference between the two old modes
/// and the thing beginners could not choose between, and it is the least reliable signal
/// available — asking "did you know that?" measures confidence, not recall. A word's
/// persisted `WordStage` (`PracticeProgress`) decides how much more proving it needs,
/// so progress carries across sessions.
///
/// Deliberately simpler than the two modes it replaces: no ordered/random switch — the
/// scheduler owns the order (persisted stages decide the workload, re-queues the
/// rhythm). The question's form pair *is* configurable (`pairCapsule`, design 5a),
/// including a Mixed draw; the Challenge ladder remains where voices alternate.
@Observable
final class PracticeModel {
    /// One entry in the queue. No `face` any more: **every card is the same card** — the
    /// word and two answers to swipe between. A word you have never met is asked like any
    /// other, because being asked is how the app finds out whether you know it, and the
    /// teaching happens in the answer rather than in a screen you tap past first.
    struct Item {
        let vocab: Vocab
    }

    /// How far back a re-queued word goes — a *window*, drawn per word, not a fixed
    /// offset. Far enough that the answer isn't still in short-term memory, near
    /// enough to come back within the same sitting.
    ///
    /// **The randomness is the point, and a fixed distance was a real bug.** Inserting
    /// every re-queue at the same offset preserves order: the quizzes then arrive in
    /// exactly the order their cards did, so a fresh lesson plays as a block of ten
    /// cards followed by a block of ten quizzes — Flashcards for a stretch, then Train
    /// for a stretch, which is the very split this mode was merged to remove. Drawing
    /// the distance per word breaks that lockstep, and card and quiz interleave from
    /// the queue keeps reaching words it has not asked yet
    /// (`PracticeTests.theQueueKeepsReachingWordsItHasNotAskedYet`).
    static let requeueWindow = 3...8

    /// Where a word goes after its **first** correct answer — much further back, because
    /// it no longer needs another look, it needs confirming.
    ///
    /// The design says this outright: 記得了 → 升到「認得」·「明天考」 — promoted, and
    /// tested *tomorrow*. Sessions here are one sitting rather than one day, so "tomorrow"
    /// becomes the far end of the queue. Re-testing a promoted word as soon as a freshly
    /// taught one is not merely early, it starves the deck: every quiz answered right
    /// inserts another quiz near the front, so the front fills with re-tests and the
    /// unseen words behind them stop being reached. Measured over 200 sessions of
    /// lesson 1, the near window ran up to 16 consecutive quizzes with no new word taught;
    /// this keeps new words coming
    /// (`PracticeTests.theQueueKeepsReachingWordsItHasNotAskedYet`).
    static let provenWindow = 18...28
    /// Two candidates, one swipe — Train's number, for Train's reason: the 50/50
    /// choice is the gentlest form of being asked.
    static let optionCount = 2

    private(set) var queue: [Item] = []
    private(set) var options: [Vocab] = []
    private(set) var picked: Int? = nil
    /// Cards graded this session, requeues included — "did anything happen here",
    /// which is the question the way-out interstitial gate asks.
    private(set) var answered = 0
    /// Words retired this session — a word retires only by a correct quiz answer.
    private(set) var retired = 0
    private(set) var sessionTotal = 0
    /// The session's total workload in correct answers, fixed at `restart()` —
    /// the denominator of `fractionDone`.
    private(set) var sessionWork = 1

    /// Correct answers a word at `stage` still owes before it retires: one from
    /// `.recognized` up (the next hit memorizes it), two below (promote, then prove).
    private static func work(_ stage: WordStage) -> Int { stage >= .recognized ? 1 : 2 }

    /// Correct answers still owed by everything left in the queue.
    private var remainingWork: Int {
        queue.reduce(0) { $0 + Self.work(progress.stage(of: $1.vocab.id)) }
    }

    /// How far through the session's workload the learner is, in [0, 1].
    ///
    /// Weighted by answers owed, not by words retired: a word needs **two** correct
    /// answers to leave the queue, so a bar drawn from `retired` sat at zero through
    /// the whole first pass of a fresh lesson — ten right answers, no movement, and it
    /// read as broken. This moves on every correct answer and dips when a wrong one
    /// demotes a word, which is exactly the story the queue is telling.
    ///
    /// `sessionWork` **ratchets** in `resolve` when a demotion grows the owed work
    /// past it. Frozen, a review lap (every word at one owed answer) that opened with
    /// a miss had `remainingWork > sessionWork`, and the clamp pinned the bar at 0%
    /// through several correct answers — the exact failure the weighting replaced.
    var fractionDone: Double {
        let total = Double(max(sessionWork, 1))
        return min(1, max(0, (total - Double(remainingWork)) / total))
    }

    let vocab: [Vocab]   // the sheet's preview needs the pool for a live distractor
    private let progress: PracticeProgress

    // MARK: - The quiz's form pair (design 5a)

    /// The three faces a quiz can show — a deliberate subset of `VForm`: romaji is a
    /// crutch this screen shouldn't reward, and audio prompts belong to the ladder's
    /// listening rungs.
    static let quizFaces: [VForm] = [.kana, .kanji, .translation]

    /// The chosen pair — what the prompt shows and what the options answer. Never
    /// equal; kana → meaning unless the learner picked otherwise in the sheet.
    private(set) var from: VForm = .kana
    private(set) var to: VForm = .translation
    /// Every quiz card draws a random valid pair instead — the sheet's third option,
    /// there to stop a whole session running on the easiest recognition direction.
    private(set) var mixed = false

    /// The pair actually asked of the *current* card: equals `from`/`to` unless mixed
    /// re-rolled it, or the word has no kanji to show — those swap the kanji slot for
    /// kana rather than skipping the word (design: kanji questions are skipped, the
    /// word is not).
    private(set) var questionFrom: VForm = .kana
    private(set) var questionTo: VForm = .translation

    var current: Item? { queue.first }
    var isDone: Bool { queue.isEmpty }
    /// A word's persisted stage, for the ladder the card draws above it.
    func stage(of word: Vocab) -> WordStage { progress.stage(of: word.id) }

    init(vocab: [Vocab], progress: PracticeProgress) {
        self.vocab = vocab
        self.progress = progress
        // `VForm.label` strings, not raw values — stable on disk however the enum
        // reorders. Unset or unrecognized reads as the kana → meaning default.
        let d = UserDefaults.standard
        if let f = Self.face(d.string(forKey: Pref.practiceFrom)) { from = f }
        if let t = Self.face(d.string(forKey: Pref.practiceTo)), t != from { to = t }
        // Half a stored pair — "meaning" as the prompt with nothing (or junk) as the
        // answer — would leave both sides on the same face: a state `setPair` refuses,
        // the sheet greys out, and `pair(for:)` would have to repair on every card.
        if from == to { from = .kana; to = .translation }
        mixed = d.bool(forKey: Pref.practiceMixed)
        restart()
    }

    private static func face(_ label: String?) -> VForm? {
        quizFaces.first { $0.label == label }
    }

    /// The sheet's commit: a fixed pair, or mixed. Re-deals the current question the
    /// way Train's form cycling did — the distractor was chosen to be distinct under
    /// the *old* pair, and with two chips a collision under the new one is fatal.
    func setPair(from f: VForm, to t: VForm, mixed m: Bool) {
        guard Self.quizFaces.contains(f), Self.quizFaces.contains(t), f != t else { return }
        from = f; to = t; mixed = m
        let d = UserDefaults.standard
        d.set(f.label, forKey: Pref.practiceFrom)
        d.set(t.label, forKey: Pref.practiceTo)
        d.set(m, forKey: Pref.practiceMixed)
        prepare()
    }

    /// Build the session from the *current* stages, so a restart after progress is a
    /// shorter queue — visible reward, never a reset.
    ///
    /// Shuffled, not stage-sorted: sorting would front-load a wall of new cards and
    /// back-load a wall of quizzes, and the mixed rhythm is the point of the merge.
    /// A lesson that is already fully memorized re-enters whole as quiz review —
    /// wrong answers still demote, which is what gives the mode a reason to reopen.
    func restart() {
        let pending = vocab.filter { progress.stage(of: $0.id) != .memorized }
        let pool = pending.isEmpty ? vocab : pending
        queue = pool.shuffled().map { word in
            Item(vocab: word)
        }
        sessionTotal = queue.count
        sessionWork = max(1, remainingWork)
        answered = 0
        retired = 0
        picked = nil
        prepare()
    }

    /// The last grade must land even though saves are debounced.
    func flush() { progress.saveNow() }

    // MARK: - Card face

    // MARK: - Quiz face

    func choose(_ i: Int) {
        guard picked == nil, options.indices.contains(i) else { return }
        picked = i
    }

    func isCorrectOption(_ i: Int) -> Bool {
        options.indices.contains(i) && options[i].id == current?.vocab.id
    }

    /// Called by the view after the verdict has been shown — the only thing that moves
    /// a word up the ladder.
    ///
    /// **One correct answer is not knowing a word.** Two options means a coin flip is
    /// right half the time, so a single hit promotes one rung rather than finishing the
    /// word: `.seen` → `.recognized`, and only a second correct answer reaches
    /// `.memorized` and retires it for the session. A wrong answer drops it to `.seen`
    /// and brings the card back to re-teach it.
    /// `credited: false` when the learner looked at the back of the card first. A right
    /// answer after reading the answer is not evidence of knowing the word, so it moves
    /// nothing up the ladder — the word simply comes back. A *wrong* answer still
    /// demotes, peek or no peek: getting it wrong with the meaning in front of you is if
    /// anything the clearer signal.
    func resolve(credited: Bool = true) {
        guard let item = current, let picked else { return }
        answered += 1
        let stage = progress.stage(of: item.vocab.id)
        if isCorrectOption(picked), !credited {
            advance(requeue: Item(vocab: item.vocab))
            return
        }
        if isCorrectOption(picked) {
            if stage >= .recognized {
                progress.set(.memorized, for: item.vocab.id)
                retired += 1
                advance(requeue: nil)
            } else {
                progress.set(.recognized, for: item.vocab.id)
                advance(requeue: Item(vocab: item.vocab), within: Self.provenWindow)
            }
        } else {
            progress.set(.seen, for: item.vocab.id)
            advance(requeue: Item(vocab: item.vocab))
            // The demotion may have grown the owed work past the session's original
            // total — see `fractionDone`.
            sessionWork = max(sessionWork, remainingWork)
        }
    }

    // MARK: - Queue

    private func advance(requeue: Item?, within window: ClosedRange<Int> = requeueWindow) {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        if let requeue {
            queue.insert(requeue, at: min(Int.random(in: window), queue.count))
        }
        picked = nil
        prepare()
    }

    private func prepare() {
        guard let item = current else { options = []; return }
        (questionFrom, questionTo) = pair(for: item.vocab)
        options = Self.options(for: item.vocab, pool: vocab,
                               from: questionFrom, to: questionTo)
    }

    /// The faces this particular word can be asked in. A word with no kanji of its own
    /// (アメリカ, わたし) has two, not three — everything else follows from that.
    static func faces(for word: Vocab) -> [VForm] {
        quizFaces.filter { $0 != .kanji || word.displaysKanji }
    }

    /// Resolve the pair for one word: a uniform draw over the combinations this word
    /// *supports* when mixed, otherwise the learner's fixed choice.
    ///
    /// **Drawn from the supported set, never rewritten into it.** The first version
    /// picked one of the six combinations and then mapped a kanji slot the word couldn't
    /// fill onto kana. That is not a repair, it is a loaded die: four of the six
    /// combinations collapse onto kana→meaning, so on a katakana-heavy lesson — where
    /// hardly any word displays kanji — "Mixed" asked the single easiest direction about
    /// two-thirds of the time, which is exactly how it was reported. Enumerating first
    /// and drawing second gives a kana-only word an even split between kana→meaning and
    /// meaning→kana, and a kanji-bearing word all six.
    func pair(for word: Vocab) -> (VForm, VForm) {
        let available = Self.faces(for: word)
        if mixed {
            let combos = available.flatMap { a in
                available.compactMap { b in a == b ? nil : (a, b) }
            }
            return combos.randomElement() ?? (.kana, .translation)
        }

        // The fixed pair, with any slot the word can't fill moved off kanji. When that
        // collapses the pair, the *degraded* side moves again — so the side the learner
        // explicitly chose is the one that survives: someone answering in kana keeps
        // answering in kana, and the prompt becomes the meaning instead.
        var f = from, t = to
        let fDegraded = !available.contains(f), tDegraded = !available.contains(t)
        if fDegraded { f = .kana }
        if tDegraded { t = .kana }
        if f == t {
            if fDegraded { f = t == .translation ? .kana : .translation }
            else { t = f == .translation ? .kana : .translation }
        }
        return (f, t)
    }

    /// `TrainModel.rebuildOptions`, generalized over the pair. A distractor must
    /// differ on **both** faces: matching the answer side makes a second right answer
    /// that would be marked wrong (shared glosses like なん/なに), matching the prompt
    /// side makes the question unanswerable (homophones).
    static func options(for answer: Vocab, pool: [Vocab],
                        from: VForm = .kana, to: VForm = .translation) -> [Vocab] {
        var opts = [answer]
        var guardCount = 0
        while opts.count < min(optionCount, pool.count), guardCount < 2000 {
            guardCount += 1
            guard let c = pool.randomElement() else { break }
            guard !opts.contains(where: { $0.id == c.id }),
                  to.value(c) != to.value(answer),
                  from.value(c) != from.value(answer) else { continue }
            opts.append(c)
        }
        return opts.shuffled()
    }
}

/// Practice — one screen, two faces; see `PracticeModel`. Chrome is the house
/// Tinder-screen set: `SwipeCard` over `CardStackPeek`, grade chips or option chips
/// below, counter capsule centered in the toolbar.
struct PracticeView: View {
    @State private var model: PracticeModel
    @Environment(\.pronouncer) private var pronouncer
    @Environment(Store.self) private var store
    @AppStorage(Pref.soundOn) private var soundOn = true
    @State private var drag: CGSize = .zero
    /// The teaching reveal — meaning, reading and example on the card, after a miss or
    /// a "not sure". Distinct from `showKana`, which is only the reading hint.
    @State private var revealed = false
    @State private var showKana = false
    /// The card is showing its back. A long press turns it over, a tap turns it back.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flipped = false
    /// Whether *this* question was peeked at. Kept separate from `flipped` because
    /// turning the card back over doesn't unsee the answer — a peek disqualifies the
    /// round from promoting, and it has to survive the card being flipped shut again.
    @State private var peeked = false
    @State private var lastCorrect: Bool? = nil
    @State private var animating = false   // guards double-grades mid-animation
    /// The pending reveal, kept so `onDisappear` can cancel it: fired on a dead view
    /// it spoke the missed word aloud over whatever screen came next.
    @State private var pendingReveal: DispatchWorkItem?
    @State private var showPairSheet = false
    private let lessonNumber: Int

    private let threshold: CGFloat = 100

    /// `progress` arrives as a parameter, not from `@Environment` — the environment
    /// isn't readable in `init`, and the model needs the stages before it deals the
    /// first card. Same reason TrainView read its preference straight from UserDefaults.
    init(lesson: Lesson, progress: PracticeProgress) {
        lessonNumber = lesson.number
        _model = State(initialValue: PracticeModel(vocab: lesson.entries, progress: progress))
    }

    var body: some View {
        VStack(spacing: 16) {
            if let item = model.current {
                // How far the session has come, as a bar rather than only a toolbar
                // counter (design 2b): a queue that re-queues its own words has no
                // obvious end, and the bar is what says one is coming.
                sessionBar
                statusRow(item)

                // One card, always the same shape: the word, and two answers under it
                // to swipe between. There is no step to tap past before being asked —
                // being asked is how the mode finds out what you know, and what you
                // didn't know is taught in the answer instead (see `revealed`).
                //
                // The card is the flexible element — chips and the Next button keep
                // the stack's own 16pt rhythm under it. A `Spacer` between them let
                // Next drift to the screen's floor, a tab bar's height from the
                // answers it follows.
                topCard(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                optionRow
                // Only after a miss, and only as the way forward. The way to *see* a
                // word without answering is to hold the card — a button saying the same
                // thing was a second door to one room.
                if revealed { continueButton }
            } else {
                congrats
            }
        }
        .padding()
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if let lastCorrect { AnswerBadge(correct: lastCorrect) } }
        .toolbar {
            // No counter in the toolbar. It read "✓0 · 45 / 45" and stayed there: two of
            // its three numbers were the *queue*, which barely shrinks in a mode that
            // re-queues almost everything it asks, so the one figure that moves was
            // buried between two that don't. The bar under it carries the same fact, and
            // the number that belongs beside a bar is the one going up.
            FlagAndSoundToolbar(item: model.current.map {
                Feedback.Item(lesson: $0.vocab.lesson, romaji: $0.vocab.romaji)
            })
        }
        .sheet(isPresented: $showPairSheet) {
            PracticePairSheet(model: model, lesson: lessonNumber)
                .presentationDetents([.medium, .large])
                // The denominator for `practice_pair`: opened-then-left-alone was
                // invisible, so the commit rate had nothing under the line.
                .onAppear { Track.event("practice_pair_open",
                                        ["lesson": lessonNumber, "mixed": model.mixed]) }
        }
        .onAppear {
            autoPlay()
            Track.screen("practice", ["lesson": lessonNumber])
            ModeVisits.mark(lesson: lessonNumber, mode: "practice")
            if !store.isPremium { Ads.preloadInterstitial() }
        }
        // A popup ad on the way out — non-premium only, throttled — and the last
        // stage write flushed past the save debounce.
        .onDisappear {
            // The reveal may still be pending; fired on a dead view it spoke the
            // missed word over the next screen.
            pendingReveal?.cancel()
            pendingReveal = nil
            // Any answered card is graded on the way out — `revealed` alone missed the
            // 0.6s window between a wrong swipe and its reveal, where leaving skipped
            // the demotion entirely. `resolve` guards on `picked`, so an unanswered
            // card grades nothing (a correct answer's fling resolves within 0.25s and
            // clears `picked`, so it can't be double-graded here).
            if model.picked != nil { model.resolve(credited: !peeked) }
            model.flush()
            // `answered`, not queue arithmetic: a re-queue removes and re-inserts one
            // item, so `sessionTotal - queue.count + retired` collapsed to 2×retired —
            // thirty answers with nothing memorized showed no ad, which is a throttle
            // on the wrong axis. Match uses `attempts > 0` for the same gate.
            if !store.isPremium && model.answered > 0 {
                Ads.showInterstitialIfReady()
            }
        }
    }

    // MARK: - The card

    /// One card, whatever the word's stage: the question, the word, and — once answered
    /// or given up on — what it means.
    ///
    /// The reveal is where teaching lives now. There is no separate card to tap past
    /// before being asked: a word you have never met is asked like any other, and if you
    /// miss it (or say you're not sure) the meaning, the reading and the example appear
    /// on the same card. Learning the word is the *consequence* of not knowing it rather
    /// than a screen served in advance and skimmed.
    private func topCard(_ item: PracticeModel.Item) -> some View {
        // A swipe picks a side: the arrows point at the two option chips. No peek layers
        // and no "⟨ Swipe ⟩" hint — the direction is spelled out under each answer, and a
        // stack would imply a deck to flip through rather than a question to settle.
        SwipeCard(drag: drag, threshold: threshold,
                  leftStamp: ("arrow.left", Theme.accent),
                  rightStamp: ("arrow.right", Theme.accent),
                  showsStamps: model.picked == nil && !flipped,
                  showsHint: false) {
            ZStack {
                cardBack(item).opacity(flipped ? 1 : 0)
                cardFront(item).opacity(flipped ? 0 : 1)
            }
        }
        // A real turn, not a crossfade: the meaning is *on the back of this card*, and
        // the rotation is what says so — which is the whole reason a flashcard has a
        // back at all. Reduce Motion gets the same information without the spin.
        .rotation3DEffect(.degrees(flipped && !reduceMotion ? 180 : 0),
                          axis: (x: 0, y: 1, z: 0))
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.45),
                   value: flipped)
        .onTapGesture { pronouncer.speak(item.vocab) }
        // **Hold to look, release to turn back.** A press-and-hold rather than a toggle,
        // because a peek should cost you something to keep — holding the card over is a
        // thing you stop doing, where a flipped card would just sit there answered. It
        // also leaves the tap free to speak the word and needs no fourth control under a
        // question that already has two answers and a way out.
        .onLongPressGesture(minimumDuration: CardFlip.hold) {
            guard !revealed, model.picked == nil else { return }
            if !peeked {
                peeked = true
                Track.event("practice_peek", ["lesson": lessonNumber])
            }
            withAnimation { flipped = true }
        } onPressingChanged: { pressing in
            if !pressing, flipped { withAnimation { flipped = false } }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: flipped)
        .gesture(quizDrag)
    }

    /// The back: what the front is asking about. Mirrored so it reads the right way
    /// round once the card has turned.
    private func cardBack(_ item: PracticeModel.Item) -> some View {
        VStack(spacing: 0) {
            // Top corner, where the front keeps its caption — the consequence of
            // peeking is a caption on the card, not a footnote under the answer, and
            // the learner should read it on the way in rather than on the way out.
            Text(L.t("Peeked — this one comes back"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            // No "release to turn back": the finger is already holding the card down,
            // so the instruction describes what stopping would do — which the learner
            // finds out by stopping.
            VocabFace(vocab: item.vocab,
                      speakExample: {
                          pronouncer.speak(example: item.vocab)
                          Track.event("play_example", ["lesson": lessonNumber,
                                                       "surface": "practice"])
                      })

            Spacer(minLength: 12)
        }
        .padding(20)
        .frame(minHeight: 230)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
    }

    private func cardFront(_ item: PracticeModel.Item) -> some View {
        VStack(spacing: 0) {
            // Pinned to the top corner, not floated above the word. In a centred stack
            // the label rode up and down with however tall the prompt happened to be,
            // so it read as part of the question rather than as the question's caption.
            if !revealed {
                Text(promptLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 12)

            if revealed {
                // The teaching moment **replaces** the question rather than stacking
                // under it. `VocabFace` already carries every form of the word — the
                // prompt included — so keeping the 44pt question above it repeated the
                // word and pushed the face past the card's top edge, prompt label
                // bleeding out over the corner.
                VocabFace(vocab: item.vocab,
                          speakExample: {
                              pronouncer.speak(example: item.vocab)
                              Track.event("play_example", ["lesson": lessonNumber,
                                                           "surface": "practice"])
                          })
                .transition(.opacity)
            } else {
            // No speaker button: tapping the card already speaks the word, and a
            // control that duplicates the surface it sits on is one more thing to aim
            // past. The toolbar's toggle governs whether it speaks by itself.
            Text(model.questionFrom.value(item.vocab))
                .font(model.questionFrom.promptFont(wordSize: 44, translationStyle: .largeTitle))
                .multilineTextAlignment(.center)
                // A word can shrink hard; a translation can run to a sentence, and
                // 0.35 of `.largeTitle` is 11.9pt — same floors as Train.
                .minimumScaleFactor(model.questionFrom == .translation ? 0.6 : 0.35)
            }

            if !revealed, model.questionFrom == .kanji {
                // The reading, on request. A kanji prompt is unanswerable to someone
                // who can't yet read it, and the honest fix is a hint rather than a
                // wrong answer — this is practice, and nothing here is scored.
                Button {
                    Track.event("practice_show_kana", ["lesson": lessonNumber])
                    withAnimation(.easeOut(duration: 0.15)) { showKana = true }
                } label: {
                    Label(showKana ? item.vocab.kana : L.t("Show kana"),
                          systemImage: showKana ? "text.book.closed" : "eye")
                        .font(showKana ? Theme.jp(18) : .subheadline)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Theme.canvas, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(showKana)
                .padding(.top, 12)
            }

            Spacer(minLength: 12)

            // The gesture is invisible until someone tries it, and nothing else on the
            // card suggests there *is* a back. Named for what it gets you — the details
            // — rather than for the mechanic, since "flip the card" only means something
            // once you already know what is on the other side.
            if !revealed {
                Text(L.t("Long-press to see details"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(minHeight: 230)
    }

    /// Forward, once the word has been taught. Replaces the auto-advance for the cases
    /// that need reading time — a miss, or a "not sure" — while a correct answer still
    /// moves on by itself, because there is nothing there to read.
    private var continueButton: some View {
        PrimaryPillButton(action: advanceAfterReveal) {
            HStack(spacing: 8) {
                Text(L.t("Next"))
                Image(systemName: "arrow.right")
            }
            .font(Theme.title(.headline))
        }
    }

    /// One line: where this word stands on the left, what the quizzes ask on the right.
    ///
    /// A plain `HStack` now that the ladder is a readout rather than three pills — the
    /// pair was wide enough before that it needed a `ViewThatFits` fallback to a second
    /// row, which is complexity the layout no longer earns.
    private func statusRow(_ item: PracticeModel.Item) -> some View {
        HStack(spacing: 10) {
            StageLadder(stage: model.stage(of: item.vocab))
            Spacer(minLength: 8)
            pairCapsule
        }
    }

    /// Session progress. The bar is `fractionDone` — answer-weighted, so it moves on
    /// every correct answer instead of waiting for a word's second (see the model);
    /// the printed count stays `retired`, the number the mode is actually about.
    private var sessionBar: some View {
        HStack(spacing: 10) {
            CapsuleBar(fraction: model.fractionDone, height: 4, track: Theme.line)

            // The same measure as the bar, in numerals. "0 / 48 memorized" was the
            // honest count and read as a frozen one — a word needs two correct answers
            // to count, so ten right answers still printed 0. One number, moving with
            // every answer, and no localization to drift (numerals and a percent sign).
            Text("\(Int((model.fractionDone * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((model.fractionDone * 100).rounded()))%")
    }

    private var optionRow: some View {
        HStack(spacing: 12) {
            optionChip(side: 0)
            optionChip(side: 1)
        }
    }

    /// What the current question asks, in words. Mirrors `ChallengeView.promptLabel`,
    /// which poses the same question shapes on the scored side.
    private var promptLabel: String {
        if model.questionFrom == .translation { return L.t("Which word means this?") }
        if model.questionTo == .kanji { return L.t("Which kanji writes this reading?") }
        // Kanji → kana: the chips are readings, not meanings. Unlike the ladder — whose
        // forms never pair those two — Practice offers it in the sheet and deals it
        // under Mixed, and it was inheriting "What does this word mean?".
        if model.questionTo == .kana { return L.t("How is this kanji read?") }
        return L.t("What does this word mean?")
    }

    /// The face follows the answer's script, like the kana swipe quiz: Japanese on
    /// `Theme.jp`, prose on the system font.
    private func optionChip(side: Int) -> some View {
        let opt = model.options.indices.contains(side) ? model.options[side] : nil
        return SwipeOptionChip(text: opt.map { model.questionTo.value($0) } ?? "",
                               side: side,
                               picked: model.picked,
                               isAnswer: opt?.id == model.current?.vocab.id,
                               font: model.questionTo.isJapanese ? Theme.jp(24)
                                                                 : .title3.weight(.semibold),
                               // The chevron says which way; this says it in words, for
                               // the first run before the gesture is learned (design 2b).
                               hint: side == 0 ? L.t("Swipe left") : L.t("Swipe right")) { decide(side) }
    }

    /// The capsule naming the current pair — or the shuffle, when mixed. Tapping opens
    /// the sheet; disabled mid-answer so the pair can't change under a shown verdict.
    private var pairCapsule: some View {
        Button { showPairSheet = true } label: {
            HStack(spacing: 6) {
                if model.mixed {
                    Image(systemName: "shuffle")
                    Text(L.t("Mixed"))
                } else {
                    Text(PracticePairSheet.name(model.from))
                    Image(systemName: "arrow.right")
                    Text(PracticePairSheet.name(model.to))
                }
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .disabled(model.picked != nil)
    }

    // MARK: - Gestures

    private var quizDrag: some Gesture {
        CardSwipe.gesture(drag: $drag, threshold: threshold,
                          canDrag: { model.picked == nil && !animating && !revealed && !flipped },
                          canCommit: { !flipped },
                          decide: { decide($0 ? 1 : 0) })
    }

    // MARK: - Flow

    /// Leaving a card the learner has just been taught. The miss that opened the reveal
    /// is graded *here* — after the card has played out — so the word being read about
    /// stays on screen the whole time it is being read (see `decide`).
    private func advanceAfterReveal() {
        guard !animating else { return }
        animating = true
        CardSwipe.fling($drag, toRight: true) {
            model.resolve(credited: !peeked)
            afterAdvance()
        }
    }

    /// An answer. Right and wrong end differently on purpose: a correct answer has
    /// nothing to read, so it plays its badge and moves on; a **wrong** one opens the
    /// card to show the meaning, the reading and the example, and waits. That reveal is
    /// where a word actually gets taught, and it lands on the card that just proved it
    /// was needed rather than on a screen shown before anything was asked.
    private func decide(_ side: Int) {
        guard !animating, model.picked == nil, !revealed, !flipped,
              model.options.count > side else { return }
        animating = true
        model.choose(side)
        let correct = model.isCorrectOption(side)
        // `from`/`to` ride along like they did on Train and still do on the ladder:
        // an answer in kana→meaning is not the same exercise as meaning→kanji, and
        // without the pair the correct rate averages exercises into a number that
        // describes none. Both are `VForm.label` — stable ASCII, never localized text.
        Track.event("practice_answer", ["correct": correct, "lesson": lessonNumber,
                                        "from": model.questionFrom.label,
                                        "to": model.questionTo.label])
        withAnimation(.spring(duration: 0.2)) { lastCorrect = correct }
        if correct {
            // A longer wait than the exit itself, so the verdict badge reads first.
            CardSwipe.fling($drag, toRight: side == 1, then: 0.5) {
                // A right answer after reading the back proves nothing — see
                // `PracticeModel.resolve(credited:)`.
                model.resolve(credited: !peeked)
                withAnimation(.spring) { lastCorrect = nil }
                afterAdvance()
            }
        } else {
            // **Resolved on the way out, not here.** `resolve` grades *and* pops the
            // queue, so calling it now swapped the card to the next word before the
            // reveal opened: the meaning, the example and the spoken word all belonged
            // to a question the learner hadn't been asked yet, the chips lost their
            // verdict (`picked` goes nil), and "Next" then re-asked the word whose
            // answer had just been shown. Holding the card keeps `picked` set — so the
            // right chip stays marked — and `advanceAfterReveal` does the grading.
            let reveal = DispatchWorkItem {
                pendingReveal = nil
                withAnimation(.spring) { lastCorrect = nil }
                withAnimation(.easeOut(duration: 0.2)) { revealed = true }
                drag = .zero
                animating = false
                // The word just missed, said aloud while its meaning is on screen.
                if soundOn, let word = model.current?.vocab { pronouncer.speak(word) }
            }
            pendingReveal = reveal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: reveal)
        }
    }

    private func afterAdvance() {
        revealed = false
        showKana = false
        flipped = false
        peeked = false
        drag = .zero
        animating = false
        if model.isDone {
            Track.event("practice_done", ["total": model.sessionTotal, "lesson": lessonNumber])
        } else {
            autoPlay()   // explicit: a re-queued word can repeat, so no onChange
        }
    }

    /// Speaks only when hearing the word doesn't answer the question — a meaning prompt
    /// with word options, or a kana *answer*, would both be given away
    /// (`VForm.promptAudioSafe(from:to:)`).
    private func autoPlay() {
        guard soundOn, let item = model.current,
              VForm.promptAudioSafe(from: model.questionFrom, to: model.questionTo)
        else { return }
        pronouncer.speak(item.vocab)
    }

    // MARK: - Chrome

    private var congrats: some View {
        DeckDonePanel(summary: L.t("You reviewed %@ words", "\(model.sessionTotal)")) {
            Track.event("practice_restart", ["lesson": lessonNumber,
                                             "total": model.sessionTotal])
            withAnimation { model.restart(); revealed = false; drag = .zero }
            autoPlay()
        }
    }
}

/// Where a word stands on the Practice ladder: three dots and the name of the rung it
/// is on.
///
/// This was three labelled pills with connectors between them — roughly 250pt of
/// furniture for one fact, which pushed the pair control onto a second line in most
/// languages and read as a control the learner was meant to operate. It isn't one; it
/// is a status. The dots carry the progression (filled up to the current rung, the way
/// `StageDot` marks a word in the vocab list) and only the rung you are actually on is
/// named, so the whole thing is about a third of the width and unmistakably a readout.
struct StageLadder: View {
    let stage: WordStage

    private var rung: Int {
        switch stage {
        case .unseen, .seen: return 1
        case .recognized:    return 2
        case .memorized:     return 3
        }
    }

    private var title: String {
        switch stage {
        case .unseen:     return L.t("First time")
        case .seen:       return L.t("Seen")
        case .recognized: return L.t("Recognized")
        case .memorized:  return L.t("Memorized")
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 3) {
                ForEach(1...3, id: \.self) { i in
                    Circle()
                        .fill(i <= rung ? Theme.accent : Theme.line)
                        .frame(width: 6, height: 6)
                }
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(rung) of 3")
    }
}

/// The quiz-pair sheet (design 5a): two rows — what the prompt shows, what the
/// options answer — with the same face greyed on the opposite row, a mixed option,
/// and a live preview so the choice is seen as it is made. Two rows instead of the
/// 3×3 matrix the design also drew: the matrix asks the reader to parse axes, the
/// rows read as a sentence.
///
/// **Every tap commits.** There is no confirm button: the sheet holds three switches,
/// not a form, and each one is instantly reversible by tapping another chip. A commit
/// step would ask the learner to confirm a choice whose entire result — the preview
/// card below — is already on screen. The sheet stays open afterwards so the other row
/// can be set too, and closes by swipe like any other detented sheet.
struct PracticePairSheet: View {
    let model: PracticeModel
    private let lessonNumber: Int

    init(model: PracticeModel, lesson: Int) {
        self.model = model
        self.lessonNumber = lesson
    }

    /// The three faces by their on-screen names. `VForm.label` stays the analytics
    /// key; these are what the learner reads.
    static func name(_ f: VForm) -> String {
        switch f {
        case .kana: return L.t("Kana")
        case .kanji: return L.t("Kanji")
        case .translation: return L.t("Meaning")
        default: return f.label
        }
    }

    /// A word with a kanji face, so every pair previews meaningfully.
    private var sample: Vocab? {
        model.vocab.first { $0.displaysKanji } ?? model.vocab.first
    }

    /// Deterministic, unlike the real deal: the first pool word valid under the
    /// distractor rule. A re-rolled random one would flicker on every render.
    private func distractor(beside answer: Vocab) -> Vocab? {
        model.vocab.first {
            $0.id != answer.id && model.from.value($0) != model.from.value(answer)
                && model.to.value($0) != model.to.value(answer)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("How to quiz this lesson"))
                        .font(Theme.title(.title3))
                    Text(L.t("Pick what you see and what you answer"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                faceRow(L.t("You see"), selected: model.from, other: model.to) { face in
                    commit(from: face, to: model.to)
                }
                faceRow(L.t("You answer"), selected: model.to, other: model.from) { face in
                    commit(from: model.from, to: face)
                }

                mixedCard

                if let sample {
                    preview(sample)
                }
            }
            .padding(20)
        }
        // A results card is a fixed shape, not a document —
        // the bar sat over the content and reported a position nobody needed.
        .scrollIndicators(.hidden)
        .presentationDragIndicator(.visible)
    }

    /// One row of face chips. The face held by the *other* row is greyed, not
    /// swapped — the design's rule, and less surprising than a selection that moves
    /// something the learner didn't touch.
    private func faceRow(_ title: String, selected: VForm, other: VForm,
                         pick: @escaping (VForm) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(PracticeModel.quizFaces, id: \.self) { f in
                    faceChip(f, selected: !model.mixed && selected == f,
                             disabled: f == other) { pick(f) }
                }
            }
        }
        // Dimmed rather than hidden while mixed is on: the pair is still what the
        // rows say it is, it just isn't what the next card will use.
        .opacity(model.mixed ? 0.5 : 1)
    }

    private func faceChip(_ f: VForm, selected: Bool, disabled: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(Self.name(f))
                .font(.subheadline.weight(.medium))
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Selection is an accent border, never a fill — the house rule.
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 1))
        .opacity(disabled ? 0.35 : 1)
        .disabled(disabled)
    }

    private var mixedCard: some View {
        Button {
            commit(from: model.from, to: model.to, mixed: true)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .frame(width: 30)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("Mixed")).font(Theme.title(.headline))
                    Text(L.t("Each card picks a combination at random"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(L.t("Words without kanji skip kanji questions automatically"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(model.mixed ? Theme.accent : Theme.line, lineWidth: model.mixed ? 2 : 1))
    }

    /// The live preview: the chosen pair applied to a real word from this lesson,
    /// beside a real distractor — what the next quiz card will actually look like.
    /// Under Mixed it is one example of several, and says so.
    private func preview(_ sample: Vocab) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.mixed ? L.t("One example — each card varies")
                             : L.t("The card will look like this"))
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 14) {
                Text(model.from.value(sample))
                    .font(model.from.promptFont(wordSize: 30, translationStyle: .title3))
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    previewChip(model.to.value(sample))
                    if let d = distractor(beside: sample) {
                        previewChip(model.to.value(d))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        }
    }

    private func previewChip(_ text: String) -> some View {
        Text(text)
            .font(model.to.isJapanese ? Theme.jp(15) : .footnote)
            .minimumScaleFactor(0.6)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.horizontal, 8)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }

    /// Apply and record. Tapping a face always leaves Mixed, since naming a direction
    /// is the opposite of asking for a random one. Logged only when something actually
    /// moved — re-tapping the selected chip is a no-op, and counting it overstated how
    /// often the pair is changed.
    private func commit(from: VForm, to: VForm, mixed: Bool = false) {
        let changed = model.questionFrom != from || model.questionTo != to
                      || model.mixed != mixed
        withAnimation(.easeOut(duration: 0.15)) {
            model.setPair(from: from, to: to, mixed: mixed)
        }
        guard changed else { return }
        Track.event("practice_pair", ["from": from.label, "to": to.label,
                                      "mixed": mixed, "lesson": lessonNumber])
    }
}

