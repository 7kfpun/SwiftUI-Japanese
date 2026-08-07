import SwiftUI
import SwiftData
import WidgetKit

/// Pure daily-picker: restore a saved selection by id (order preserved), else pick
/// `count` at random. Pure so it's unit-testable.
enum DailyPicker {
    static func pick(from all: [Vocab], count: Int, savedIDs: [String]) -> [Vocab] {
        let restored = savedIDs.compactMap { id in all.first { $0.id == id } }
        return restored.isEmpty ? Array(all.shuffled().prefix(count)) : restored
    }
}

/// A card browser (à la the RN "Today"), tied to the challenge ladder: it deals the
/// new words of the lesson's **next unpassed challenge**, so studying here is direct
/// preparation for the test you're about to take — pass it and Today advances with
/// you. Once a lesson's ladder is fully cleared it falls back to a random daily 7 as
/// review. The same words feed the home-screen widget. Lesson picked from the
/// top-right menu; locked lessons open the paywall.
struct TodayView: View {
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.defaultLanguage
    @AppStorage(Pref.todaySelection) private var selectionJSON = ""   // {lesson, romaji:[...]}
    @AppStorage(Pref.kanjiShown)       private var showKanji = true
    @AppStorage(Pref.kanaShown)        private var showKana = true
    @AppStorage(Pref.romajiShown)      private var showRomaji = true
    @AppStorage(Pref.translationShown) private var showTranslation = true
    @AppStorage(Pref.soundOn)          private var soundOn = true
    @Environment(\.pronouncer) private var pronouncer
    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var context

    @State private var picks: [Vocab] = []
    @State private var index = 0
    /// Where the learner is, derived from progress rather than picked — see `studyLesson`.
    @State private var lessonNumber = 1
    /// The rung these cards prepare for — nil once the lesson's ladder is cleared.
    @State private var upNext: Int?
    /// Furthest card reached in this deck, so `today_swipe` reports depth rather than
    /// raw swipe count — back-and-forth on the same two cards isn't engagement.
    @State private var deepestCard = 1
    private let dailyCount = 7

