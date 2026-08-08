import SwiftUI
import SwiftData
import WidgetKit

/// A card browser (à la the RN "Today"), tied to the challenge ladder: it deals every
/// word the lesson's **next unpassed challenge** can ask — the rung's new words plus
/// its review window — so studying here is direct preparation for the test you're
/// about to take, review questions included. The same words feed the home-screen widget.
///
/// One rule the whole screen follows: show the next unpassed rung, walking lessons 1
/// through 50. Clearing a lesson's last rung rolls straight on to the next lesson's
/// first; clearing all fifty parks on lesson 50's final rung as review. There is no
/// separate "finished" mode, no shuffled deck and nothing to persist — the deck is a
/// function of progress, so it can always be recomputed and never drifts.
///
/// Never paywalled. The lesson is derived from progress (see `studyLesson`) and runs
/// the full 1–50 whatever the subscription says: meeting the words is free, being
/// tested on them is what premium buys.
struct TodayView: View {
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.defaultLanguage
    @AppStorage(Pref.kanjiShown)       private var showKanji = true
    @AppStorage(Pref.kanaShown)        private var showKana = true
    @AppStorage(Pref.romajiShown)      private var showRomaji = true
    @AppStorage(Pref.translationShown) private var showTranslation = true
    @AppStorage(Pref.soundOn)          private var soundOn = true
    @Environment(\.pronouncer) private var pronouncer
    @Environment(\.modelContext) private var context
    // Only for deciding where the capsule's tap goes — the deck itself is never gated.
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router

    @State private var picks: [Vocab] = []
    @State private var index = 0
    /// Where the learner is, derived from progress rather than picked — see `studyLesson`.
    @State private var lessonNumber = 1
    /// The rung these cards prepare for.
    @State private var upNext = 1
    /// False once every rung of all 50 lessons is passed — the deck is then lesson 50's
    /// last rung, kept as review, and the capsule says so rather than promising a test.
    @State private var hasNext = true
    /// Furthest card reached in this deck, so `today_swipe` reports depth rather than
    /// raw swipe count — back-and-forth on the same two cards isn't engagement.
    @State private var deepestCard = 1

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
        }
    }

    /// Where you are, and the way in. Same wording, same capsule and the same
    /// destination as the widget's call to action — the two are the same promise made
    /// on two surfaces, so they shouldn't look or behave like different features.
    private var whereYouAre: some View {
        Button(action: openChallenge) {
            HStack(spacing: 6) {
                Image(systemName: hasNext ? "flag.checkered" : "checkmark.seal.fill")
                Text(L.t("Lesson %@", "\(lessonNumber)"))
                Text("·")
                Text(L.t("Ready for Challenge %@?", "\(upNext)"))
                Image(systemName: "chevron.right").font(.caption2)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Theme.accent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// To the lesson's mode list — not into the rung itself. Starting a scored test
    /// nobody chose to start just manufactures abandons; from here the challenge is one
    /// deliberate tap away. When the lesson is behind the paywall it stops at the
    /// Lessons list instead, since the deck here is never gated and a free user can
    /// legitimately be reading words for a challenge they can't take. Same rule as the
    /// widget's link.
    private func openChallenge() {
        Track.event("today_challenge_open", ["lesson": lessonNumber, "index": upNext])
        if Gating.isLocked(lesson: lessonNumber, isPremium: store.isPremium) {
            router.openLessonList()
        } else {
            router.openLesson(VocabStore.lesson(lessonNumber, language))
        }
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
                                        "for_challenge": upNext])
        }
    }

    /// Deal the study deck: every word the next unpassed challenge can ask — its new
    /// words plus the review window, since the challenge tests both.
    ///
    /// Deterministic, so it needs no persistence and advances by itself the moment a
    /// rung is passed. When everything is cleared it holds lesson 50's last rung as
    /// review; that's the only case where the deck isn't something you're about to be
    /// tested on.
    private func loadPicks() {
        lessonNumber = studyLesson()
        let all = VocabStore.lesson(lessonNumber, language).entries
        let total = Challenge.count(wordCount: all.count)
        let next = ChallengeResult.firstUnpassed(
            total: total, results: ChallengeResult.byIndex(lesson: lessonNumber, context: context))
        let rung = next ?? total
        let words = Challenge.pool(all, index: rung)

        // Reset the page only when the deck actually changed (a rung was passed, or the
        // lesson switched) — not on every tab visit mid-study.
        if upNext != rung || picks.map(\.id) != words.map(\.id) { index = 0; deepestCard = 1 }
        upNext = rung
        hasNext = next != nil
        picks = words
        if index >= picks.count { index = 0 }
        publishWidget()
    }

    /// The lesson Today studies: the first one still holding an unpassed challenge —
    /// i.e. where the learner actually is.
    ///
    /// Derived, not chosen. The toolbar used to carry a 1–50 picker, but once the deck
    /// became "the next challenge's words" the picker only offered ways to point Today
    /// at something that *isn't* next.
    ///
    /// Deliberately *not* capped at the free lesson ceiling. Today is a reading surface,
    /// not a graded one — a free user keeps meeting new words here even where the
    /// matching challenge is locked. The paywall stays on the thing it guards (taking
    /// the test), rather than freezing the daily card on lesson 3 forever.
    ///
    /// One fetch for all 50 lessons rather than one per lesson — this runs on every
    /// appear.
    private func studyLesson() -> Int {
        let rows = (try? context.fetch(FetchDescriptor<ChallengeResult>())) ?? []
        var passed: [Int: Set<Int>] = [:]
        for row in rows where row.isPassed { passed[row.lesson, default: []].insert(row.index) }

        for n in 1...50 {
            let total = Challenge.count(wordCount: VocabStore.lesson(n, language).entries.count)
            if (passed[n]?.count ?? 0) < total { return n }
        }
        return 50   // every challenge cleared — keep reviewing the last lesson
    }

    /// Publish the deck to the App Group so the widget cycles the same words.
    private func publishWidget() {
        let words = picks.map {
            TodayShared.Word(kana: $0.kana, kanji: $0.kanji, romaji: $0.romaji, meaning: $0.translation)
        }
        let snapshot = TodayShared.Snapshot(lesson: lessonNumber, words: words,
                                            challenge: upNext)
        TodayShared.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        // The watch has its own App Group container that this write can't reach, so the
        // same deck goes over WatchConnectivity as well — see WatchLink.
        WatchLink.shared.send(snapshot)
    }

    private func autoPlay() {
        if soundOn, let word = current { pronouncer.speak(word) }
    }
}
