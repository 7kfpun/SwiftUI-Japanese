import SwiftUI
import SwiftData

/// The feedback sheet — a native form, not a web page.
///
/// It replaces an Airtable form that opened in `SFSafariViewController` and collected
/// nothing (see `Feedback`). Everything here that looks like a small courtesy is really
/// about that: the keyboard is already up, the only required field is the message, the
/// diagnostic half of the report is filled in without being asked for, and the send is
/// one tap from a screen that never left the app.
///
/// One thing it deliberately does *not* do is wait. `Survey.submit` is fire-and-forget
/// over Firestore's offline queue, so a report typed on a plane lands when the network
/// comes back and the sheet closes at the speed of the tap either way. The confirmation
/// is honest about that: "on its way", not "delivered".
struct FeedbackView: View {
    let source: Feedback.Source
    /// 1…5 when the star row sent the user here, 0 otherwise.
    var stars: Int = 0
    /// The word the sender was looking at, when the flag on a practice screen opened this.
    /// Nil everywhere else — the sheet has no way to name a word on its own, which is what
    /// the flag exists for (see `ReportItemButton`).
    var item: Feedback.Item? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var modelContext
    /// Only to resolve `item` for display — the row shows the sender the entry their report
    /// is being attached to, in the language they read meanings in.
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.deviceDefaultLanguage

