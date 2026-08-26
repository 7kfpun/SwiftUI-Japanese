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
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.deviceDefaultLanguage
    @AppStorage(Pref.soundOn)          private var soundOn = true
    @Environment(\.pronouncer) private var pronouncer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    // Only for deciding where the capsule's tap goes — the deck itself is never gated.
    @Environment(Store.self) private var store
    @Environment(Unlock.self) private var unlock
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
    /// Double-tap turns the card over and it *stays* over; double-tap again turns it
    /// back (kf, 2026-08-26 — the hold was fatiguing for actually reading the entry).
    /// A single tap reads: the word on the front, the whole entry on the back.
    @State private var flipped = false
    /// Reads the flipped entry aloud — the read-along four-leg sequence (word,
    /// meaning, sentence, its meaning) on a one-word list. Free users get the word
    /// leg: the spoken meaning is the same paid feature it is in Read along.
    @State private var detailPlayer = LessonPlayer()
    /// This card already logged its flip — `today_flip` counts cards peeked, not
    /// presses, matching `flashcard_flip` and `practice_peek`.
    @State private var flippedThisCard = false
    /// Recomputed on appear rather than observed: the streak can only change by answering
    /// something, which always happens on another screen, so there is nothing to watch
    /// while Today is visible.
    @State private var streak = Streak(days: [])
    /// The soft opt-in, raised once the streak has earned it — see `NotificationOptIn`.
    @State private var showNotificationOptIn = false
    /// Whether the card was answered, so its dismissal can be told from its two buttons.
    @State private var optInAnswered = false

    private var current: Vocab? { picks.indices.contains(index) ? picks[index] : picks.first }

    private func reloadStreak() {
        streak = StudyDay.streak(context: context)
        // A streak worth protecting is the moment the offer makes sense — asking on day 1
        // is asking someone to defend something they don't have yet. Checked here because
        // this is the one place the streak is read; the policy itself lives in
        // `NotificationOptIn` so the intro and this can't both fire in the same week.
        Task { [streak] in
            let status = await StreakReminder.authorizationStatus()
            let on = UserDefaults.standard.bool(forKey: Pref.streakReminderOn)
            if NotificationOptIn.shouldAskAfterStreak(streak, isOn: on, status: status) {
                await MainActor.run { showNotificationOptIn = true }
            }
        }
        // The reminder plan is a sliding week, and it depends on whether today is already
        // done — both of which go stale on their own. Re-planning wherever the streak is
        // read keeps the two in step without a timer or a background task.
        Task { [studiedToday = streak.studiedToday] in
            await StreakReminder.reschedule(studiedToday: studiedToday)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                // Where you are and what's next, as the redesign's warm-up banner —
                // it carries the lesson-and-rung fact the old capsule held, plus the
                // one sentence that makes the deck make sense: these exact words are
                // what the test will ask. The field toggles moved to the toolbar's
                // Show menu, so the banner is the first thing under the title.
                warmupBanner
                if picks.count > 1 { deckSegments }
                if let word = current { cardStack(word) } else { ProgressView().frame(maxHeight: .infinity) }
                // The gesture is invisible until tried — same one-line teacher as
                // Flashcards, in the slot the cards-left footer used to hold.
                Text(L.t("Double-tap for details"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Theme.canvas)
            .navigationTitle(L.t("Today"))
            .navigationBarTitleDisplayMode(.inline)
            // The streak belongs on the surface it measures. Today *is* the daily-habit
            // screen, so the number sits in its bar rather than claiming a fifth tab for
            // one integer — and a toolbar item costs no vertical space on a screen that
            // already gives some to a banner.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { showMenu }
                ToolbarItem(placement: .topBarLeading) {
                    StreakBadge(streak: streak) {
                        // The screen event can't split the badge from the tab bar, and
                        // this is the affordance the badge exists to be.
                        Track.event("streak_open", ["streak": streak.current,
                                                    "studied_today": streak.studiedToday])
                        router.tab = .progress
                    }
                }
            }
            .onAppear {
                loadPicks(); autoPlay(); reloadStreak()
                unlock.refresh(context: context)
                Track.screen("today", ["lesson": lessonNumber])
            }
            // A sheet rather than an alert: this is an offer with a rationale, and an
            // alert's two bare buttons can't carry the reason it's worth a yes.
            // A swipe down is a third exit and, unlike the two buttons, it records no ask —
            // so the card comes back on the next appear. Kept as its own name rather than
            // folded into `notification_opt_in` with `accepted: false`: a decline is one
            // person deciding once, while this can fire repeatedly at the same person, and
            // averaging the two together would quietly wreck the accept rate.
            .sheet(isPresented: $showNotificationOptIn, onDismiss: {
                guard !optInAnswered else { optInAnswered = false; return }
                Track.event("notification_opt_in_dismissed",
                            ["source": "streak", "streak": streak.current])
            }) {
                NotificationOptInCard { wantsReminders in
                    optInAnswered = true
                    NotificationOptIn.recordAsked()
                    Track.event("notification_opt_in",
                                ["source": "streak", "accepted": wantsReminders,
                                 "streak": streak.current])
                    showNotificationOptIn = false
                    guard wantsReminders else { return }
                    Task {
                        guard await StreakReminder.requestAuthorization() else { return }
                        UserDefaults.standard.set(true, forKey: Pref.streakReminderOn)
                        await StreakReminder.reschedule(studiedToday: streak.studiedToday)
                        await PushService.shared.registerIfAuthorized()
                    }
                }
                .scrollableWhenCramped()
                .presentationDetents([.medium, .large])
            }
            .onChange(of: language) { loadPicks() }
            .onDisappear { detailPlayer.stop() }
        }
    }

    /// Where you are, and the way in — the same destination as the widget's call to
    /// action, drawn as the redesign's warm-up banner. `hasNext` decides the words,
    /// not just the icon: a learner who has passed everything is reviewing, not
    /// preparing, and the banner must not promise a rung `firstUnpassed` said is gone.
    private var warmupBanner: some View {
        Button(action: openChallenge) {
            HStack(spacing: 11) {
                Image(systemName: hasNext ? "flag" : "checkmark.seal.fill")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasNext ? L.t("Warming up for Challenge %@", "\(upNext)")
                                 : L.t("All challenges passed"))
                        .font(Theme.title(.subheadline))
                        .foregroundStyle(.primary)
                    Text(hasNext ? L.t("These %@ words are exactly what it will ask.",
                                       "\(picks.count)")
                                 : L.t("Reviewing the last words of Lesson %@.",
                                       "\(lessonNumber)"))
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.5)))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    /// One slim segment per card: filled for seen, mid for the current, faint for what
    /// is still to come — the deck's length made visible without a number.
    private var deckSegments: some View {
        HStack(spacing: 5) {
            ForEach(picks.indices, id: \.self) { i in
                Capsule()
                    .fill(i < index ? Color.primary
                          : i == index ? Color.secondary
                          : Theme.line)
                    .frame(height: 4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Word %@ of %@", "\(index + 1)", "\(picks.count)"))
    }

    /// The shared Show menu — same component Flashcards mounts, see `CardShowMenu`.
    private var showMenu: some View { CardShowMenu() }

    /// To the lesson's mode list — not into the rung itself — or to the Lessons list when
    /// the lesson is behind the paywall, since the deck here is never gated and a free
    /// user can legitimately be reading words for a challenge they can't take. Both rules
    /// are `Router`'s (`openLesson` / `openLessonList`), and the widget's link shares them.
    private func openChallenge() {
        let locked = Gating.isLocked(lesson: lessonNumber, isPremium: store.isPremium,
                                     earnedFirstGroup: unlock.earnedFirstGroup)
        // `locked` on the event: a locked lesson lands on the Lessons list, not the
        // rung the event names, and without the param the two were one number.
        Track.event("today_challenge_open", ["lesson": lessonNumber, "index": upNext,
                                             "locked": locked])
        if locked {
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
        // The hint hides while flipped — it belongs to `SwipeCard`, which is what the
        // 3D turn rotates, so on the back it would render mirror-written.
        SwipeCard(showsHint: picks.count > 1 && !flipped) {
            ZStack {
                back(word).opacity(flipped ? 1 : 0)
                front(word).opacity(flipped ? 0 : 1)
            }
        }
        .rotation3DEffect(.degrees(flipped && !reduceMotion ? 180 : 0),
                          axis: (x: 0, y: 1, z: 0))
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.45),
                   value: flipped)
        // Double-tap first: attached before the single tap, so the tap waits for the
        // double to fail rather than firing twice on every flip.
        .onTapGesture(count: 2) { toggleFlip(word) }
        .onTapGesture {
            if flipped { readDetails(word) } else { pronouncer.speak(word) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: flipped)
        .cardPager(canPage: { picks.count > 1 }) { dir in
            let count = picks.count
            index = dir > 0 ? (index + 1) % count : (index - 1 + count) % count
            detailPlayer.stop()
            flipped = false
            flippedThisCard = false
            autoPlay()   // explicit: every completed page-turn speaks the new word
            // Today is the landing tab, so "did anyone go past the first card" is the
            // question that decides whether it earns the slot. `depth` is how far into
            // the deck this turn reached — a distribution stuck at 1 means the cards
            // are wallpaper; one that runs to the end means it's the study surface.
            deepestCard = max(deepestCard, index + 1)
            Track.event("today_swipe", ["lesson": lessonNumber,
                                        "depth": deepestCard,
                                        "deck": picks.count,
                                        "for_challenge": upNext])
        }
    }

    private func toggleFlip(_ word: Vocab) {
        withAnimation { flipped.toggle() }
        if flipped {
            if !flippedThisCard {
                flippedThisCard = true
                Track.event("today_flip", ["lesson": lessonNumber])
            }
            readDetails(word)
        } else {
            detailPlayer.stop()
        }
    }

    /// The full entry, spoken. `.japanese` without premium: hearing the meaning read
    /// aloud is exactly what Read along sells, and this must not be its free door.
    private func readDetails(_ word: Vocab) {
        guard soundOn else { return }
        pronouncer.stop()
        detailPlayer.stop()
        detailPlayer.toggle([word],
                            mode: store.isPremium ? .withExample : .japanese,
                            language: language, loops: false)
    }

    /// Mirrored, so it reads the right way round once the card has turned. Full
    /// details regardless of the Show menu — the flip is the way to see everything,
    /// and the example sentence lives only here.
    private func back(_ word: Vocab) -> some View {
        VocabFace(vocab: word,
                  speakExample: {
                      pronouncer.speak(example: word)
                      Track.event("play_example", ["lesson": word.lesson,
                                                   "surface": "today"])
                  })
            .padding(18)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
    }

    private func front(_ word: Vocab) -> some View {
            VStack(spacing: 0) {
                HStack {
                    // The chip states the deck's contract — these words are the test.
                    Text(hasNext ? L.t("Asked in Challenge %@", "\(upNext)")
                                 : L.t("Review these"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                    Spacer()
                    // Its own button: the card's tap also speaks, but a visible control
                    // is what tells anyone the card *can* talk.
                    Button { pronouncer.speak(word) } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.body)
                            .foregroundStyle(Color(.systemBackground))
                            .frame(width: 44, height: 44)
                            .background(Color.primary, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Tap to hear it"))
                }

                Spacer(minLength: 10)

                // The shared toggle-driven face — one front for both browse decks.
                VocabFront(vocab: word)

                Spacer(minLength: 10)
            }
            .padding(18)
    }

    /// Deal the study deck: every word the next unpassed challenge can ask — its new
    /// words plus the review window, since the challenge tests both.
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

        for n in 1...Course.current.lessonCount {
            // `wordCount`, never `lesson(n).entries.count`: the lesson subscript traps
            // when `Course.lessonCount` outruns the data file, and its own doc admits
            // the two can drift. `wordCount` returns 0 there — `Challenge.count(0)` is
            // 0, no rung is owed, and the loop walks on instead of crashing the first
            // Today appear of a build shipped with a short dataset. It also skips
            // building a whole language's Vocab array per lesson on every appear.
            let total = Challenge.count(wordCount: VocabStore.wordCount(n))
            if (passed[n]?.count ?? 0) < total { return n }
        }
        // Every challenge cleared — keep reviewing the last lesson. The course's own
        // count, never a literal: 50 was right for Minna only by coincidence, and in
        // the JLPT app it parked a finished learner's deck and widget on lesson 50 of 201.
        return Course.current.lessonCount
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
