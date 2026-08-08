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
    @AppStorage(Pref.soundOn) private var soundOn = true
    @State private var recorded = false
    @State private var showRating = false
    @State private var showFeedback = false

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
                        if soundOn || question.from.isAudio { pronouncer.speak(question.answer) }
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
            ToolbarItem(placement: .topBarTrailing) { SoundToggle() }
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
        .sheet(isPresented: $showRating) {
            RatingSheet { stars in
                Track.event("rating_given", ["stars": stars,
                                             "lesson": lesson.number,
                                             "index": index])
                // 4★+ goes to Apple; anything lower goes somewhere a reply can come
                // back from. Both are a real destination — neither answer dead-ends.
                if stars >= 4 {
                    RatingPrompt.requestAppStoreReview()
                } else {
                    showFeedback = true
                }
            }
        }
        .sheet(isPresented: $showFeedback) {
            SafariView(url: Feedback.url(source: "rating")).ignoresSafeArea()
        }
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
        askForRatingIfEarned()
    }

    /// A just-passed rung is the one moment the app is unambiguously working, so it's
    /// where the ask goes — subscribers only, and once. Deferred a beat so the result
    /// screen is on screen behind the sheet rather than appearing under it.
    private func askForRatingIfEarned() {
        let passedCount = ChallengeResult.totalPassed(context: context)
        guard RatingPrompt.shouldAsk(isPremium: store.isPremium,
                                     passed: model.passed,
                                     passedCount: passedCount) else { return }
        RatingPrompt.markAsked()
        Track.event("rating_shown", ["lesson": lesson.number, "passed_total": passedCount])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showRating = true }
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
                    .font(Theme.jp(38))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { pronouncer.speak(q.answer) }
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

    /// Audio questions must always speak — the clip *is* the question, so the sound
    /// toggle can't silence them. Other prompts respect the toggle, with one hard
    /// exception: a translation prompt never speaks. Its options are the Japanese
    /// words, so pronouncing the answer reads the correct button aloud. (Any prompt
    /// that shows the word — kana/kanji — already identifies it, so audio adds the
    /// reading without giving anything away.)
    private func autoPlay() {
        guard let q = model.question else { return }
        if q.from.isAudio { pronouncer.speak(q.answer) }
        else if soundOn, q.from != .translation { pronouncer.speak(q.answer) }
    }
}

/// The end-of-run screen: score, stars, and what you missed.
private struct ChallengeResultView: View {
    let model: ChallengeModel
    let lesson: Lesson
    let total: Int
    let retry: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                StarRow(stars: model.stars, size: 34)
                    .padding(.top, 12)

                Text("\(model.scorePercent)%")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(model.passed ? Theme.correct : Theme.wrong)

                Text(model.passed
                     ? (model.index >= total ? L.t("Lesson complete!") : L.t("Challenge passed!"))
                     : L.t("%@% needed to pass — try again.", "\(Challenge.passScore)"))
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if !model.missed.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L.t("Review these")).font(.subheadline.weight(.semibold))
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

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                Image(systemName: i <= stars ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i <= stars ? Color.yellow : Color.secondary.opacity(0.35))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("%@ of 3 stars", "\(stars)"))
    }
}
