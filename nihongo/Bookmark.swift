import SwiftUI
import SwiftData

/// A word the learner saved, filed under one, two or three stars.
///
/// The stars are the *grouping*, not a score — this is the user's own shelf, and what
/// each tier means is theirs to decide (hardest first, exam soon, favourites). That is
/// why the group headers are drawn as literal star glyphs rather than named: naming them
/// would impose a meaning, and would cost three translations in seventeen languages to
/// say something the user already understands.
///
/// Not to be confused with `ChallengeResult.stars`, which *is* a score. They share a
/// symbol and nothing else.
///
/// CloudKit-backed like every other model here: no `@Attribute(.unique)`, every property
/// defaulted, and readers collapse duplicate rows from a sync merge.
@Model
final class Bookmark {
    /// `Vocab.id` — `"lesson/key"`, stable across languages because it is built from the
    /// reading, never the meaning.
    var word: String = ""
    /// Kept alongside `word` so the list can show and sort by lesson without resolving
    /// every id back through `VocabStore`.
    var lesson: Int = 0
    /// 1…3. Clamped on write; a row that arrives outside the range from an older or
    /// newer build is filed under the nearest tier rather than vanishing.
    var stars: Int = 1
    var savedAt: Date = Date.now

    init(word: String, lesson: Int, stars: Int, savedAt: Date = .now) {
        self.word = word
        self.lesson = lesson
        self.stars = Bookmark.clamp(stars)
        self.savedAt = savedAt
    }

    static func clamp(_ stars: Int) -> Int { min(max(stars, 1), 3) }

    // MARK: - Reading

    /// Every bookmark, newest first, one row per word.
    ///
    /// A sync merge can leave two rows for the same word — possibly at different tiers,
    /// if it was re-filed on two devices. The most recent wins, which matches what the
    /// user last did on the device they were holding.
    static func all(context: ModelContext) -> [Bookmark] {
        let rows = (try? context.fetch(FetchDescriptor<Bookmark>())) ?? []
        return Dictionary(rows.map { ($0.word, $0) },
                          uniquingKeysWith: { $0.savedAt >= $1.savedAt ? $0 : $1 })
            .values.sorted { $0.savedAt > $1.savedAt }
    }

    /// The tier a word is filed under, or nil if it isn't bookmarked.
    static func stars(for word: String, context: ModelContext) -> Int? {
        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.word == word })
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.max { $0.savedAt < $1.savedAt }.map { clamp($0.stars) }
    }

    // MARK: - Writing

    /// File `vocab` under `stars`, or remove it when `stars` is nil.
    ///
    /// Deletes *every* row for the word rather than the newest one: duplicates from a
    /// merge would otherwise resurrect a bookmark the user just cleared, which reads as
    /// the app ignoring them.
    static func set(_ stars: Int?, for vocab: Vocab, context: ModelContext) {
        let word = vocab.id
        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.word == word })
        for row in (try? context.fetch(descriptor)) ?? [] { context.delete(row) }
        if let stars {
            context.insert(Bookmark(word: word, lesson: vocab.lesson, stars: stars))
        }
        try? context.save()
    }

    /// none → ★ → ★★ → ★★★ → none. One control, four states, no menu: filing a word is
    /// a one-handed action taken while reading a list, and a picker would turn it into a
    /// decision.
    static func next(after stars: Int?) -> Int? {
        switch stars {
        case nil: return 1
        case 1:   return 2
        case 2:   return 3
        default:  return nil
        }
    }
}

/// The star control on a vocab row. Hollow when unsaved, filled with the tier's count.
struct BookmarkStars: View {
    let vocab: Vocab
    @Environment(\.modelContext) private var context
    @State private var stars: Int?

    var body: some View {
        Button {
            let next = Bookmark.next(after: stars)
            Bookmark.set(next, for: vocab, context: context)
            stars = next
            Track.event("bookmark", ["lesson": vocab.lesson, "stars": next ?? 0])
        } label: {
            // One glyph when unsaved, `stars` of them when saved — so the tier is
            // readable at a glance down a list without counting anything twice.
            HStack(spacing: 1) {
                if let stars {
                    ForEach(0..<stars, id: \.self) { _ in Image(systemName: "star.fill") }
                } else {
                    Image(systemName: "star")
                }
            }
            .font(.caption)
            .foregroundStyle(stars == nil ? Color.secondary.opacity(0.35) : Theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Bookmark"))
        .accessibilityValue(stars.map { "\($0)" } ?? "")
        .task { stars = Bookmark.stars(for: vocab.id, context: context) }
    }
}
