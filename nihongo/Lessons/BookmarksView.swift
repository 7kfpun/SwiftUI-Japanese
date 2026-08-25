import SwiftUI
import SwiftData

/// The saved-words shelf, in three groups.
///
/// Headers are literal star glyphs rather than words. What each tier means is the user's
/// own decision — hardest first, exam soon, favourites — so naming them would impose a
/// meaning, and three names would cost 51 translations to say something the stars
/// already say.
struct BookmarksView: View {
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.deviceDefaultLanguage
    @Environment(\.modelContext) private var context
    @State private var groups: [Int: [Vocab]] = [:]

    private var isEmpty: Bool { groups.values.allSatisfy(\.isEmpty) }

    var body: some View {
        Group {
            if isEmpty {
                empty
            } else {
                List {
                    // Highest tier first: whatever three stars means to someone, it is
                    // the group they came here for.
                    ForEach([3, 2, 1], id: \.self) { tier in
                        if let words = groups[tier], !words.isEmpty {
                            Section {
                                ForEach(words) { VocabRow(vocab: $0, showLesson: true,
                                                          surface: "bookmarks") }
                            } header: {
                                Text(String(repeating: "★", count: tier))
                                    .font(Theme.title(.footnote))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L.t("Bookmarks"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload(); Track.screen("bookmarks") }
        .onChange(of: language) { reload() }
    }

    private var empty: some View {
        EmptyStatePanel(text: L.t("Tap the star beside any word to save it here.")) {
            Image(systemName: "star")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent.opacity(0.5))
        }
    }

    /// Resolve saved ids back to words in the *current* meaning language.
    ///
    /// One pass over the bookmarked lessons rather than `allVocab`: a JLPT user may have
    /// saved from any of 201 lessons, and building a 7,972-entry index to find twelve
    /// words would be paid on every appearance.
    private func reload() {
        let saved = Bookmark.all(context: context)
        var byID: [String: Vocab] = [:]
        for lesson in Set(saved.map(\.lesson)) where Course.current.hasLesson(lesson) {
            for word in VocabStore.lesson(lesson, language).entries { byID[word.id] = word }
        }
        // Keyed by tier, each in save order (newest first, from `Bookmark.all`). A row
        // whose word no longer resolves — a dataset that dropped an entry — is skipped
        // rather than rendered blank.
        groups = Dictionary(grouping: saved.compactMap { row in
            byID[row.word].map { (Bookmark.clamp(row.stars), $0) }
        }, by: \.0).mapValues { $0.map(\.1) }
    }
}
