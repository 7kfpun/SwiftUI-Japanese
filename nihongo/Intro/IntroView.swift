import SwiftUI

/// First launch: a five-card tour that also asks the three questions worth asking before
/// anyone has used anything.
///
/// Paged with `cardPager` over a `SwipeCard` deck rather than a `TabView(.page)`, on
/// purpose — the same gesture, chrome and peek stack as Today, Flashcards and Train. The
/// tour teaches the app's one navigation idiom while it explains the app, and the first
/// swipe a learner ever makes is the swipe every other screen wants.
///
/// Two rules the whole flow follows:
///
/// - **Only card 1 writes a setting as you go** (`Pref.translationLanguage`). The three
///   answers are held in `IntroAnswers` and written once, on the way out, so a skip
///   halfway through persists exactly what was actually answered.
/// - **It never touches `Pref.appLanguage`.** `RootView` keys the whole tab tree on
///   `.id(appLanguage)`, so changing it here would rebuild the hierarchy underneath this
///   cover mid-onboarding. The meanings language is the one that's settable here.
///
/// No pricing, no premium, no free-lesson limit is mentioned anywhere in the five cards —
/// a deliberate product decision, not an omission.
struct IntroView: View {
    /// Called with the tab to land on, once the intro is finished or skipped.
    let onFinish: (Router.Tab) -> Void

    @AppStorage(Pref.translationLanguage) private var language = VocabStore.deviceDefaultLanguage
    @Environment(\.pronouncer) private var pronouncer
    // Only for the survey's diagnostic context on the way out — the tour itself is never
    // gated and reads no progress. See `Survey.Context`.
    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var index = 0
    @State private var fling: Int?
    @State private var answers = IntroAnswers()
    /// Vocab List is preselected so card 3 is never an empty frame.
    @State private var peek: Intro.Mode = .vocabList
    /// The stepper's value, separate from the answer: it has to have a number to show
    /// before the "Yes" chip is ever tapped, and moving it shouldn't retroactively
    /// answer a question the learner hasn't answered.
    @State private var textbookLesson = 5

    private static let cards = Intro.Card.allCases
    /// Adaptive rather than a fixed row: "Both, comfortably" is half again as long in
    /// German, and a row sized for English would clip it.
    private static let chipColumns = [GridItem(.adaptive(minimum: 112), spacing: 8)]
    /// Card 3's four mode chips: a fixed 2 × 2, never adaptive — see `modesCard`.
    private static let modeColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    private var card: Intro.Card { Self.cards[index] }
    private var isLast: Bool { index == Self.cards.count - 1 }

    /// Lesson 1, in the language meanings are currently shown in. Every sample on every
    /// card comes from here — never a hardcoded word, so the tour shows what lesson 1 will
    /// actually show, in the learner's own language.
    private var entries: [Vocab] { VocabStore.lesson(1, language).entries }

    /// The word card 1 is built from. `entries.first` (わたし) is kana-only, so a card
    /// built on it would teach three fields where `CardOptionsBar` toggles four — this
    /// takes the first entry carrying a distinct kanji instead, and falls back to the
    /// first if a data regeneration ever leaves none.
    private var anatomyWord: Vocab? { entries.first { $0.displaysKanji } ?? entries.first }

    var body: some View {
        VStack(spacing: 12) {
            skipBar
            deck
            footer
        }
        .padding()
        .background(Theme.canvas)
        .onAppear { trackCard() }
        .onChange(of: index) { trackCard() }
    }

    // MARK: - Chrome