    @State private var draft = FeedbackDraft()
    @State private var sent = false
    @FocusState private var messageFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if sent { confirmation } else { form }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .navigationTitle(L.t("Send feedback"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !sent {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L.t("Cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L.t("Send")) { send() }
                            .fontWeight(.semibold)
                            .disabled(!draft.isValid)
                    }
                }
            }
        }
        .onAppear {
            draft.stars = stars
            // Arriving from the flag: the bucket and the word are both already known, so the
            // form opens with the second-level answer filled in and one question left — what
            // is actually wrong with it. Set without `withAnimation`, so the section is
            // simply *there* on the first frame rather than animating in under the sender.
            if let item {
                draft.kind = .content
                draft.item = item
            }
            Track.event("feedback_opened", ["source": source.rawValue])
            // The message is the only required field, so the keyboard belongs on it from
            // the first frame — the kind chips below are one tap each and read fine over
            // a raised keyboard, while a form that opens dormant asks for a tap before
            // anything can be said.
            messageFocused = true
        }
        // In `onDisappear` rather than in the Cancel button, so a swipe-down counts as an
        // abandon too. An open-to-send funnel where one of the two ways of leaving is
        // invisible measures the wrong thing.
        .onDisappear {
            guard !sent else { return }
            Track.event("feedback_dismissed", ["source": source.rawValue,
                                               "message_length": draft.trimmedMessage.count])
        }
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Arriving from the star row means a rating already exists and is shown as a
                // fact. Anywhere else it's an invitation — which is worth offering, because
                // a written report with a score attached is far easier to triage than either
                // half alone, and Settings was previously the one route that produced neither.
                if source == .rating { rating } else { ratingPicker }
                kindPicker
                followUp
                messageField
                emailField
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The stars the user just picked, shown back to them and not editable here.
    ///
    /// They travel with the message so a complaint can be read next to the rating that
    /// produced it, and showing them is the honest half of that: the row carries a number
    /// the sender gave on a different screen, so this is where they find that out.
    private var rating: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= draft.stars ? "star.fill" : "star")
                        .foregroundStyle(i <= draft.stars ? Theme.accent : Color.secondary.opacity(0.4))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("%@ stars", "\(draft.stars)"))

            Text(L.t("Your rating comes with this message."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// The same star row, but tappable — shown when the sheet was *not* opened from the star
    /// row, so someone writing in from Settings can attach a score if they want to.
    ///
    /// Optional, exactly like the email: 0 means unrated, `isValid` ignores it, and nothing
    /// nags for it. It also can't be un-set once given, which is a deliberate small loss —
    /// a "clear" affordance on an optional field is more chrome than the field is worth.
    ///
    /// Not `RatingSheet`: that type owns the earned moment, including the deliberate beat
    /// before it dismisses itself and the routing to Apple's review sheet. Reusing it here
    /// would drag a dismissal and a review handoff into a form the sender hasn't submitted
    /// yet. Only the star row's *look* is shared, and the accessibility label literally is.
    private var ratingPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(L.t("How would you rate it?"))
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Button { draft.stars = i } label: {
                        Image(systemName: i <= draft.stars ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(i <= draft.stars ? Theme.accent
                                                             : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("%@ stars", "\(i)"))
                }
            }
        }
    }

    /// One chip per row rather than a grid: these labels are sentences, and in the longer
    /// of the 17 languages a two-column grid re-flows into a ragged 2 + 2 with a hole. A
    /// single column also gives every option the same width, which is what makes four
    /// chips read as one set of choices.
    ///
    /// `IntroChip` on purpose — the accent-**border** selection is a house rule (green and
    /// red belong exclusively to answer feedback), and it should live in one place rather
    /// than be re-implemented per screen.
    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(L.t("What's this about?"))
            ForEach(Feedback.Kind.allCases) { kind in
                IntroChip(text: kind.title, icon: kind.icon, selected: draft.kind == kind) {
                    // Animated because picking a bucket can *reveal* the section below, and
                    // an un-animated insertion reads as the form jumping rather than as an
                    // answer opening a follow-up question. Nothing above this point moves,
                    // and Send is a toolbar item — so no reveal can push it off screen,
                    // however long the labels run at an accessibility text size.
                    withAnimation(.easeOut(duration: 0.22)) { draft.kind = kind }
                }
            }
        }
    }

    /// The second-level question, which exists because the first level doesn't route a
    /// report anywhere on its own: "something's broken" needs a part of the app, and "a
    /// wrong word" needs the word.
    ///
    /// It sits directly under the chip that revealed it, so the new content appears exactly
    /// where the sender's attention already is — under their finger — rather than below the
    /// message box where a raised keyboard would hide it.
    @ViewBuilder
    private var followUp: some View {
        switch draft.kind {
        case .bug:     areaPicker.transition(.opacity)
        case .content: itemSection.transition(.opacity)
        default:       EmptyView()
        }
    }

    /// `IntroChip` again, one per row, for both reasons `kindPicker` gives.
    ///
    /// Optional like everything else here — eight chips and none of them preselected, so a
    /// sender who doesn't recognise their own bug in the list simply says nothing and the
    /// prose does the work. See `Feedback.Area` for what each one maps to in the code.
    private var areaPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(L.t("Which part isn't working?"))
            ForEach(Feedback.Area.allCases) { area in
                IntroChip(text: area.title, icon: area.icon, selected: draft.area == area) {
                    withAnimation(.easeOut(duration: 0.22)) { draft.area = area }
                }
            }
        }
    }

    /// What a wrong-word report knows about the word.
    ///
    /// Two states, and the second one is deliberately not a picker. Opened from the flag on
    /// a practice screen, the entry is already known and is shown back to the sender — the
    /// same courtesy the star row gets, and for the same reason: the row carries something
    /// they didn't type, so this is where they find that out.
    ///
    /// Opened cold from Settings, there is no word and no way to name one. A searchable list
    /// of all 2,089 entries was the alternative; it was dropped because the flag already
    /// knows the answer at the moment it matters, and the list would only serve someone
    /// re-finding a word they had already walked away from. So this points at the better
    /// route instead of being a dead end, and the report still sends without it — `lesson`
    /// and `item` go to the wire as 0 and "".
    @ViewBuilder
    private var itemSection: some View {
        if let vocab = reportedVocab {
            attachedItem {
                // The row every list of words in this app uses, so the entry under report
                // looks exactly like the entry that was on screen a tap ago. Its own tap
                // still speaks the word, which is the cheapest possible confirmation that
                // this is the right one — and for a mis-cut clip it *is* the bug.
                VocabRow(vocab: vocab, showLesson: true)
            }
        } else if let romaji = draft.item?.romaji {
            // A kana item (lesson 0), or a romaji the bundled data no longer has after a
            // regeneration. Nothing to resolve, so the identifier itself is what's shown —
            // still honest about what travels with the message.
            attachedItem {
                Text(romaji)
                    .font(Theme.title(.headline))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(L.t("Open the word and tap the flag to report it exactly."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// The attached word in the same chrome the two text fields wear — a `Theme.surface`
    /// panel on the sheet's `Theme.canvas`, so it reads as a filled-in field rather than as
    /// loose text between two questions. The note under it is the exact counterpart of the
    /// star row's line, because it says the same thing about a different field.
    private func attachedItem<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            Text(L.t("This word comes with your message."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// The reported entry resolved in the current Meanings language, or nil when there is
    /// nothing to resolve: no item, a kana item (`lesson == 0`), or a romaji that a data
    /// regeneration has since renamed.
    private var reportedVocab: Vocab? {
        guard let item = draft.item, Course.current.hasLesson(item.lesson) else { return nil }
        return VocabStore.lesson(item.lesson, language).entries.first { $0.romaji == item.romaji }
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(L.t("What happened?"))
            // `lineLimit(4...12)` and never a `frame(height:)`: the box has to be four
            // lines tall at every Dynamic Type size, and a fixed height would clip the
            // first line of text at the accessibility sizes.
            TextField(L.t("The more detail the better — which word, which screen, what you expected."),
                      text: $draft.message, axis: .vertical)
                .lineLimit(4...12)
                .focused($messageFocused)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        }
    }

    /// Below the message, always. The message is the thing worth having; the address is an
    /// afterthought, and the order of the two says so.
    ///
    /// Optional in the label, optional in the gate (`FeedbackDraft.isValid` never looks at
    /// it) and never format-checked. A form that refuses a malformed address trades a
    /// whole bug report for a typo.
    private var emailField: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(L.t("Email"))
            TextField(L.t("you@example.com"), text: $draft.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            Text(L.t("Optional — only if you'd like a reply."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(Theme.title(.headline))
            .multilineTextAlignment(.leading)
    }

    // MARK: - Sent

    /// A beat of acknowledgement before the sheet goes.
    ///
    /// `Theme.accent`, not `Theme.correct`: green in this app means "your answer was
    /// right" and nothing else, and a green tick here would be the app grading the report.
    private var confirmation: some View {
        VStack(spacing: 14) {
            Image(systemName: "paperplane.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text(L.t("Thanks — it's on its way."))
                .font(Theme.title(.title3))
                .multilineTextAlignment(.center)
            Text(L.t("We read every one of these."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }

    private func send() {
        guard let submission = draft.submission(source: source) else { return }
        Survey.submit(submission,
                      context: Survey.Context(store: store, modelContext: modelContext))
        Track.event("feedback_submitted", draft.trackParams(source: source))
        sent = true
        messageFocused = false
        // Long enough to read, short enough that nobody reaches for the close button.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismiss() }
    }
}

/// The flag: report the word on screen, from the screen it's on.
///
/// This is the primary way a wrong meaning, reading or clip gets reported, because it is the
/// only one that doesn't ask the sender to find the word again. It opens the same sheet with
/// `kind` and the entry already filled in, leaving one question — what's wrong with it.
///
/// **A toolbar item, never an overlay on the card.** Every screen that carries it but
/// `ChallengeView` is swipe-driven (`FlashcardScreen` and `TrainView` through `SwipeCard`,
/// `LearnView` through `cardPager`), and a control sitting on the card competes with the
/// horizontal drag that grades or turns it — the exact failure `CLAUDE.md` records from the
/// intro's sample cards. The toolbar is outside the gesture's view entirely, and it puts the
/// flag in the same place on every screen that offers it.
///
/// **A `.sheet`, never a `fullScreenCover`.** A sheet leaves the presenting view in the
/// hierarchy, so no screen's `onDisappear` runs while a report is being written. That
/// matters most on `ChallengeView`, whose `onDisappear` logs `challenge_abandon` for a run
/// left past question 1 and fires the exit interstitial: a cover would log an abandon per
/// report and quietly corrupt the funnel. It also matters that the sheet dismisses back to
/// the same screen — the run, the deck and the score are all untouched `@State` behind it.
struct ReportItemButton: View {
    let item: Feedback.Item
    @State private var reporting = false

    var body: some View {
        Button { reporting = true } label: {
            Image(systemName: "flag")
        }
        // The label names the flag the copy in the sheet also names ("tap the flag"), so the
        // two describe one thing. No visible text: it shares a toolbar with the sound toggle
        // on three of the four screens, and a word there would crowd the counter between them.
        .accessibilityLabel(L.t("Report a wrong word"))
        .sheet(isPresented: $reporting) {
            FeedbackView(source: .card, item: item)
        }
    }
}

#Preview {
    FeedbackView(source: .rating, stars: 2)
        .tint(Theme.accent)
        .environment(Store())
        .modelContainer(for: [KanaResult.self, ChallengeResult.self, StudyDay.self], inMemory: true)
}

#Preview("From the flag") {
    FeedbackView(source: .card, item: Feedback.Item(lesson: 2, romaji: "tsukue"))
        .tint(Theme.accent)
        .environment(Store())
        .modelContainer(for: [KanaResult.self, ChallengeResult.self, StudyDay.self], inMemory: true)
}
