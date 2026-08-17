import SwiftUI
import SwiftData

/// One run of a challenge: a bounded set of questions, then a result screen.
///
/// Deliberately unlike `TrainView`, which is an open-ended practice loop with
/// user-switchable forms and no ending. Here the questions, their forms and their
/// order are all fixed up front by `ChallengeModel`, because a score only means
/// something if the run is the same shape every time.
struct ChallengeView: View {
    @State private var model: ChallengeModel
    @Environment(\.pronouncer) private var pronouncer
    @Environment(\.modelContext) private var context
    @Environment(Store.self) private var store
    @Environment(Unlock.self) private var unlock
    @AppStorage(Pref.soundOn) private var soundOn = true
    @State private var recorded = false
    @State private var showRating = false
    @State private var showFeedback = false
    @State private var showSharePrompt = false
    /// Raised after the nudge dismisses — see `ShareSheetPrompt`, which can't present the
    /// system share sheet from a view that is already going away.
    @State private var showShareSheet = false
    /// What the star row returned, or nil if it was dismissed without an answer.
    @State private var ratedStars: Int?
    /// The same number, kept for the feedback sheet to carry. Separate because
    /// `routeRating` clears `ratedStars` as it consumes it, and the sheet is built after.
    @State private var feedbackStars = 0

    private let lesson: Lesson
    private let index: Int
    private let total: Int

    init(lesson: Lesson, index: Int, total: Int) {
        self.lesson = lesson
        self.index = index
        self.total = total
        _model = State(initialValue: Self.makeModel(lesson: lesson, index: index, total: total))
    }

    private static func makeModel(lesson: Lesson, index: Int, total: Int) -> ChallengeModel {
        ChallengeModel(lessonNumber: lesson.number, index: index, total: total, words: lesson.entries)
    }

    /// Start a fresh run: new questions, new order, cleared score.
    ///
    /// Also the fix for re-entering a finished challenge. `@State`'s initial value is
    /// only used once per view identity, and re-pushing the same `NavigationLink` row
    /// reuses that identity — so without this you'd return to the previous run's
    /// result screen with no way to play again.
    private func restart() {
        model = Self.makeModel(lesson: lesson, index: index, total: total)
        recorded = false
    }

