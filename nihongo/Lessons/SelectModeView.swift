import SwiftUI
import SwiftData

struct SelectModeView: View {
    let lesson: Lesson
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.deviceDefaultLanguage
    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var context
    @State private var showPaywall = false
    @State private var results: [Int: ChallengeResult] = [:]

    // Re-resolve so entering a mode uses the current Meanings language.
    private var current: Lesson { VocabStore.lesson(lesson.number, language) }

    /// The one place lesson gating is enforced: locked rows open the paywall instead of
    /// navigating, so no practice screen has to police access itself.
    private var locked: Bool { Gating.isLocked(lesson: lesson.number, isPremium: store.isPremium) }

    private var challengeCount: Int { Challenge.count(wordCount: current.entries.count) }

    var body: some View {
        List {
            // Study first, test second — the two halves are separated because they ask
            // different things of you: the Learn modes are untested practice you can
            // wander through, the ladder is scored and gates the next rung.
            //
            // Rows run shallow → deep, the order you'd actually study new material:
            // meet the words (Vocab List), recognise them (Flashcards), choose under a
            // gentle 50/50 ask (Train, audio prompts included), then produce them from
            // tiles (Learn) — the last stop before the Challenge ladder tests you.
            Section {
                // Vocab List is free on every lesson — browsing and search stay open.
                NavigationLink { VocabListView(lesson: current) } label: {
                    ModeRow(icon: "list.bullet", title: L.t("Vocab List"),
                            subtitle: L.t("Browse & hear all words"))
                }
                mode(icon: "rectangle.on.rectangle.angled", title: L.t("Flashcards"),
                     subtitle: L.t("Swipe right if you know it")) { FlashcardView(lesson: current) }
                mode(icon: "arrow.left.arrow.right", title: L.t("Train"),
                     subtitle: L.t("Swipe to the right answer")) { TrainView(lesson: current) }
                mode(icon: "square.grid.2x2", title: L.t("Learn"),
                     subtitle: L.t("Rebuild the reading from tiles")) { LearnView(lesson: current) }
            } header: {
                Text(L.t("Learn")).font(Theme.title(.footnote))
            }

            Section {
                ForEach(1...challengeCount, id: \.self) { i in challengeRow(i) }
            } header: {
                // The tally is part of the header, not a row datum, so it takes the header
                // face too — it just keeps its monospaced digits so it doesn't jitter as
                // rungs are cleared.
                HStack {
                    Text(L.t("Challenge"))
                    Spacer()
                    Text("\(ChallengeResult.passedCount(results: results)) / \(challengeCount)")
                        .monospacedDigit()
                }
                .font(Theme.title(.footnote))
            } footer: {
                Text(L.t("Clear every challenge to master the lesson."))
            }
        }
        .navigationTitle(L.t("Lesson %@", "\(lesson.number)"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Track.screen("select_mode", ["lesson": lesson.number])
            reloadResults()
        }
        .sheet(isPresented: $showPaywall) { PaywallView(source: "select_mode_locked") }
    }

    /// Re-read on every appear so a challenge finished and popped back updates its row.
    private func reloadResults() {
        results = ChallengeResult.byIndex(lesson: lesson.number, context: context)
    }

    /// A rung of the ladder: locked by premium, locked by progress, or playable.
    @ViewBuilder
    private func challengeRow(_ i: Int) -> some View {
        let result = results[i]
        let openable = ChallengeResult.isUnlocked(index: i, results: results)

        if locked {
            Button {
                showPaywall = true
                Track.event("locked_challenge", ["lesson": lesson.number, "index": i])
            } label: {
                ChallengeRow(index: i, result: nil, state: .premium)
            }
            .buttonStyle(.plain)
        } else if openable {
            NavigationLink {
                ChallengeView(lesson: current, index: i, total: challengeCount)
            } label: {
                ChallengeRow(index: i, result: result, state: .open)
            }
        } else {
            ChallengeRow(index: i, result: nil, state: .sequential)
        }
    }

    /// A premium-gated mode row: navigates when unlocked, opens the paywall when not.
    @ViewBuilder
    private func mode<D: View>(icon: String, title: String, subtitle: String,
                               @ViewBuilder destination: @escaping () -> D) -> some View {
        if locked {
            Button {
                showPaywall = true
                Track.event("locked_mode", ["mode": title, "lesson": lesson.number])
            } label: {
                ModeRow(icon: icon, title: title, subtitle: subtitle, locked: true)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink { destination() } label: {
                ModeRow(icon: icon, title: title, subtitle: subtitle)
            }
        }
    }
}

/// Why a challenge row isn't playable — the two lock reasons look different on
/// purpose, because only one of them is something the user can fix by paying.
enum ChallengeRowState { case open, sequential, premium }

private struct ChallengeRow: View {
    let index: Int
    let result: ChallengeResult?
    let state: ChallengeRowState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(passed ? Theme.accent : Color.secondary.opacity(0.15))
                    .frame(width: 30, height: 30)
                if passed {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(state == .open ? .primary : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("Challenge %@", "\(index)"))
                    .font(Theme.title(.headline))
                    .foregroundStyle(state == .open ? .primary : .secondary)
                if let result, result.bestScore > 0 {
                    Text(L.t("Best %@%", "\(result.bestScore)"))
                        .font(.caption).foregroundStyle(.secondary)
                } else if state == .sequential {
                    // Name the concrete goal ("Beat Challenge 2") rather than describe
                    // the restriction — the row always knows exactly which rung blocks it.
                    Text(L.t("Beat Challenge %@ to unlock", "\(index - 1)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            switch state {
            case .open:       StarRow(stars: result?.stars ?? 0)
            case .sequential: Image(systemName: "lock.fill").font(.footnote).foregroundStyle(.tertiary)
            case .premium:    Image(systemName: "lock.fill").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var passed: Bool { result?.isPassed == true }
}

private struct ModeRow: View {
    let icon: String, title: String, subtitle: String
    var locked = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(locked ? Color.secondary : Theme.accent)
            // Row name in the title face, subtitle left on the system font — the mode's
            // name is a heading, "Swipe right if you know it" is a sentence about it.
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.title(.headline))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            if locked {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .foregroundStyle(.primary)   // keep the label neutral inside a plain Button
    }
}
