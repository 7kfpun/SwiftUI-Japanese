import SwiftUI
import SwiftData

/// One run of a challenge: a briefing, a bounded set of questions, then a result
/// screen — the design's intro → play → result flow.
///
/// Deliberately unlike `PracticeView`, which is an open-ended practice loop with
/// user-switchable forms and no ending. Here the questions, their forms and their
/// order are all fixed up front by `ChallengeModel`, because a score only means
/// something if the run is the same shape every time.
struct ChallengeView: View {
    /// Where the run stands. `result` isn't a phase — it's `model.isDone`, so the
    /// score screen can never be reached by a state bug that skipped the questions.
    private enum Phase { case intro, play }

    @State private var model: ChallengeModel
    @State private var phase: Phase = .intro
    /// When the current run started — drives the play screen's clock.
    @State private var startDate = Date.now
    @Environment(\.pronouncer) private var pronouncer
    @Environment(\.modelContext) private var context
    @Environment(Store.self) private var store
    @Environment(Unlock.self) private var unlock
    @Environment(PracticeProgress.self) private var practice
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
    private let total: Int
    /// The rung this view was pushed for. `@State`, not `let`, because the result screen
    /// can walk forward to the next rung without popping — see `advanceToNext`.
    @State private var index: Int

    init(lesson: Lesson, index: Int, total: Int) {
        self.lesson = lesson
        self.total = total
        _index = State(initialValue: index)
        _model = State(initialValue: Self.makeModel(lesson: lesson, index: index, total: total))
    }

    private static func makeModel(lesson: Lesson, index: Int, total: Int) -> ChallengeModel {
        ChallengeModel(lessonNumber: lesson.number, index: index, total: total, words: lesson.entries)
    }

    /// Back to the briefing with a fresh run: new questions, new order, cleared score.
    /// The briefing rather than straight into question 1, because a retry is exactly
    /// when the "last time n%" banner has something to say.
    ///
    /// Also the fix for re-entering a finished challenge. `@State`'s initial value is
    /// only used once per view identity, and re-pushing the same `NavigationLink` row
    /// reuses that identity — so without this you'd return to the previous run's
    /// result screen with no way to play again.
    private func restart() {
        model = Self.makeModel(lesson: lesson, index: index, total: total)
        recorded = false
        phase = .intro
    }

    /// The actual start: the briefing's one button. `challenge_start` fires here — a
    /// run begins when the learner says so, not when the briefing appears.
    private func startRun() {
        startDate = .now
        phase = .play
        Track.event("challenge_start", ["lesson": lesson.number, "index": index,
                                        "questions": model.questions.count])
        autoPlay()
    }

    /// Move on to the next rung without leaving the screen.
    ///
    /// The ladder's forward step used to cost a pop, a scan of the mode list and a push —
    /// three taps to continue the loop the whole product is built on, on the screen where
    /// momentum is highest. This rebuilds the model one rung up instead, landing on the
    /// new rung's briefing so its pool and rules get their moment.
    ///
    /// Still a *button*, never automatic: `Router.openLesson` documents why dropping
    /// someone into a scored test they didn't choose "produces abandons, not attempts",
    /// and that reasoning holds just as well one rung later.
    private func advanceToNext() {
        guard model.passed, index < total else { return }
        Track.event("challenge_next", ["lesson": lesson.number,
                                       "from_index": index,
                                       "stars": model.stars])
        index += 1
        model = Self.makeModel(lesson: lesson, index: index, total: total)
        recorded = false
        phase = .intro
    }

    /// The forward step handed to the result screen, or nil on a lesson's last rung.
    ///
    /// Spelled out with an explicit type rather than inlined as a ternary at the call
    /// site: `cond ? someMethod : nil` gives the type checker a method reference and an
    /// untyped nil to reconcile inside a ViewBuilder, and it gives up — surfacing as an
    /// "ambiguous use of toolbar(content:)" error thirty lines away.
    private var nextAction: (() -> Void)? {
        guard model.index < total else { return nil }
        return { advanceToNext() }
    }