    var body: some View {
        VStack(spacing: 16) {
            if let question = model.question {
                progressBar
                prompt(question)
                OptionGrid(count: question.options.count) { i in
                    QuizOptionButton(text: question.to.value(question.options[i]),
                                     index: i,
                                     picked: model.picked,
                                     isAnswer: question.isCorrect(i)) {
                        model.choose(i)
                        // One `answer` event per selection, the same shape every practice
                        // surface logs. `from`/`to` because the ladder's whole design is
                        // forms hardening as you climb — per-form accuracy is the readout.
                        // No word id or text: the answer stream is volume, not content.
                        Track.event("answer", ["screen": "challenge",
                                               "lesson": lesson.number,
                                               "index": model.index,
                                               "from": question.from.label,
                                               "to": question.to.label,
                                               "correct": question.isCorrect(i)])
                        if soundOn || question.from.isAudio { pronouncer.speak(question.answer, voice: question.voice) }
                    }
                }
                nextButton
            } else {
                ChallengeResultView(model: model, lesson: lesson, total: total, retry: restart)
            }
        }
        .padding()
        .background(Theme.canvas)
        .navigationTitle(L.t("Challenge %@", "\(model.index)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The flag appears only once the question has been answered, and that gate is
            // the point: the sheet shows the sender the entry their report is about, so a
            // flag offered mid-question would name the answer to a scored question. After
            // the pick, `QuizOptionButton` has already marked the right option — nothing is
            // given away, and "wait, that meaning is wrong" is exactly the moment it lands.
            //
            // A `.sheet`, so this view stays in the hierarchy while a report is written:
            // `onDisappear` below logs `challenge_abandon` and fires the exit interstitial,
            // and neither may happen because someone reported a word mid-run.
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let question = model.question, model.picked != nil {
                    ReportItemButton(item: Feedback.Item(lesson: question.answer.lesson,
                                                         romaji: question.answer.romaji))
                }
                SoundToggle()
            }
        }
        .onAppear {
            // Coming back to a run that already ended means the view was reused —
            // start over rather than stranding the user on an old result screen.
            if model.isDone { restart() }
            autoPlay()
            Track.screen("challenge", ["lesson": lesson.number, "index": index])
            Track.event("challenge_start", ["lesson": lesson.number, "index": index,
                                            "questions": model.questions.count])
            if !store.isPremium { Ads.preloadInterstitial() }
        }
        .onChange(of: model.current) { autoPlay() }
        .onChange(of: model.isDone) { if model.isDone { finish() } }
        .onDisappear {
            // Left mid-run. `challenge_start` minus `challenge_complete` would give the
            // count, but not the shape: `question` says *where* people bail — question 2
            // is a difficulty wall, question 9 is fatigue or an interruption, and those
            // want opposite fixes.
            if !model.isDone && model.current > 0 {
                Track.event("challenge_abandon", ["lesson": lesson.number,
                                                  "index": index,
                                                  "question": model.current + 1,
                                                  "of": model.questions.count,
                                                  "correct": model.correct])
            }
            // A popup ad on the way out — non-premium only, throttled. Never mid-run.
            if !store.isPremium && model.isDone { Ads.showInterstitialIfReady() }
        }
        // Routed from `onDismiss`, not from the star tap. Both destinations replace the
        // star row — Apple's review sheet and the feedback sheet each need the screen to
        // themselves — and asking to present either while this one is still animating
        // away is silently dropped. `onDismiss` runs once it's actually gone.
        .sheet(isPresented: $showRating, onDismiss: routeRating) {
            RatingSheet { ratedStars = $0 }
        }
        // The stars come along, so the complaint can be read next to the rating that
        // produced it. `feedbackStars` rather than `ratedStars`, which `routeRating` has
        // already cleared by the time this sheet is built.
        .sheet(isPresented: $showFeedback) {
            FeedbackView(source: .rating, stars: feedbackStars)
        }
        // The earned unlock, celebrated where it was won. A sheet rather than a toast:
        // this is the rarest thing that happens in the app and the only reward that
        // isn't a number, so it gets the screen for a moment.
        .sheet(isPresented: Binding(get: { unlock.justEarned },
                                    set: { if !$0 { unlock.acknowledge() } })) {
            EarnedUnlockCard(band: unlock.bandName, through: unlock.bandLast) {
                unlock.acknowledge()
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSharePrompt) {
            ShareSheetPrompt { showShareSheet = true }
        }
        // The system share sheet, raised only after the nudge has gone. `.shareSheet` is
        // this app's wrapper; the modifier form is used rather than a `ShareLink` because
        // the trigger is a button inside a sheet that no longer exists by then.
        .shareSheet(isPresented: $showShareSheet,
                    items: [SharePrompt.appStoreURL, SharePrompt.shareText()])
    }

    /// Persist the result once. Guarded because `isDone` can re-fire on redraws and a
    /// second call would inflate the attempt count.
    private func finish() {
        guard !recorded else { return }
        recorded = true
        ChallengeResult.record(lesson: lesson.number, index: model.index,
                               score: model.scorePercent, context: context)
        Track.event("challenge_complete", ["lesson": lesson.number,
                                           "index": model.index,
                                           "score": model.scorePercent,
                                           "stars": model.stars,
                                           "passed": model.passed])
        // Before the prompts: this rung may have completed the sweep, and an unlock the
        // learner just earned outranks anything we want from them.
        unlock.refresh(context: context)
        if unlock.justEarned {
            Track.event("earned_first_group", ["lesson": lesson.number, "index": model.index])
            return   // the celebration is the only thing on screen this time
        }

        // Order matters and is the whole point: the rating gets first refusal, and the
        // share nudge only runs if it declined. Two sheets stacked on one passed rung
        // reads as begging, and Apple rate-limits the rating to a handful a year while
        // this one comes back next month regardless.
        let asked = askForRatingIfEarned()
        if !asked { askForShareIfEarned() }
    }

    /// A just-passed rung is the one moment the app is unambiguously working, so it's
    /// where the ask goes — subscribers only, and once. Deferred a beat so the result
    /// screen is on screen behind the sheet rather than appearing under it.
    /// Returns whether it took the occasion, so the share nudge knows to stand down.
    @discardableResult
    private func askForRatingIfEarned() -> Bool {
        let passedCount = ChallengeResult.totalPassed(context: context)
        guard RatingPrompt.shouldAsk(isPremium: store.isPremium,
                                     passed: model.passed,
                                     passedCount: passedCount) else { return false }
        RatingPrompt.markAsked()
        Track.event("rating_shown", ["lesson": lesson.number, "passed_total": passedCount])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showRating = true }
        return true
    }

