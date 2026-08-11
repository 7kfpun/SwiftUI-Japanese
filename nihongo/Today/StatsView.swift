import SwiftUI
import SwiftData

/// What the learner has actually done — streak, days, challenges, kana.
///
/// Named `StatsView` rather than `ProgressView` because SwiftUI already owns that name,
/// and shadowing it would make every spinner in the app ambiguous.
///
/// Every number is **derived from stored results**, never stored as a running total.
/// A counter has to be maintained correctly at every write and across two devices
/// merging out of order; it gets it wrong once and is never trusted again. Deriving also
/// means this screen was true retroactively the day it shipped — someone with a year of
/// challenge history sees that history, not zero.
struct StatsView: View {
    @Environment(\.modelContext) private var context

    @State private var streak = Streak(days: [])
    @State private var daysStudied = 0
    @State private var challengesPassed = 0
    @State private var kanaLearned = 0

    /// Every rung of every lesson in this course. Arithmetic over the bundled data, so it
    /// follows `Course.current` — 50 lessons of Minna or 201 of JLPT — with no constant
    /// to keep in step.
    private var challengesTotal: Int {
        VocabStore.lessons().reduce(0) { $0 + Challenge.count(wordCount: $1.entries.count) }
    }

    /// Distinct kana cells in the chart, counted rather than hardcoded: the chart is
    /// generated from the submodule and a literal here would rot the moment it changed.
    private var kanaTotal: Int {
        let cells = (KanaData.seion + KanaData.dakuon + KanaData.youon).flatMap { $0 }
        return Set(cells.filter { !$0.isEmpty }.map(\.romaji)).count
    }

    var body: some View {
        NavigationStack {
            Group {
                if daysStudied == 0 {
                    empty
                } else {
                    List {
                        // The streak is the reason to come back, so it gets the top of
                        // the screen rather than a row among five equals.
                        Section {
                            StreakHero(streak: streak)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        row("trophy", L.t("Best streak"), "\(streak.best)")
                        row("calendar", L.t("Days studied"), "\(daysStudied)")
                        row("checkmark.seal", L.t("Challenges passed"),
                            "\(challengesPassed) / \(challengesTotal)")
                        row("character.book.closed", L.t("Kana learned"),
                            "\(kanaLearned) / \(kanaTotal)")

                        // The shelf belongs with the rest of "what's mine" rather than
                        // on a tab of its own — it's a place you go on purpose, not one
                        // you need in front of you.
                        Section {
                            NavigationLink {
                                BookmarksView()
                            } label: {
                                Label {
                                    Text(L.t("Bookmarks"))
                                        .font(Theme.title(.body, weight: .regular))
                                } icon: {
                                    Image(systemName: "star").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L.t("Progress"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { reload(); Track.screen("progress") }
        }
    }

    /// The one place an illustration earns its keep. It is not a control, so it costs
    /// nothing in Dynamic Type or tap targets, and an empty list with five zeroes reads
    /// as a broken screen rather than a new one.
    private var empty: some View {
        VStack(spacing: 16) {
            Image("skill-tree")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 180)
                .foregroundStyle(Theme.accent.opacity(0.7))
            Text(L.t("Answer anything to start a streak."))
                .font(Theme.title(.subheadline, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }

    private func row(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack {
            Label {
                Text(label).font(Theme.title(.body, weight: .regular))
            } icon: {
                Image(systemName: symbol).foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 12)
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    /// One fetch per model, on appear. Nothing here can change while this screen is up —
    /// every counter moves only by answering something, which happens on another tab.
    private func reload() {
        let days = (try? context.fetch(FetchDescriptor<StudyDay>())) ?? []
        // By `Set`, not `count`: a sync merge can leave two rows for the same day, and
        // counting both would report more days studied than the calendar contains.
        let unique = Set(days.map(\.day))
        daysStudied = unique.count
        streak = Streak(days: unique)

        let results = (try? context.fetch(FetchDescriptor<ChallengeResult>())) ?? []
        challengesPassed = Dictionary(results.map { ($0.id, $0) },
                                      uniquingKeysWith: ChallengeResult.better)
            .values.filter(\.isPassed).count

        let kana = (try? context.fetch(FetchDescriptor<KanaResult>())) ?? []
        // Same dedupe, by kana: the most recent row for each is the one that counts.
        kanaLearned = Dictionary(kana.map { ($0.romaji, $0) },
                                 uniquingKeysWith: { $0.timestamp >= $1.timestamp ? $0 : $1 })
            .values.filter(\.isCorrect).count
    }
}

#Preview {
    StatsView()
        .tint(Theme.accent)
        .modelContainer(for: [KanaResult.self, ChallengeResult.self, StudyDay.self, Bookmark.self], inMemory: true)
}