    private struct Selection: Codable { let lesson: Int; let ids: [String] }
    private var current: Vocab? { picks.indices.contains(index) ? picks[index] : picks.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                CardOptionsBar()
                // Where you are and what's next. This carries the lesson number that
                // used to live in the toolbar picker — the picker itself is gone,
                // because Today no longer studies a lesson you choose, it studies the
                // one you're actually on.
                whereYouAre
                if let word = current { cardStack(word) } else { ProgressView().frame(maxHeight: .infinity) }
            }
            .padding()
            .background(Theme.canvas)
            .navigationTitle(L.t("Today"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadPicks(); autoPlay(); Track.screen("today", ["lesson": lessonNumber]) }
            .onChange(of: language) { loadPicks() }
            // Premium changes the ceiling on how far progress may run.
            .onChange(of: store.isPremium) { loadPicks() }
        }
    }

    private var whereYouAre: some View {
        HStack(spacing: 6) {
            Image(systemName: upNext == nil ? "checkmark.seal.fill" : "flag.checkered")
            Text(L.t("Lesson %@", "\(lessonNumber)"))
            if let upNext {
                Text("·")
                Text(L.t("Challenge %@", "\(upNext)"))
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Theme.accent.opacity(0.12), in: Capsule())
    }

    /// A peek stack behind the card — the same deck look as Flashcards/Kana swipe,
    /// so paging through the day's words reads as "a stack of cards" too.
    private func cardStack(_ word: Vocab) -> some View {
        ZStack {
            CardStackPeek()
            card(word)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ word: Vocab) -> some View {
        // No stamps: here a swipe only turns the page, it doesn't decide anything.
        // Movement comes from `cardPager` below rather than a drag binding, so this
        // passes no `drag` — the modifier applies the offset itself.
        SwipeCard(showsHint: picks.count > 1) {
            VStack(spacing: 12) {
                if showKanji && word.displaysKanji {
                    Text(word.kanji).font(Theme.jp(22)).foregroundStyle(.secondary)
                }
                if showKana {
                    Text(word.kana).font(Theme.jp(46))
                        .minimumScaleFactor(0.4).multilineTextAlignment(.center)
                }
                if showRomaji {
                    Text(word.romaji).font(.title3).foregroundStyle(.secondary)
                }
                if showTranslation {
                    Text(word.translation).font(.title3).foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
        .onTapGesture { pronouncer.speak(word) }
        .cardPager(canPage: { picks.count > 1 }) { dir in
            let count = picks.count
            index = dir > 0 ? (index + 1) % count : (index - 1 + count) % count
            autoPlay()   // explicit: every completed page-turn speaks the new word
            // Today is the landing tab, so "did anyone go past the first card" is the
            // question that decides whether it earns the slot. `depth` is how far into
            // the deck this swipe reached — a distribution stuck at 1 means the cards
            // are wallpaper; one that runs to the end means it's the study surface.
            deepestCard = max(deepestCard, index + 1)
            Track.event("today_swipe", ["lesson": lessonNumber,
                                        "depth": deepestCard,
                                        "deck": picks.count,
                                        "for_challenge": upNext ?? 0])
        }
    }

    /// Deal the study deck: the new words of the lesson's first unpassed challenge.
    /// Deterministic (that rung's words, lesson order), so it needs no persistence and
    /// advances by itself the moment the challenge is passed. Only a fully-cleared
    /// ladder falls back to the random daily 7, kept stable via `todaySelection`.
    private func loadPicks(reshuffle: Bool = false) {
        lessonNumber = studyLesson()
        let all = VocabStore.lesson(lessonNumber, language).entries
        let results = ChallengeResult.byIndex(lesson: lessonNumber, context: context)
        let next = ChallengeResult.firstUnpassed(total: Challenge.count(wordCount: all.count),
                                                 results: results)
        if let next {
            let words = Challenge.newWords(all, index: next)
            // Reset the page only when the deck actually changed (a rung was passed,
            // or the lesson switched) — not on every tab visit mid-study.
            if upNext != next || picks.map(\.id) != words.map(\.id) { index = 0; deepestCard = 1 }
            upNext = next
            picks = words
        } else {
            upNext = nil
            var savedIDs: [String] = []
            if !reshuffle,
               let data = selectionJSON.data(using: .utf8),
               let sel = try? JSONDecoder().decode(Selection.self, from: data),
               sel.lesson == lessonNumber {
                savedIDs = sel.ids
            }
            picks = DailyPicker.pick(from: all, count: dailyCount, savedIDs: savedIDs)
            if let data = try? JSONEncoder().encode(Selection(lesson: lessonNumber, ids: picks.map(\.id))),
               let str = String(data: data, encoding: .utf8) {
                selectionJSON = str
            }
        }
        if index >= picks.count { index = 0 }
        publishWidget()
    }

    /// The lesson Today studies: the first one still holding an unpassed challenge —
    /// i.e. where the learner actually is.
    ///
    /// Derived, not chosen. The toolbar used to carry a 1–50 picker, but once the deck
    /// became "the next challenge's words" the picker only offered ways to point Today
    /// at something that *isn't* next. Deriving it also retires `clampIfLocked`: a free
    /// user can't land on a locked lesson because the search stops at the free ceiling.
    ///
    /// One fetch for all 50 lessons rather than one per lesson — this runs on every
    /// appear.
    private func studyLesson() -> Int {
        let ceiling = store.isPremium ? 50 : Gating.freeLessonLimit
        let rows = (try? context.fetch(FetchDescriptor<ChallengeResult>())) ?? []
        var passed: [Int: Set<Int>] = [:]
        for row in rows where row.isPassed { passed[row.lesson, default: []].insert(row.index) }

        for n in 1...ceiling {
            let total = Challenge.count(wordCount: VocabStore.lesson(n, language).entries.count)
            if (passed[n]?.count ?? 0) < total { return n }
        }
        return ceiling   // everything unlocked is finished — keep reviewing the last one
    }

    /// Publish today's 7 words to the App Group so the widget cycles them.
    private func publishWidget() {
        let words = picks.map {
            TodayShared.Word(kana: $0.kana, kanji: $0.kanji, romaji: $0.romaji, meaning: $0.translation)
        }
        TodayShared.write(.init(lesson: lessonNumber, words: words))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func autoPlay() {
        if soundOn, let word = current { pronouncer.speak(word) }
    }
}