    private var skipBar: some View {
        HStack {
            Spacer()
            Button(L.t("Skip")) { skip() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// The card itself, over the same peek stack every other card screen uses — here the
    /// layers double as a progress cue, thinning out as the tour runs down.
    private var deck: some View {
        ZStack {
            CardStackPeek(count: min(2, Self.cards.count - 1 - index))
            // Swipeable, like every other card surface in the app — Today, Flashcards,
            // Train, Kana Swipe and Learn all page this way, so the first card a learner
            // ever sees should teach that gesture rather than contradict it. `Next` stays as
            // the obvious affordance for anyone who doesn't try a swipe.
            SwipeCard(showsHint: true) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
            }
            // On the card, *not* on the ZStack. `cardPager` applies its offset and rotation
            // to whatever it modifies, so attaching it outside flings the peek layers along
            // with the front card and the deck slides off as one slab instead of a card
            // leaving a stack behind. Same rule Flashcards and Today follow — and the same
            // trap `Flashcards.swift`'s own comment warns about.
            .cardPager(fling: $fling) { turn($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            // Past the first card only. A back-swipe already worked, but a gesture is a poor
            // *only* way back: nothing on screen said the tour was reversible, and a learner
            // who mis-tapped an answer had no visible way to correct it. Flings through the
            // same `fling` binding as `Next`, so back and forward animate identically.
            if index > 0 {
                Button { retreat() } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(L.t("Back"))
            }
            dots
            Spacer(minLength: 12)
            // The reminders card carries its own two answers ("Remind me" / "Not now"),
            // and a third button here would be a way to finish the tour without answering
            // — which would land someone in the app having neither opted in nor declined,
            // and leave the ask to fire again later as if it had never been shown.
            if card != .reminders {
                Button { advance() } label: {
                    HStack(spacing: 6) {
                        Text(isLast ? L.t("Start learning") : L.t("Next"))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "arrow.right")
                    }
                    .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Self.cards) { c in
                let current = c == card
                Circle()
                    .fill(current ? Theme.accent : Color.secondary.opacity(0.35))
                    .frame(width: current ? 8 : 6, height: current ? 8 : 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index + 1) / \(Self.cards.count)")
    }

    @ViewBuilder private var content: some View {
        switch card {
        case .meanings:  meaningsCard
        case .kana:      kanaCard
        case .modes:     modesCard
        case .challenge: challengeCard
        case .today:     todayCard
        case .reminders: remindersCard
        }
    }

    // MARK: - Card 6 · Reminders

    /// The soft opt-in. Answering either way finishes the tour, and **only a yes reaches
    /// iOS** — a "not now" here must never be followed by the system alert, because that
    /// alert can only be shown once and a refusal to it is permanent.
    private var remindersCard: some View {
        NotificationOptInCard { wantsReminders in
            NotificationOptIn.recordAsked()
            Track.event("notification_opt_in", ["source": "intro", "accepted": wantsReminders])
            Task {
                if wantsReminders, await StreakReminder.requestAuthorization() {
                    UserDefaults.standard.set(true, forKey: Pref.streakReminderOn)
                    await StreakReminder.reschedule(studiedToday: false)
                    await PushService.shared.registerIfAuthorized()
                }
                await MainActor.run { finish() }
            }
        }
    }

    // MARK: - Card 1 · Meanings

    /// The four-field anatomy every card in the app shares (kanji / kana / romaji /
    /// meaning), stacked exactly as Today stacks it, plus the one thing that's worth
    /// choosing this early: which language the fourth field is in.
    private var meaningsCard: some View {
        VStack(spacing: 14) {
            Text(L.t("Meanings in %@", VocabStore.displayName(language)))
                .font(Theme.title(.title3))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)

            if let word = anatomyWord {
                Button { pronouncer.speak(word) } label: { wordFace(word) }
                    .buttonStyle(.plain)
            }

            Text(L.t("Tap any word to hear it."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            languageMenu
        }
    }

    private func wordFace(_ word: Vocab) -> some View {
        VStack(spacing: 10) {
            if word.displaysKanji {
                Text(word.kanji).font(Theme.jp(22)).foregroundStyle(.secondary)
            }
            Text(word.kana)
                .font(Theme.jp(44))
                .multilineTextAlignment(.center).minimumScaleFactor(0.4)
            Text(word.romaji).font(.title3).foregroundStyle(.secondary)
            Text(word.translation)
                .font(.title3).foregroundStyle(Theme.accent)
                .multilineTextAlignment(.center).minimumScaleFactor(0.5)
        }
        .contentShape(Rectangle())
    }

    /// Meanings only — see the type's note on why `Pref.appLanguage` is off limits here.
    /// A menu rather than 17 chips, and the same event Settings logs, so a language chosen
    /// during onboarding is indistinguishable from one chosen later.
    private var languageMenu: some View {
        Menu {
            Picker("", selection: $language) {
                ForEach(VocabStore.availableLanguages, id: \.self) { code in
                    Text(VocabStore.displayName(code)).tag(code)
                }
            }
        } label: {
            Label(L.t("Change language"), systemImage: "globe")
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .onChange(of: language) { Track.event("set_vocab_language", ["code": language]) }
    }

    // MARK: - Card 2 · Kana

    private var kanaCard: some View {
        VStack(spacing: 12) {
            if let a = Self.aCell {
                Button { pronouncer.speak(kana: a) } label: {
                    Text(a.hiragana)
                        .font(Theme.jpBold(60))
                        .foregroundStyle(Theme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(a.romaji)
            }

            Text(L.t("All of Kana is free."))
                .font(Theme.title(.title3))
                .multilineTextAlignment(.center).minimumScaleFactor(0.6)
            Text(L.t("The chart, the quizzes, and drawing a kana to have your strokes scored."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            question(L.t("Do you read kana already?"))

            // One per row, not an adaptive grid: three options don't divide into two
            // columns, so the grid left a ragged 2 + 1 with a hole beside the last one.
            // A single column also gives every option the same width, which is what makes
            // three chips read as one set of choices rather than three separate buttons —
            // and it survives the long languages without re-flowing.
            VStack(spacing: 8) {
                ForEach(Intro.KanaLevel.allCases) { level in
                    IntroChip(text: level.title, selected: answers.kana == level) {
                        answers.kana = level
                    }
                }
            }
        }
    }

    /// あ — the first cell of the chart, looked up rather than typed, so the intro speaks
    /// through the same `Pronouncer` path (and the same bundled clip) as the Kana tab.
    private static let aCell: K? = KanaData.seion.flatMap { $0 }.first { $0.romaji == "a" }

    // MARK: - Card 3 · The four Learn modes

    /// Tap a chip, the sample below it changes. The chips carry `SelectModeView`'s own
    /// titles, subtitles and icons — meeting the real labels here is the point.
    private var modesCard: some View {
        VStack(spacing: 10) {
            Text(L.t("Four ways through a lesson."))
                .font(Theme.title(.title3))
                .multilineTextAlignment(.center).minimumScaleFactor(0.6)

            // Exactly two columns, not `chipColumns`' adaptive width. The four mode names
            // are short enough that an adaptive grid fits *three* of them on a 6.9" screen,
            // leaving a ragged 3 + 1 with a hole beside the last chip; two columns give a
            // square 2 × 2 on every device.
            LazyVGrid(columns: Self.modeColumns, spacing: 8) {
                ForEach(Intro.Mode.allCases) { mode in
                    IntroChip(text: mode.title, icon: mode.icon, selected: peek == mode) {
                        peek = mode
                        // The key, not the localized title: an event whose value changes
                        // with the device language can't be grouped in a dashboard.
                        Track.event("intro_mode_peek", ["mode": mode.titleKey])
                    }
                }
            }

            Text(peek.subtitle)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // The sample sits in a `Theme.canvas` pane, and that is load-bearing rather
            // than decoration. Three of the four samples draw the app's real card chrome —
            // Flashcards a `SwipeCard`, Train two `SwipeOptionChip`s, Learn its tiles — and
            // all of that chrome fills with `Theme.surface`. This whole intro card is
            // *also* a `SwipeCard`, so surface-on-surface rendered them invisible but for a
            // hairline: they looked broken while Vocab List, which has no chrome, looked
            // fine. Standing them on the screen colour is what makes them read as separate
            // panes — the same rule `IntroWidgetPreview` documents and follows.
            //
            // A minimum, never a fixed height: the four samples are matched in content
            // volume so switching chips doesn't jump the card, but a long gloss in one of
            // the 17 languages still has to be able to grow.
            IntroModeSample(mode: peek, entries: entries)
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding(10)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))

            Text(L.t("Many ways to learn. All of them fun."))
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Card 4 · The Challenge ladder

    private var challengeCard: some View {
        VStack(spacing: 12) {
            Text(L.t("Challenge"))
                .font(Theme.title(.title3))

            IntroChallengeRungs()

            // Straight from the constants, so the numbers can't drift from the ladder.
            HStack(spacing: 6) {
                Text(L.t("%@ questions a rung", "\(Challenge.questionsPerChallenge)"))
                Text("·")
                Text(L.t("%@% to pass, up to three stars", "\(Challenge.passScore)"))
            }
            .font(.caption).foregroundStyle(.secondary)
            .lineLimit(2).minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)

            Text(L.t("Pass one and the next opens."))
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            question(L.t("Studied Minna no Nihongo before?"))

            VStack(spacing: 8) {
                IntroChip(text: L.t("No, starting fresh"),
                          selected: answers.textbookLesson == 0) {
                    answers.textbookLesson = 0
                }
                IntroChip(text: L.t("Yes — up to lesson %@", "\(textbookLesson)"),
                          selected: (answers.textbookLesson ?? 0) > 0) {
                    answers.textbookLesson = textbookLesson
                }
                // Only once they've said yes: a stepper on an unasked question is noise,
                // and its value is what the chip above then reports.
                if (answers.textbookLesson ?? 0) > 0 {
                    Stepper("", value: Binding(get: { textbookLesson },
                                               set: { textbookLesson = $0
                                                      answers.textbookLesson = $0 }),
                            in: 1...Course.current.lessonCount)
                        .labelsHidden()
                        .accessibilityLabel(L.t("Lesson %@", "\(textbookLesson)"))
                }
            }
        }
    }

    // MARK: - Card 5 · Today + widget

    private var todayCard: some View {
        VStack(spacing: 12) {
            if let word = entries.first {
                IntroWidgetPreview(word: word, lesson: 1)
                    .contentShape(Rectangle())
                    .onTapGesture { pronouncer.speak(word) }
            }

            Text(L.t("Today deals exactly the words your next challenge will ask."))
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Text(L.t("The same deck sits on your Lock Screen, Home Screen and Watch."))
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            question(L.t("Why are you learning?"))

            LazyVGrid(columns: Self.chipColumns, spacing: 8) {
                ForEach(Intro.Goal.allCases) { goal in
                    IntroChip(text: goal.title, icon: goal.icon, selected: answers.goal == goal) {
                        answers.goal = goal
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func question(_ text: String) -> some View {
        Text(text)
            .font(Theme.title(.headline))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .padding(.top, 2)
    }

    // MARK: - Flow

    /// Paging is clamped, not wrapped — this is an explanation, not a carousel. A forward
    /// swipe off the last card finishes, exactly as the button does, so the gesture the
    /// tour just taught is enough to leave it.
    private func turn(_ direction: Int) {
        // The reminders card is the one that must be *answered*, so a forward swipe there
        // does nothing — otherwise the tour's own gesture would be a way past the question,
        // and the answer would go unrecorded and be asked again as if never shown.
        if direction > 0 && card == .reminders { return }
        if direction > 0 && isLast { finish(); return }
        index = min(max(0, index + direction), Self.cards.count - 1)
    }

    /// Advance through `fling` rather than by setting `index`, so the button and the swipe
    /// produce the identical animation (same trick as Learn's Random button).
    private func advance() {
        if isLast { finish() } else { fling = 1 }
    }

    /// One card back. Guarded rather than clamped so the first card's button is simply
    /// absent — a disabled control that never becomes enabled is just clutter.
    private func retreat() {
        guard index > 0 else { return }
        fling = -1
    }

    private func trackCard() { Track.event("intro_card", ["card": card.rawValue]) }

    private func finish() {
        answers.save()
        Track.event("intro_done", answers.trackParams)
        // Only a fully answered run is submitted — see `IntroAnswers.submission`. Nothing is
        // awaited: the write is fire-and-forget over Firestore's offline queue, so the intro
        // closes at the speed of the tap and a learner who finishes the tour on a plane
        // still has their answers land when the network comes back.
        if let submission = answers.submission {
            Survey.submit(submission, context: .init(store: store, modelContext: modelContext))
        }
        onFinish(Intro.landingTab(kana: answers.kana))
    }

    /// A skip still saves: whatever was answered before it is real data, and the flag has
    /// to go down either way or the tour reopens on the next launch. It deliberately does
    /// not log `intro_done` — abandoning isn't completing, and the two shouldn't be one
    /// number in a funnel.
    private func skip() {
        Track.event("intro_skip", ["card": card.rawValue])
        answers.save()
        onFinish(Intro.landingTab(kana: answers.kana))
    }
}

/// One answer chip.
///
/// Selection is an accent **border**, never a fill. Two reasons, both house rules: green
/// and red belong exclusively to answer feedback in this app, and a filled chip would read
/// as a verdict on a question that has no right answer.
struct IntroChip: View {
    let text: String
    var icon: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).imageScale(.small) }
                Text(text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Theme.accent : Color.primary)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 1))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

#Preview {
    IntroView { _ in }
        .tint(Theme.accent)
}