    /// The once-a-month "tell a friend". Same moment as the rating and the same deferral,
    /// but open to free users too — someone recommending a lesson they got for free is
    /// exactly who this is for.
    private func askForShareIfEarned() {
        let passedCount = ChallengeResult.totalPassed(context: context)
        guard SharePrompt.shouldAsk(passed: model.passed,
                                    passedCount: passedCount,
                                    ratingShown: false) else { return }
        SharePrompt.markAsked()
        Track.event("share_prompt_shown", ["lesson": lesson.number, "passed_total": passedCount])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showSharePrompt = true }
    }

    /// Where the stars lead, run once the star row has finished dismissing.
    ///
    /// 4★ and up hands off to Apple's native review sheet. Anything lower opens the
    /// in-app feedback sheet, where the complaint reaches someone who can answer it
    /// instead of becoming a public one-liner. Dismissing without picking leads nowhere,
    /// which is the point of offering "Not now" at all.
    ///
    /// The `survey_rating` row is written *before* the branch and on neither arm, so the
    /// star is captured whatever happens next — see `Survey.Rating`. It changes no routing:
    /// every answer still leads exactly where it did, which is what keeps this the app's
    /// own question rather than a rating gate (see `RatingPrompt`).
    private func routeRating() {
        guard let stars = ratedStars else {
            Track.event("rating_dismissed", ["lesson": lesson.number])
            return
        }
        ratedStars = nil
        Track.event("rating_given", ["stars": stars, "lesson": lesson.number, "index": index])
        Survey.submit(Survey.Rating(stars: stars),
                      context: Survey.Context(store: store, modelContext: context))
        if stars >= 4 {
            RatingPrompt.requestAppStoreReview()
        } else {
            feedbackStars = stars
            showFeedback = true
        }
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(model.current + 1) / \(model.questions.count)")
                Spacer()
                ScoreBadge(correct: model.correct, total: model.current + (model.picked == nil ? 0 : 1))
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            ProgressView(value: Double(model.current), total: Double(max(model.questions.count, 1)))
                .tint(Theme.accent)
        }
    }

    /// A big speaker for audio prompts, the word itself otherwise. Tapping replays.
    private func prompt(_ q: ChallengeQuestion) -> some View {
        Group {
            if q.from.isAudio {
                VStack(spacing: 12) {
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 64))
                    Text(L.t("Hear it, pick the word"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .foregroundStyle(Theme.accent)
            } else {
                Text(q.from.value(q.answer))
                    .font(q.from.promptFont(wordSize: 38, translationStyle: .title))
                    .multilineTextAlignment(.center)
                    // Rung 2 onward asks meaning→Japanese, so this slot holds a full
                    // translation — which needs the inset (a word never reached the card's
                    // edge, a sentence does) and a floor that stays readable.
                    .minimumScaleFactor(q.from == .translation ? 0.6 : 0.5)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { pronouncer.speak(q.answer, voice: q.voice) }
    }

    private var nextButton: some View {
        Button { model.advance() } label: {
            Text(model.isLastQuestion ? L.t("Finish") : L.t("Next"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.picked == nil)
    }

    /// Audio questions must always speak — the clip *is* the question, so the sound toggle
    /// can't silence them. Everything else respects the toggle, and which prompts may speak
    /// at all is `TrainModel.promptAudioSafe`'s rule, shared so the two quizzes can't drift.
    private func autoPlay() {
        guard let q = model.question else { return }
        if q.from.isAudio { pronouncer.speak(q.answer, voice: q.voice) }
        else if soundOn, TrainModel.promptAudioSafe(from: q.from) { pronouncer.speak(q.answer, voice: q.voice) }
    }
}

/// The end-of-run screen: score, stars, and what you missed.
private struct ChallengeResultView: View {
    let model: ChallengeModel
    let lesson: Lesson
    let total: Int
    let retry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.pronouncer) private var pronouncer
    /// Unlike a question's audio — where the clip *is* the question and so always plays —
    /// a cheer is commentary, and commentary respects the sound switch.
    @AppStorage(Pref.soundOn) private var soundOn = true
    /// Chosen once, on appear. Nil until then, and nil forever if the pools were empty.
    @State private var phrase: Cheer?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // The one place a StarRow celebrates. A miss lands nothing — `land`
                // returns on zero stars — so the animation can only ever mark a pass.
                StarRow(stars: model.stars, size: 34, celebrates: true)
                    .padding(.top, 12)

                Text("\(model.scorePercent)%")
                    .font(Theme.display(56))
                    .foregroundStyle(model.passed ? Theme.correct : Theme.wrong)

                Text(model.passed
                     ? (model.index >= total ? L.t("Lesson complete!") : L.t("Challenge passed!"))
                     : L.t("%@% needed to pass — try again.", "\(Challenge.passScore)"))
                    .font(Theme.title(.headline))
                    .multilineTextAlignment(.center)

                if let phrase { cheerLine(phrase) }

                if !model.missed.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L.t("Review these")).font(Theme.title(.subheadline))
                        ForEach(uniqueMissed, id: \.id) { word in
                            HStack {
                                Text(word.kana).font(Theme.jp(20))
                                Spacer()
                                Text(word.translation)
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                }

                // Retry leads after a miss — the words to fix are right there on
                // screen. After a pass it stays available but steps back, so the
                // forward path is obvious while chasing the third star is still easy.
                VStack(spacing: 10) {
                    retryButton(prominent: !model.passed)
                    doneButton(prominent: model.passed)
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear(perform: cheer)
    }

    /// The phrase, in Japanese, with its reading and meaning under it.
    ///
    /// `Theme.jp` for the Japanese — the face follows the content's script, and this line
    /// is Japanese on every one of the 17 interface languages. The gloss reads as a
    /// caption rather than as a second headline, because the phrase is the thing being
    /// learned and the English is only there to make it stick.
    @ViewBuilder
    private func cheerLine(_ phrase: Cheer) -> some View {
        VStack(spacing: 4) {
            Text(phrase.text)
                .font(Theme.jp(28))
            Text("\(phrase.romaji) · \(L.t(phrase.meaning))")
                .font(Theme.title(.footnote, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    /// Pick once on appear, then draw it and — only if sound is on — say it.
    ///
    /// Picked into state rather than re-read per redraw: a phrase that changed on every
    /// layout pass would be unreadable. And picked *regardless* of the sound switch,
    /// because the text is the part being taught; muting the app shouldn't cost a learner
    /// the phrase, only the voice.
    ///
    /// The speech delay lets the push transition finish — `speak` stops whatever is
    /// playing, so firing immediately would clip the last question's audio and talk over
    /// the screen sliding in.
    private func cheer() {
        guard let choice = Cheer.next(passed: model.passed) else { return }
        phrase = choice
        guard soundOn else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            pronouncer.speak(cheer: choice)
        }
    }

    @ViewBuilder
    private func retryButton(prominent: Bool) -> some View {
        let button = Button {
            Track.event("challenge_retry", ["lesson": lesson.number,
                                            "index": model.index,
                                            "previous_score": model.scorePercent])
            retry()
        } label: {
            Label(L.t("Try again"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
        }
        if prominent { button.buttonStyle(.borderedProminent).controlSize(.large) }
        else { button.buttonStyle(.bordered).controlSize(.large) }
    }

    @ViewBuilder
    private func doneButton(prominent: Bool) -> some View {
        let button = Button {
            Track.event("challenge_done_tapped", ["lesson": lesson.number,
                                                  "index": model.index,
                                                  "passed": model.passed])
            dismiss()
        } label: {
            Text(model.passed ? L.t("Done") : L.t("Back")).frame(maxWidth: .infinity)
        }
        if prominent { button.buttonStyle(.borderedProminent).controlSize(.large) }
        else { button.buttonStyle(.bordered).controlSize(.large) }
    }

    /// A word missed twice shouldn't be listed twice.
    private var uniqueMissed: [Vocab] {
        var seen = Set<String>()
        return model.missed.filter { seen.insert($0.id).inserted }
    }
}

/// Three stars, filled to `stars`. Shared by the result screen and the ladder rows.
struct StarRow: View {
    let stars: Int
    var size: CGFloat = 13
    /// Whether the earned stars land one at a time when the row appears.
    ///
    /// Off by default, and deliberately *not* inferred from `stars == 3`: the ladder
    /// draws a row on every rung, so stars bouncing as rows scroll into view would read
    /// as noise rather than as a reward for having just done something.
    var celebrates = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One counter per star; bumping one is what fires its bounce.
    @State private var landed = [0, 0, 0]
    /// Bumped when the third star lands, which is the only thing that carries a haptic.
    /// Kept separate from `landed` so Reduce Motion can suppress the bounce without
    /// suppressing the haptic too.
    @State private var perfected = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                Image(systemName: i <= stars ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i <= stars ? Color.yellow : Color.secondary.opacity(0.35))
                    .symbolEffect(.bounce, value: landed[i - 1])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("%@ of 3 stars", "\(stars)"))
        .sensoryFeedback(.success, trigger: perfected)
        .onAppear(perform: land)
    }

    /// Left to right, one every `stagger` seconds, with the third carrying the haptic —
    /// sequential rather than all at once because three stars arriving together is a
    /// single event, while three arriving in order is a *count*, and counting up is the
    /// part that feels earned. The lead-in lets the screen settle first, so the stars
    /// land on a still page rather than during the push transition.
    ///
    /// Reduce Motion drops the stagger, not the reward: the row simply draws already
    /// filled and the haptic still marks a clean run. The setting is about movement, and
    /// silently withholding the feedback as well would make it a worse result rather
    /// than a calmer one.
    private func land() {
        guard celebrates, stars > 0 else { return }
        guard !reduceMotion else {
            if stars >= 3 { perfected += 1 }
            return
        }
        for i in 0..<min(stars, landed.count) {
            DispatchQueue.main.asyncAfter(deadline: .now() + leadIn + Double(i) * stagger) {
                landed[i] += 1
                if i == 2 { perfected += 1 }
            }
        }
    }

    private let leadIn = 0.25
    private let stagger = 0.18
}
