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
    @State private var bookmarkCount = 0

    /// Every rung of every lesson in this course. Arithmetic over the bundled data, so it
    /// follows `Course.current` — 50 lessons of Minna or 201 of JLPT — with no constant
    /// to keep in step.
    private var challengesTotal: Int {
        (1...Course.current.lessonCount).reduce(0) { $0 + Challenge.count(wordCount: VocabStore.wordCount($1)) }
    }

    /// Distinct kana cells in the chart, counted rather than hardcoded: the chart is
    /// generated from the submodule and a literal here would rot the moment it changed.
    private var kanaTotal: Int {
        let cells = (KanaData.seion + KanaData.dakuon + KanaData.youon).flatMap { $0 }
        return Set(cells.filter { !$0.isEmpty }.map(\.romaji)).count
    }

    var body: some View {
        NavigationStack {
            // Always a `List`, even with nothing studied yet. The empty state used to
            // replace the whole screen, which took Bookmarks with it — and bookmarks are
            // filled from the Vocab List, free on every lesson and needing no challenge
            // at all. Someone could save a dozen words and then find no way back to them.
            List {
                if daysStudied == 0 {
                    Section {
                        empty
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                } else {
                    // The streak is the reason to come back, so it gets the top of
                    // the screen rather than a row among five equals.
                    Section {
                        StreakHero(streak: streak)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                        // The week strip above answers "am I on track"; this answers
                        // "have I been here before" — gaps and runs over a season.
                        StudyCalendar(streak: streak)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                        // Tiles rather than rows: four numbers read at a glance as a
                        // grid, and a list of four equal rows made each one look minor.
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                            GridItem(.flexible(), spacing: 10)],
                                  spacing: 10) {
                            StatTile(symbol: "trophy", label: L.t("Best streak"),
                                     value: "\(streak.best)")
                            StatTile(symbol: "calendar", label: L.t("Days studied"),
                                     value: "\(daysStudied)")
                            StatTile(symbol: "checkmark.seal", label: L.t("Challenges passed"),
                                     value: "\(challengesPassed)", total: "\(challengesTotal)")
                            StatTile(symbol: "character.book.closed", label: L.t("Kana learned"),
                                     value: "\(kanaLearned)", total: "\(kanaTotal)")
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                    .listRowSeparator(.hidden)
                }

                // The shelf belongs with the rest of "what's mine" rather than on a tab
                // of its own — it's a place you go on purpose, not one you need in front
                // of you. Shown unconditionally: it is the only route to saved words.
                Section {
                    NavigationLink {
                        BookmarksView()
                    } label: {
                        HStack(spacing: 12) {
                            IconWell(systemName: "star")
                            Text(L.t("Bookmarks"))
                                .font(Theme.title(.body, weight: .regular))
                            Spacer(minLength: 12)
                            // The count is what makes the row worth showing on an
                            // otherwise-empty screen: it says whether there's anything
                            // behind it before you tap.
                            if bookmarkCount > 0 {
                                Text("\(bookmarkCount)")
                                    .font(.body.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
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
        EmptyStatePanel(text: L.t("Take a challenge or a kana quiz to start a streak.")) {
            Image("skill-tree")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 180)
                .foregroundStyle(Theme.accent.opacity(0.7))
        }
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

        // Deduped by word, matching `Bookmark.all` — a merge can leave two rows for one
        // word, and counting both would promise more on the shelf than it holds.
        bookmarkCount = Bookmark.all(context: context).count

        let kana = (try? context.fetch(FetchDescriptor<KanaResult>())) ?? []
        // Same dedupe, by kana: the most recent row for each is the one that counts.
        kanaLearned = Dictionary(kana.map { ($0.romaji, $0) },
                                 uniquingKeysWith: { $0.timestamp >= $1.timestamp ? $0 : $1 })
            .values.filter(\.isCorrect).count
    }
}

/// One counter as a tile: what it is, then the number, with its ceiling (if it has one)
/// set smaller so the eye reads the achievement before the denominator.
private struct StatTile: View {
    let symbol: String
    let label: String
    let value: String
    var total: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IconWell(systemName: symbol)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.title(.title2, weight: .bold))
                    .monospacedDigit()
                if let total {
                    Text("/ \(total)")
                        .font(Theme.title(.subheadline))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .cardChrome(radius: Theme.Radius.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(total.map { "\(value) / \($0)" } ?? value)
    }
}

/// Twelve weeks of study days, a column per week, the current week last.
///
/// Built from `Streak.days`, so it can never disagree with the streak above it, and
/// laid out on `StudyDay.calendar` — the stamps are Gregorian whatever the region, and
/// reading them back through `Calendar.current` would shift every square. Studied days
/// take the streak's amber: a study day is a link in the streak, not an answer.
struct StudyCalendar: View {
    let streak: Streak
    static let weeks = 12

    /// Columns of seven stamps, oldest week first. `nil` for days still to come.
    private var columns: [[Int?]] {
        let calendar = StudyDay.calendar
        var c = DateComponents()
        c.year = streak.today / 10_000; c.month = (streak.today / 100) % 100; c.day = streak.today % 100
        let date = calendar.date(from: c) ?? .now
        // Days since the week began, on the calendar's own first weekday.
        let intoWeek = (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
        let first = StudyDay.stamp(streak.today, offsetBy: -((Self.weeks - 1) * 7 + intoWeek),
                                   calendar: calendar)
        return (0..<Self.weeks).map { week in
            (0..<7).map { day in
                let offset = week * 7 + day
                return offset > (Self.weeks - 1) * 7 + intoWeek
                    ? nil : StudyDay.stamp(first, offsetBy: offset, calendar: calendar)
            }
        }
    }

    var body: some View {
        let columns = columns
        let studied = columns.joined().compactMap { $0 }.filter(streak.days.contains).count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.t("Last 12 weeks")).font(Theme.title(.subheadline))
                Spacer(minLength: 8)
                Text(L.t("%@ days", "\(studied)"))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(columns.indices, id: \.self) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { day in
                            cell(columns[week][day])
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .cardChrome(radius: Theme.Radius.deck)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Last 12 weeks"))
        .accessibilityValue(L.t("%@ days", "\(studied)"))
    }

    private func cell(_ stamp: Int?) -> some View {
        let shape = Theme.rounded(Theme.Radius.tick)
        return shape
            .fill(stamp.map { streak.days.contains($0) ? Color.streak : Color.secondary.opacity(0.15) }
                  ?? .clear)
            .overlay(shape.strokeBorder(Theme.line, lineWidth: stamp == nil ? 1 : 0))
            // Today is ringed whether or not it's done, as on the week strip.
            .overlay(shape.inset(by: -2.5).stroke(Color.streak, lineWidth: stamp == streak.today ? 1.5 : 0))
            .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    StatsView()
        .tint(Theme.accent)
        .modelContainer(for: [KanaResult.self, ChallengeResult.self, StudyDay.self, Bookmark.self], inMemory: true)
}
