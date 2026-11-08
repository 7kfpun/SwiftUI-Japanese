import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The numbers on Progress, derived once so the screen and the share card cannot disagree.
///
/// Same rules as the screen: duplicate CloudKit rows collapse (days by stamp, challenges
/// by `ChallengeResult.better`, kana by the latest answer), and a challenge counts only
/// once it is actually passed. Nothing here is a stored counter.
struct ProgressStats: Equatable {
    var streak: Streak
    var daysStudied: Int
    var challengesPassed: Int
    var challengesTotal: Int
    var kanaLearned: Int
    var kanaTotal: Int

    static func load(context: ModelContext) -> ProgressStats {
        let days = (try? context.fetch(FetchDescriptor<StudyDay>())) ?? []
        let unique = Set(days.map(\.day))

        let results = (try? context.fetch(FetchDescriptor<ChallengeResult>())) ?? []
        let passed = Dictionary(results.map { ($0.id, $0) },
                                uniquingKeysWith: ChallengeResult.better)
            .values.filter(\.isPassed).count

        let kana = (try? context.fetch(FetchDescriptor<KanaResult>())) ?? []
        let learned = Dictionary(kana.map { ($0.romaji, $0) },
                                 uniquingKeysWith: { $0.timestamp >= $1.timestamp ? $0 : $1 })
            .values.filter(\.isCorrect).count

        return ProgressStats(streak: Streak(days: unique),
                             daysStudied: unique.count,
                             challengesPassed: passed,
                             challengesTotal: challengeTotal,
                             kanaLearned: learned,
                             kanaTotal: kanaTotal)
    }

    /// Every rung of every lesson. Follows `Course.current`, so Minna and JLPT stay honest.
    static var challengeTotal: Int {
        (1...Course.current.lessonCount).reduce(0) {
            $0 + Challenge.count(wordCount: VocabStore.wordCount($1))
        }
    }

    /// Distinct kana cells, counted from the chart rather than a literal that would rot.
    static var kanaTotal: Int {
        let cells = (KanaData.seion + KanaData.dakuon + KanaData.youon).flatMap { $0 }
        return Set(cells.filter { !$0.isEmpty }.map(\.romaji)).count
    }
}

/// The image a streak is shared as. Fixed 4:5, rendered off screen, so it must not
/// depend on the live screen: no Dynamic Type, no dark mode, no safe area. One
/// appearance — light — so a card sent at night still reads in a chat thread.
struct ShareCardView: View {
    static let size = CGSize(width: 360, height: 450)

    var stats: ProgressStats

    /// Light ink, taken from the course accent rather than `Theme.accent`, which flips
    /// with the appearance. The export forces light mode and these colours agree with it.
    private var accent: Color {
        Color(red: Course.current.accentLight.r,
              green: Course.current.accentLight.g,
              blue: Course.current.accentLight.b)
    }
    private let text = Color(red: 0.12, green: 0.14, blue: 0.16)
    private let secondary = Color(red: 0.36, green: 0.39, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "character.book.closed")
                    .font(Theme.display(15, weight: .semibold))
                    .foregroundStyle(accent)
                Text(Course.current.displayName)
                    .font(Theme.display(15, weight: .semibold))
                    .foregroundStyle(text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 12)

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: stats.streak.studiedToday ? "flame.fill" : "flame")
                        .font(Theme.display(34, weight: .semibold))
                    Text("\(stats.streak.current)")
                        .font(Theme.display(68, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(Color.streak)
                Text(L.t("%@-day streak", "\(stats.streak.current)"))
                    .font(Theme.display(16, weight: .semibold))
                    .foregroundStyle(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)

            week
                .padding(.top, 16)

            Spacer(minLength: 16)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    tile(L.t("Best streak"), "\(stats.streak.best)")
                    tile(L.t("Days studied"), "\(stats.daysStudied)")
                }
                HStack(spacing: 8) {
                    tile(L.t("Challenges passed"), "\(stats.challengesPassed) / \(stats.challengesTotal)")
                    tile(L.t("Kana learned"), "\(stats.kanaLearned) / \(stats.kanaTotal)")
                }
            }

            Spacer(minLength: 16)

            Text(L.t("Learn Japanese with me"))
                .font(Theme.display(13, weight: .medium))
                .foregroundStyle(secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 0.98),
                    accent.opacity(0.22),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .environment(\.colorScheme, .light)
    }

    /// Seven dots. A gap is a day that was not studied — the same strip as the hero,
    /// without weekday letters, which overflow a card in the longer scripts.
    private var week: some View {
        HStack(spacing: 8) {
            ForEach(stats.streak.lastWeek(), id: \.day) { entry in
                Circle()
                    .fill(entry.studied ? Color.streak : Color.black.opacity(0.08))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.streak, lineWidth: entry.day == stats.streak.today ? 2 : 0)
                            .frame(width: 18, height: 18)
                    )
                    .frame(width: 18, height: 18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.display(12, weight: .medium))
                .foregroundStyle(secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(value)
                .font(Theme.display(20, weight: .bold))
                .foregroundStyle(text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// PNG the share sheet can hand to Messages. `ShareLink` needs `Transferable`;
/// `UIActivityViewController` takes the `UIImage` directly.
/// `nonisolated` so this can be `Transferable` (`Sendable`). The app target isolates
/// types to the main actor by default, and a main-actor image cannot cross the share sheet.
nonisolated struct ShareCardFile: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { file in
            file.image.pngData() ?? Data()
        }
    }
}

enum ShareCard {
    /// Off-screen render at 3× so a story crop stays sharp. Nil when the renderer
    /// produces nothing — the share control hides rather than sending an empty file.
    @MainActor
    static func render(_ stats: ProgressStats) -> UIImage? {
        let renderer = ImageRenderer(content:
            ShareCardView(stats: stats)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: ShareCardView.size.width,
                                                 height: ShareCardView.size.height)
        return renderer.uiImage
    }

    /// The recommend nudge's payload plus the card, when it renders. The text and the
    /// listing stay — the image is the extra, and a failed render leaves them alone.
    @MainActor
    static func activityItems(campaign: SharePrompt.Campaign, context: ModelContext) -> [Any] {
        var items: [Any] = []
        let stats = ProgressStats.load(context: context)
        // A card of nothing studied is the same picture the Progress screen refuses to offer.
        if stats.daysStudied > 0, let image = render(stats) {
            items.append(image)
        }
        items.append(SharePrompt.appStoreURL(campaign: campaign))
        items.append(SharePrompt.shareText(campaign: campaign))
        return items
    }
}

#Preview {
    ShareCardView(stats: ProgressStats(
        streak: Streak(days: [20261025, 20261026, 20261027], today: 20261027),
        daysStudied: 12,
        challengesPassed: 28,
        challengesTotal: 312,
        kanaLearned: 46,
        kanaTotal: 104))
}