    var body: some View {
        Group {
            if model.isDone {
                ChallengeResultView(model: model, lesson: lesson, total: total,
                                    retry: restart, next: nextAction)
            } else if phase == .intro {
                briefing
            } else {
                play
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
                if phase == .play, let question = model.question, model.picked != nil {
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
            Track.screen("challenge", ["lesson": lesson.number, "index": index])
            if !store.isPremium { Ads.preloadInterstitial() }
        }
        .onChange(of: model.current) { if phase == .play { autoPlay() } }
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
                    items: [SharePrompt.appStoreURL(campaign: .prompt),
                                            SharePrompt.shareText(campaign: .prompt)])
    }

    // MARK: - The briefing

    /// How many wrong answers still round to at least `minScore` percent — the honest
    /// way to phrase the star bands per run, since a short rung allows fewer misses.
    static func allowedWrong(questions: Int, minScore: Int) -> Int {
        guard questions > 0 else { return 0 }
        var w = 0
        while w + 1 <= questions,
              Int((Double(questions - w - 1) / Double(questions) * 100).rounded()) >= minScore {
            w += 1
        }
        return w
    }

    /// The words this rung introduces — every one of them gets a question.
    private var newWords: [Vocab] { Challenge.newWords(lesson.entries, index: index) }

    /// How many of the run's questions go to *older* words. The run asks
    /// `model.questions.count`, the new words take one slot each, and the remainder is
    /// review — so this is arithmetic on what will actually happen, not an estimate.
    private var reviewCount: Int {
        max(0, model.questions.count - newWords.count)
    }

    /// What this rung asks before it asks it: the words it draws from, how the stars
    /// are earned, and — on a return visit — what there is to win back. The design's
    /// point: a scored test you can size up first produces attempts, not abandons.
    private var briefing: some View {
        let best = ChallengeResult.byIndex(lesson: lesson.number, context: context)[index]
        let q = model.questions.count
        let w2 = Self.allowedWrong(questions: q, minScore: 90)
        let w1 = Self.allowedWrong(questions: q, minScore: Challenge.passScore)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t("Rung %@ of %@", "\(index)", "\(total)"))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    // The rung named in the page, not only in the navigation bar: this
                    // screen is where someone decides whether to take a scored test, and
                    // a 17pt inline title is not what the decision anchors on.
                    Text(L.t("Challenge %@", "\(index)"))
                        .font(Theme.title(.largeTitle, weight: .bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(index == 1
                         ? L.t("%@ questions — recognise each new word.", "\(q)")
                         : L.t("%@ mixed questions — recall, listening and kanji can all appear.", "\(q)"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // The words this rung *introduces*, which is the set worth naming.
                //
                // It used to list `Challenge.pool` — literally what the questions draw
                // from — and that was accurate and useless: on lesson 1 rung 3 the pool
                // is 25 words for a 10-question run, so most of what it showed would not
                // be asked, and rungs 3 through 6 all displayed roughly the same 21–25
                // chips. A panel that barely changes between rungs says nothing about
                // the rung you are looking at.
                //
                // The new words are the opposite: seven or eight per rung, different
                // every time, and **each one is guaranteed a question**
                // (`ChallengeModel.build` reserves them a slot;
                // `ChallengeTests.newWordsAreAlwaysAsked` pins it). The review share is
                // then stated as a count rather than drawn, because which older words
                // come up is decided per run and naming them would be a promise.
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("New in this challenge"))
                        .font(Theme.title(.footnote))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(newWords, id: \.id) { word in
                            Text(word.displaysKanji ? word.kanji : word.kana)
                                .font(Theme.jp(15))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                    Text(reviewCount > 0
                         ? L.t("Each one is asked, plus %@ from earlier words", "\(reviewCount)")
                         : L.t("Each one is asked"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))

                // The star bands, phrased in misses — computed from this run's real
                // question count, never hardcoded to ten.
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("How stars work"))
                        .font(Theme.title(.footnote))
                        .foregroundStyle(.secondary)
                    starRule(stars: 3, text: L.t("All correct"))
                    if w2 > 0 { starRule(stars: 2, text: L.t("Up to %@ wrong", "\(w2)")) }
                    if w1 > w2 { starRule(stars: 1, text: L.t("Up to %@ wrong", "\(w1)")) }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))

                // The comeback line, only when there is something to come back for.
                if let best, best.bestScore > 0, best.stars < 3 {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L.t("Last time %@% — %@ ★", "\(best.bestScore)", "\(best.stars)"))
                                .font(.subheadline.weight(.medium))
                            Text(L.t("A clean run fills all 3 ★"))
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        }
                        Spacer()
                        StarRow(stars: best.stars, size: 12)
                    }
                    .padding(14)
                    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent, lineWidth: 1))
                }

                startButton
                    .padding(.top, 4)
            }
        }
        // No scroll bar: these are cards, not a document. The indicator sat over the
        // content and reported a position nobody needs — how far down a briefing you
        // are is not information, where you are in a licence agreement is (which is why
        // Legal, the paywall and the feedback form keep theirs).
        .scrollIndicators(.hidden)
    }

    private func starRule(stars: Int, text: String) -> some View {
        HStack(spacing: 11) {
            StarRow(stars: stars, size: 12)
            Text(text).font(.subheadline)
        }
    }

    private var startButton: some View {
        Button(action: startRun) {
            Text(L.t("Start the challenge"))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(Color(.systemBackground))
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: - The run

    /// Wrong answers so far, counting the one just picked.
    private var wrongs: Int {
        model.current + (model.picked == nil ? 0 : 1) - model.correct
    }

    /// The stars still reachable if everything from here on is answered right.
    private var potentialStars: Int {
        let q = max(model.questions.count, 1)
        let bestScore = Int((Double(q - wrongs) / Double(q) * 100).rounded())
        return Challenge.stars(score: bestScore)
    }

    @ViewBuilder
    private var play: some View {
        if let question = model.question {
            VStack(spacing: 14) {
                // The run's header: the clock, and the stars still on the table —
                // which shrink as misses land, so the stake is visible per question.
                HStack {
                    TimelineView(.periodic(from: startDate, by: 1)) { ctx in
                        Text(clock(ctx.date))
                            .font(.footnote.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // The stars are a *stake*, not a score, and unlabelled they read as
                    // one — three greyed stars look like a result you already got.
                    Text(L.t("Still winnable"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    StarRow(stars: potentialStars, size: 13)
                }

                pips

                VStack(spacing: 10) {
                    Text(promptLabel(question))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    prompt(question)
                    // The card is tappable and nothing says so. On a listening rung it
                    // is the only way to hear the question again, which makes an
                    // invisible affordance a real problem rather than a polish note.
                    Text(question.from.isAudio ? L.t("Tap to hear it again") : L.t("Tap to hear it"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: 10) {
                    ForEach(question.options.indices, id: \.self) { i in
                        QuizOptionButton(text: question.to.value(question.options[i]),
                                         index: i,
                                         picked: model.picked,
                                         isAnswer: question.isCorrect(i),
                                         font: question.to.isJapanese ? Theme.jp(22) : .headline) {
                            answer(i, question: question)
                        }
                        .frame(minHeight: 56)
                    }
                }

                Text(riskLine(question))
                    .font(.footnote)
                    // Red only for a wrong answer's correction — the line is otherwise
                    // commentary, and colouring the running stake would spend answer
                    // feedback's colour on something that isn't feedback.
                    .foregroundStyle(wrongAnswerShowing(question) ? Theme.wrong : Color.secondary)
                    .multilineTextAlignment(.center)

                // The forward step appears only once the question is settled — an
                // always-there disabled button reads as something broken, and its
                // arrival is the "next" cue itself.
                ZStack {
                    if model.picked != nil {
                        Button { withAnimation(.easeOut(duration: 0.15)) { model.advance() } } label: {
                            // Fill and shape go *inside* the label. A `.frame` only
                            // reserves layout space — it is not hit-testable on its own,
                            // so with the background applied outside, only the glyphs of
                            // the word took taps and the rest of a 54pt bar did nothing.
                            Text(model.isLastQuestion ? L.t("Finish") : L.t("Next"))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .foregroundStyle(Color(.systemBackground))
                                .background(Color.primary, in: RoundedRectangle(cornerRadius: 18))
                                .contentShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(height: 54)
                .animation(.easeOut(duration: 0.2), value: model.picked != nil)
            }
        }
    }

    private func answer(_ i: Int, question: ChallengeQuestion) {
        model.choose(i)
        // One event per selection, its own name like every mode's.
        // `from`/`to` because the ladder's whole design is forms
        // hardening as you climb — per-form accuracy is the readout.
        // No word id or text: the answer stream is volume, not content.
        Track.event("challenge_answer", ["lesson": lesson.number,
                                         "index": model.index,
                                         "from": question.from.label,
                                         "to": question.to.label,
                                         "correct": question.isCorrect(i)])
        // A ladder miss demotes the word's Practice stage: the next Practice
        // session re-deals it as a card, which is what makes the result screen's
        // "missed words come back in Practice" true rather than hopeful.
        if !question.isCorrect(i), practice.stage(of: question.answer.id) >= .recognized {
            practice.set(.seen, for: question.answer.id)
        }
        if soundOn || question.from.isAudio {
            pronouncer.speak(question.answer, voice: question.voice)
        }
    }

    private func clock(_ now: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(startDate)))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    /// One thin pip per question: answered ones filled, the live one halfway, the rest
    /// on the line colour. Position without numbers — the count is short enough to see.
    private var pips: some View {
        HStack(spacing: 5) {
            ForEach(model.questions.indices, id: \.self) { i in
                Capsule()
                    .fill(i < model.current ? Color.primary
                          : i == model.current ? Color.secondary
                          : Theme.line)
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.current + 1) / \(model.questions.count)")
    }

    /// What the question is asking, said outright — the form pair implies it, but only
    /// to someone who already knows the ladder's design.
    private func promptLabel(_ q: ChallengeQuestion) -> String {
        if q.from.isAudio { return L.t("Hear it, pick the word") }
        if q.from == .translation { return L.t("Which word means this?") }
        if q.to == .kanji { return L.t("Which kanji writes this reading?") }
        return L.t("What does this word mean?")
    }

    /// Whether what the risk line is currently saying is a correction after a miss.
    private func wrongAnswerShowing(_ q: ChallengeQuestion) -> Bool {
        guard let picked = model.picked else { return false }
        return !q.isCorrect(picked)
    }

    /// The stake, stated between the options and the next button: what the run still
    /// holds before an answer, the verdict after one.
    private func riskLine(_ q: ChallengeQuestion) -> String {
        if model.picked == nil {
            if wrongs == 0 { return L.t("All correct so far — keep it up for 3 ★") }
            if potentialStars > 0 {
                return L.t("%@ wrong — finish clean to keep %@ ★", "\(wrongs)", "\(potentialStars)")
            }
            return L.t("No stars this run — you can retry right after")
        }
        if let picked = model.picked, q.isCorrect(picked) { return L.t("Correct!") }
        return L.t("The answer is %@", q.to.value(q.answer))
    }

    /// A big speaker for audio prompts, the word itself otherwise. Tapping replays.
    private func prompt(_ q: ChallengeQuestion) -> some View {
        Group {
            if q.from.isAudio {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 64))
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
            Track.event("rating_dismissed", ["lesson": lesson.number,
                                            "source": "challenge"])
            return
        }
        ratedStars = nil
        // `source` separates the two surfaces that ask: the star row after a rung, and
        // Diagnostics' developer copy of it. Without it the two are one funnel.
        Track.event("rating_given", ["stars": stars, "lesson": lesson.number,
                                     "index": index, "source": "challenge"])
        Survey.submit(Survey.Rating(stars: stars),
                      context: Survey.Context(store: store, modelContext: context))
        if stars >= 4 {
            RatingPrompt.requestAppStoreReview()
        } else {
            feedbackStars = stars
            showFeedback = true
        }
    }

    /// Audio questions must always speak — the clip *is* the question, so the sound toggle
    /// can't silence them. Everything else respects the toggle, and which prompts may speak
    /// at all is `VForm.promptAudioSafe`'s rule, shared so the quizzes can't drift.
    private func autoPlay() {
        guard let q = model.question else { return }
        if q.from.isAudio { pronouncer.speak(q.answer, voice: q.voice) }
        else if soundOn, VForm.promptAudioSafe(from: q.from, to: q.to) {
            pronouncer.speak(q.answer, voice: q.voice)
        }
    }
}

/// The end-of-run screen: the stars, what they mean, the numbers, and what you missed.
private struct ChallengeResultView: View {
    let model: ChallengeModel
    let lesson: Lesson
    let total: Int
    let retry: () -> Void
    /// Advance to the next rung in place. Nil on the last rung of a lesson, which is
    /// what makes "Lesson complete!" the end of the road rather than a button that
    /// walks off the end of the ladder.
    let next: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.pronouncer) private var pronouncer
    @Environment(\.modelContext) private var context
    /// Unlike a question's audio — where the clip *is* the question and so always plays —
    /// a cheer is commentary, and commentary respects the sound switch.
    @AppStorage(Pref.soundOn) private var soundOn = true
    /// Chosen once, on appear. Nil until then, and nil forever if the pools were empty.
    @State private var phrase: Cheer?

    private var title: String {
        switch model.stars {
        case 3:  return L.t("Perfect — 3 ★")
        case 2:  return L.t("So close to perfect")
        case 1:  return L.t("Passed!")
        default: return L.t("Try again")
        }
    }

    private var blurb: String {
        if model.passed && model.index >= total { return L.t("Lesson complete!") }
        if model.stars == 3 { return L.t("Full marks — the next challenge is open.") }
        if model.passed { return L.t("Missed words will come back in Practice.") }
        return L.t("%@% needed to pass — try again.", "\(Challenge.passScore)")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // The one place a StarRow celebrates. A miss lands nothing — `land`
                // returns on zero stars — so the animation can only ever mark a pass.
                StarRow(stars: model.stars, size: 34, celebrates: true)
                    .padding(.top, 12)

                VStack(spacing: 6) {
                    Text(title)
                        .font(Theme.title(.title2, weight: .bold))
                    Text(blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let phrase { cheerLine(phrase) }

                stats

                if !model.missed.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L.t("Review these")).font(Theme.title(.subheadline))
                        // Each row plays its word — these are the words just missed, and
                        // hearing one again right here is the cheapest rep it will ever
                        // get. Ignores the sound toggle like every explicit tap does:
                        // auto-play respects the setting, a deliberate tap is the ask.
                        ForEach(uniqueMissed, id: \.id) { word in
                            Button {
                                pronouncer.speak(word)
                                Track.event("challenge_review_play",
                                            ["lesson": lesson.number, "index": index])
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "speaker.wave.2")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.accent)
                                    Text(word.kana).font(Theme.jp(20))
                                    Spacer()
                                    Text(word.translation)
                                        .font(.subheadline).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(word.kana)
                            .accessibilityHint(L.t("Tap any word to hear it."))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                }

                // What is left to win, stated where the retry button is — the same job
                // the briefing's comeback banner does on the way in. A result screen
                // that only reports is a dead end; this is the sentence that makes
                // "again" a decision rather than a shrug.
                whatIsLeft

                // After a pass the forward step leads and everything else steps back:
                // continuing is the common intent, and it used to be the only one that
                // cost a pop and a hunt. After a miss, retry leads instead — the words to
                // fix are right there on screen — and no forward button is offered at
                // all, because the next rung isn't unlocked yet.
                VStack(spacing: 10) {
                    if model.passed, let next { nextButton(next) }
                    HStack(spacing: 10) {
                        retryButton(prominent: !model.passed)
                        doneButton(prominent: model.passed && model.index >= total)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        // A results card is a fixed shape, not a document —
        // the bar sat over the content and reported a position nobody needed.
        .scrollIndicators(.hidden)
        .onAppear(perform: cheer)
    }

    /// This run, the rung's best, and the lesson's star tally — the three numbers that
    /// say whether to retry, move on, or close the lesson.
    private var stats: some View {
        let byIndex = ChallengeResult.byIndex(lesson: lesson.number, context: context)
        let best = max(byIndex[model.index]?.bestScore ?? 0, model.scorePercent)
        let lessonStars = byIndex.values.reduce(0) { $0 + $1.stars }
        return HStack(spacing: 10) {
            statCard(L.t("This run"), "\(model.scorePercent)%")
            statCard(L.t("Best"), "\(best)%")
            // Accented: the other two describe this run, this one describes the lesson,
            // and it is the number that says whether to move on.
            statCard(L.t("Lesson stars"), "\(lessonStars) / \(total * 3)", tint: Theme.accent)
        }
    }

    /// The offer, sized to what actually happened: a clean sweep says what is left in
    /// the lesson, a pass says the third star is still there for the taking, a miss says
    /// how far short it fell. Tinted like the briefing's banner, and on a miss it takes
    /// the warm tone rather than the answer-feedback red — the run is over, so this is
    /// an invitation, not a verdict.
    private var whatIsLeft: some View {
        let passed = model.passed
        let short = max(0, Challenge.passScore - model.scorePercent)
        let title: String
        let body: String
        if model.stars >= 3 {
            title = L.t("Every word in this challenge stuck")
            body = model.index >= total ? L.t("Lesson complete!")
                                        : L.t("Challenge %@ is open.", "\(model.index + 1)")
        } else if passed {
            title = L.t("A clean run fills all 3 ★")
            body = L.t("Your best only goes up — replaying never costs a star you have.")
        } else {
            title = L.t("%@% short of passing", "\(short)")
            body = L.t("Missed words will come back in Practice.")
        }

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StarRow(stars: model.stars, size: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background((passed ? Theme.accent : Color.streak).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(passed ? Theme.accent : Color.streak, lineWidth: 1))
    }

    private func statCard(_ label: String, _ value: String,
                          tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(Theme.title(.title3))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    /// The phrase, in Japanese, with its reading and meaning under it.
    ///
    /// `Theme.jp` for the Japanese — the face follows the content's script, and this line
    /// is Japanese on every one of the 19 interface languages. The gloss reads as a
    /// caption rather than as a second headline, because the phrase is the thing being
    /// learned and the English is only there to make it stick.
    @ViewBuilder
    private func cheerLine(_ phrase: Cheer) -> some View {
        // Tappable: it plays again *and* draws another phrase. There are six to eight
        // per tier and a learner meets them dozens of times, so the tap is how the rest
        // get discovered — a phrase heard once at the end of a run is a phrase never
        // learned. Re-rolling on tap also means the button does something visible even
        // with the sound off.
        Button {
            guard let next = Cheer.next(stars: model.stars, passed: model.passed) else { return }
            withAnimation(.easeOut(duration: 0.15)) { self.phrase = next }
            pronouncer.speak(cheer: next)
            // Whether the phrases get discovered at all is the question the tap answers,
            // and the tier is what decides how many there are to find.
            Track.event("cheer_replay", ["stars": model.stars, "passed": model.passed])
        } label: {
            VStack(spacing: 4) {
                Text(phrase.text)
                    .font(Theme.jp(28))
                Text("\(phrase.romaji) · \(L.t(phrase.meaning))")
                    .font(Theme.title(.footnote, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L.t("Tap to hear it again"))
    }

    /// Pick once on appear, then draw it and — only if sound is on — say it.
    ///
    /// Picked into state rather than re-read per redraw: a phrase that changed on every
    /// layout pass would be unreadable. And picked *regardless* of the sound switch,
    /// because the text is the part being taught; muting the app shouldn't cost a learner
    /// the phrase, only the voice.
    ///
    /// Spoken immediately, not after a settle delay: the voice and the screen are one
    /// moment, and even 0.4s apart reads as the app lagging rather than reacting. The
    /// cost is that `speak` stops the final answer's playback mid-word — acceptable,
    /// because the result appearing *is* the event now, and the cheer is the sound of it.
    private func cheer() {
        guard let choice = Cheer.next(stars: model.stars, passed: model.passed) else { return }
        phrase = choice
        guard soundOn else { return }
        pronouncer.speak(cheer: choice)
    }

    /// The forward step. Prominent, and worded as encouragement rather than navigation —
    /// "Next challenge" describes the app's structure, "Keep the run going" describes
    /// what the learner is actually doing, and this is the one screen where they've just
    /// earned the right to hear it.
    @ViewBuilder
    private func nextButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L.t("Keep going — Challenge %@", "\(model.index + 1)"),
                  systemImage: "arrow.right.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
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

/// Three stars, filled to `stars`. Shared by the result screen and the ladder chips.
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
