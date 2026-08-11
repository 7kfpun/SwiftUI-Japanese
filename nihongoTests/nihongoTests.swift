import Testing
import Foundation
import SwiftData
import AVFoundation
import UIKit
@testable import nihongo

// MARK: - Bundled data integrity (canaries for scripts/build-minna-data.py)

struct DataTests {
    @Test func generatedDataShape() {
        // Entry/audio totals are regeneration canaries — update together with `make data`.
        #expect(VocabStore.allVocab().count == 2089)
        #expect(VocabStore.allVocab().filter { $0.audio != nil }.count == 2089)
        #expect(VocabStore.lessons().map(\.number) == Array(1...50))
    }

    /// The lesson list renders exactly one group's range at a time, so the groups have
    /// to tile `1...lessonCount` with no gap and no overlap — a gap makes lessons
    /// unreachable and an overlap lists them twice, and neither shows up anywhere but
    /// on the screen itself. Course-agnostic on purpose: this guards JLPT's five levels
    /// as much as Minna's four bands.
    @Test func lessonGroupsTileEveryLesson() {
        let groups = Course.current.groups
        #expect(groups.first?.first == 1)
        #expect(groups.last?.last == Course.current.lessonCount)
        for (a, b) in zip(groups, groups.dropFirst()) {
            #expect(b.first == a.last + 1, "gap or overlap between \(a.name) and \(b.name)")
        }
    }

    @Test func streakCountsBackFromTodayAndSurvivesAnOpenDay() {
        let today = 20260811
        func back(_ n: Int) -> Int { StudyDay.stamp(today, offsetBy: -n) }

        // Nothing recorded at all.
        #expect(Streak(days: [], today: today).current == 0)

        // Three days ending today.
        let done = Streak(days: [back(0), back(1), back(2)], today: today)
        #expect(done.current == 3)
        #expect(done.studiedToday)

        // Same three days, but today hasn't been studied yet: the streak is still alive
        // — it breaks on a *missed* day, not on an unfinished one — and says so.
        let open = Streak(days: [back(1), back(2), back(3)], today: today)
        #expect(open.current == 3)
        #expect(!open.studiedToday)

        // A gap two days ago ends it.
        #expect(Streak(days: [back(0), back(2), back(3)], today: today).current == 1)

        // `best` remembers a longer past run than the current one.
        let past = Streak(days: [back(0), back(10), back(11), back(12), back(13)], today: today)
        #expect(past.current == 1)
        #expect(past.best == 4)
    }

    /// The pressure states. Everything the UI nags with keys off `atRisk`, so it must be
    /// false in every state where the user has nothing left to do — including the one
    /// where they have no streak at all, or a streak of zero would be chased for nothing.
    @Test func streakAppliesPressureOnlyWhenSomethingIsActuallyAtRisk() {
        let today = 20260811
        func back(_ n: Int) -> Int { StudyDay.stamp(today, offsetBy: -n) }

        #expect(!Streak(days: [], today: today).atRisk)                    // nothing to lose
        #expect(!Streak(days: [back(0), back(1)], today: today).atRisk)    // today already done
        #expect(Streak(days: [back(1), back(2)], today: today).atRisk)     // alive, today open

        // Nothing to chase once the current run *is* the record — the app must not invent
        // a target when the honest answer is "you're at your best".
        #expect(Streak(days: [back(0), back(1), back(2)], today: today).toBeatBest == nil)

        // Behind the record: one more than the gap, because matching it isn't beating it.
        let behind = Streak(days: [back(0), back(10), back(11), back(12)], today: today)
        #expect(behind.current == 1)
        #expect(behind.best == 3)
        #expect(behind.toBeatBest == 3)

        // The week strip is always seven days, oldest first, ending today.
        let week = Streak(days: [back(0), back(3)], today: today).lastWeek()
        #expect(week.count == 7)
        #expect(week.last?.day == today)
        #expect(week.map(\.studied) == [false, false, false, true, false, false, true])
    }

    /// The countdown must be silent unless something is genuinely at stake, and it must
    /// run to real local midnight — the same boundary `StudyDay.record` stamps against,
    /// or the clock would hit zero at a moment the streak doesn't actually end.
    @Test func countdownRunsToMidnightAndOnlyWhenAtRisk() throws {
        let calendar = StudyDay.calendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11,
                                                                  hour: 21, minute: 30)))
        let today = StudyDay.stamp(now)
        func back(_ n: Int) -> Int { StudyDay.stamp(today, offsetBy: -n) }

        #expect(Streak(days: [], today: today).timeLeft(now: now) == nil)
        #expect(Streak(days: [back(0)], today: today).timeLeft(now: now) == nil)

        let left = try #require(Streak(days: [back(1)], today: today).timeLeft(now: now))
        #expect(left == 2.5 * 3600)   // 21:30 → midnight
    }

    /// A meaning must be spoken by a voice for *its* language. The mapped codes are the
    /// ones that would otherwise resolve to no voice at all and fall back to silence or
    /// to the wrong accent.
    /// The recommend nudge must never land on the same rung as the star row, and must
    /// never fire on a failed one. Both prompts trigger on "challenge finished", so the
    /// precedence is the only thing stopping two sheets stacking on one screen.
    @Test func sharePromptStandsDownForTheRatingAndForFailures() {
        let enough = SharePrompt.challengesRequired

        #expect(SharePrompt.shouldAsk(passed: true, passedCount: enough, ratingShown: false))
        // The star row took this occasion.
        #expect(!SharePrompt.shouldAsk(passed: true, passedCount: enough, ratingShown: true))
        // Asking someone to recommend the app straight after they failed asks a different
        // question than the one intended.
        #expect(!SharePrompt.shouldAsk(passed: false, passedCount: enough, ratingShown: false))
        // Zero passed rungs is still too few, even at a threshold of one — the nudge is
        // tied to something having visibly worked, not to opening the app.
        #expect(!SharePrompt.shouldAsk(passed: true, passedCount: 0, ratingShown: false))

        // Far lower bar than the rating: this asks for a recommendation, not a public
        // verdict, so it fires on the first rung anyone clears.
        #expect(SharePrompt.challengesRequired == 1)
        #expect(SharePrompt.challengesRequired < RatingPrompt.challengesRequired)
        // Monthly here, quarterly there — and separate keys, or each would silence the
        // other the moment one of them stamped.
        #expect(SharePrompt.askAgainAfter < RatingPrompt.askAgainAfter)
        #expect(Pref.shareAskedAt != Pref.ratingAskedAt)
    }

    /// The share text must carry *this* app's listing. Two apps, two listings, and a
    /// recommendation pointing at the other one would look like it worked.
    @Test func shareLinkPointsAtThisCoursesListing() {
        #expect(SharePrompt.appStoreURL.absoluteString == Course.current.appStoreURL)
        #expect(SharePrompt.shareText().contains(Course.current.appStoreURL))
        #expect(Course.minna.appStoreURL != Course.jlpt.appStoreURL)
    }

    @Test func meaningLocalesAreSpeakableTags() {
        #expect(Speech.meaningLocale("zh") == "zh-CN")        // `zh` is Simplified here
        #expect(Speech.meaningLocale("zh-Hant") == "zh-TW")
        #expect(Speech.meaningLocale("fil") == "fil-PH")      // no voice under bare `fil`
        #expect(Speech.meaningLocale("vi") == "vi")           // already a valid tag

        // Every meaning language the course ships must map to something non-empty.
        for language in VocabStore.availableLanguages {
            #expect(!Speech.meaningLocale(language).isEmpty, "no locale for \(language)")
        }
    }

    /// Month and year ends are exactly where a streak computed by integer arithmetic
    /// breaks: 20260301 minus one is not 20260228 in a leap year, and 20260101 minus one
    /// is not 20260100. Both must walk through `Calendar`.
    @Test func streakStampsCrossMonthAndYearBoundaries() {
        #expect(StudyDay.stamp(20260301, offsetBy: -1) == 20260228)   // 2026 is not a leap year
        #expect(StudyDay.stamp(20240301, offsetBy: -1) == 20240229)   // 2024 is
        #expect(StudyDay.stamp(20260101, offsetBy: -1) == 20251231)
        #expect(StudyDay.stamp(20251231, offsetBy: 1) == 20260101)

        // A run spanning a year end is one run, not two.
        let days: Set<Int> = [20251230, 20251231, 20260101, 20260102]
        #expect(Streak(days: days, today: 20260102).current == 4)
    }

    @Test func idsAreGloballyUnique() {
        // Romaji repeats across lessons, so Vocab.id must include the lesson number.
        let ids = VocabStore.allVocab().map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// Every screen's minimum data needs, checked for all 50 lessons: a floor on lesson
    /// size, so nothing deals a near-empty deck (Today deals a rung's pool, which is
    /// larger), and 4 distinct kana so a multiple-choice question has four options.
    @Test func everyLessonSupportsGameplay() {
        for lesson in VocabStore.lessons() {
            #expect(lesson.entries.count >= 7, "lesson \(lesson.number) too small for Today")
            #expect(Set(lesson.entries.map(\.kana)).count >= 4,
                    "lesson \(lesson.number) lacks 4 distinct kana for the quiz")
        }
    }

    @Test func vocabClipIsNamedAndDecodes() throws {
        let watashi = try #require(VocabStore.lesson(1).entries.first { $0.romaji == "watashi" })
        #expect(watashi.audio == "1-watashi")                    // flat naming scheme
        let url = try #require(VocabStore.audioURL(for: watashi))
        let player = try AVAudioPlayer(contentsOf: url)          // throws if not decodable
        #expect(player.duration > 0)
    }

    /// Every kana shown anywhere in the UI has a bundled pronunciation clip.
    @Test func everyKanaHasABundledClip() throws {
        let cells = (KanaData.seion + KanaData.dakuon + KanaData.youon)
            .flatMap { $0 }.filter { !$0.isEmpty }
        for cell in cells {
            #expect(VocabStore.kanaAudioURL(cell.romaji) != nil, "missing clip for \(cell.romaji)")
        }
        #expect(VocabStore.kanaAudioURL("") == nil)
        // spot-check one decodes
        let url = try #require(VocabStore.kanaAudioURL("ka"))
        #expect(try AVAudioPlayer(contentsOf: url).duration > 0)
    }

    @Test func translationsSwitchWithLanguage() {
        let en = VocabStore.lesson(1, "en").entries.first { $0.romaji == "watashi" }?.translation
        let zh = VocabStore.lesson(1, "zh").entries.first { $0.romaji == "watashi" }?.translation
        #expect(en == "I")
        #expect(zh != nil && !zh!.isEmpty && zh != en)
        // every bundled language resolves fully for a lesson.
        for lang in VocabStore.availableLanguages {
            #expect(VocabStore.lesson(1, lang).entries.allSatisfy { !$0.translation.isEmpty })
        }
    }
}

// MARK: - Text cleaning

struct TextTests {
    @Test func cleanWordStripsAnnotations() {
        #expect(cleanWord("のります［でんしゃに～］") == "のります")
        #expect(cleanWord("大変「な」") == "大変")
        #expect(cleanWord("お問い合わせの番号。") == "お問い合わせの番号")
        #expect(cleanWord("～さん") == "さん")
        #expect(cleanWord("") == "")
    }
}

// MARK: - Kana data (bundled from minna/vocab/kana.json)

struct KanaTests {
    private func nonEmpty(_ t: [[K]]) -> Int { t.flatMap { $0 }.filter { !$0.isEmpty }.count }

    @Test func tableAndPoolCounts() {
        #expect(nonEmpty(KanaData.seion) == 46)
        #expect(nonEmpty(KanaData.dakuon) == 25)
        #expect(nonEmpty(KanaData.youon) == 33)
        #expect(KanaData.hiraganaPool.count == 74)
        #expect(KanaData.katakanaPool.count == 74)
    }

    @Test func strokeOrderFontIsBundled() {
        #expect(UIFont(name: "KanjiStrokeOrders", size: 20) != nil)
    }
}

// MARK: - Search

struct SearchTests {
    @Test func findsByRomajiAndTranslation() {
        #expect(searchVocab("watashi").contains { $0.romaji == "watashi" })
        #expect(!searchVocab("teacher").isEmpty)
        #expect(searchVocab("   ").isEmpty)
    }
}

// MARK: - Learn mode (tile reconstruction)

struct LearnTests {
    @Test func tileGenerationNeverCrashesAndKeepsAnswerBuildable() {
        for lesson in VocabStore.lessons() {
            let model = LearnModel(vocab: lesson.entries)
            for i in lesson.entries.indices {
                model.index = i
                model.loadTiles()
                let target = cleanWord(lesson.entries[i].kana)
                if !target.isEmpty && target.count <= 15 {
                    let tiles = model.tiles.map(\.text)
                    for ch in target.map(String.init) {
                        #expect(tiles.contains(ch))
                    }
                }
            }
        }
    }

    @Test func sentenceLengthEntryBails() {
        let l14 = VocabStore.lesson(14)
        guard let idx = l14.entries.firstIndex(where: { cleanWord($0.kana).count > 15 }) else {
            Issue.record("expected a sentence-length entry in lesson 14"); return
        }
        let model = LearnModel(vocab: l14.entries)
        model.index = idx
        model.loadTiles()
        #expect(model.tiles.isEmpty)
        #expect(model.isPlayable == false)
    }

    @Test func detectsCorrectAndWrong() {
        let v = Vocab(lesson: 1, kanji: "わたし", kana: "わたし", romaji: "watashi",
                      dictionary: nil, useKana: false, translation: "I", audio: nil, key: nil)

        let ok = LearnModel(vocab: [v])
        for ch in "わたし".map(String.init) { ok.tap(Tile(id: 0, text: ch)) }
        #expect(ok.state == .correct)

        let bad = LearnModel(vocab: [v])
        bad.tap(Tile(id: 0, text: "か"))
        #expect(bad.state == .wrong)
    }
}

// MARK: - Flashcard deck (Tinder-style spaced repetition)

struct FlashcardTests {
    private var sample: [Vocab] { VocabStore.lesson(3).entries }

    @Test func knowRetiresAndDontKnowRecycles() {
        let deck = FlashDeck(sample)
        let start = deck.remaining
        let first = deck.current
        deck.dontKnow()
        #expect(deck.remaining == start)          // still in the deck, sent to the back
        #expect(deck.current?.id != first?.id)
        deck.know()
        #expect(deck.remaining == start - 1)
        #expect(deck.mastered == 1)
    }

    @Test func unknownCardsResurfaceUntilKnown() {
        // "Don't know" every card once, then master the deck — it must still drain.
        let deck = FlashDeck(sample)
        for _ in 0..<deck.total { deck.dontKnow() }
        while !deck.isDone { deck.know() }
        #expect(deck.mastered == deck.total)
        #expect(deck.current == nil)
    }

    @Test func restartRefillsAndResets() {
        let deck = FlashDeck(sample)
        while !deck.isDone { deck.know() }
        deck.restart()
        #expect(deck.remaining == deck.total)
        #expect(deck.mastered == 0)
        #expect(deck.current != nil)
    }

    @Test func genericDeckAlsoDrivesKana() {
        // The same FlashDeck powers the Kana flashcards (generic over element type).
        let kana = KanaData.seion.flatMap { $0 }.filter { !$0.isEmpty }
        let deck = FlashDeck(kana)
        #expect(deck.total == kana.count)
        while !deck.isDone { deck.know() }
        #expect(deck.mastered == deck.total)
    }
}

// MARK: - Train / kana quiz models

struct TrainTests {
    /// Two chips, one swipe: the answer is present and the distractor differs on BOTH
    /// faces — a shared display text is unanswerable, a shared prompt text (homophones,
    /// なん/なに-style glosses) is a second right answer that would be marked wrong.
    @Test func dealsTwoOptionsDistinctOnBothFaces() {
        let model = TrainModel(vocab: VocabStore.lesson(5).entries)
        for _ in 0..<50 {
            model.next()
            #expect(model.options.count == 2)
            #expect(model.options.contains { $0.id == model.answer.id })
            let shown = model.options.map { model.to.value($0) }
            #expect(Set(shown).count == shown.count)
            let prompts = model.options.map { model.from.value($0) }
            #expect(Set(prompts).count == prompts.count)
        }
    }

    /// Cycling a form re-deals the distractor — it was picked to be distinct under the
    /// old pair, and with two chips a collision under the new one is fatal.
    @Test func formCyclingSkipsOtherSideAndKeepsOptionsDistinct() {
        let model = TrainModel(vocab: VocabStore.lesson(1).entries)
        for _ in 0..<8 {
            model.cycleFrom()
            #expect(model.from != model.to)
            model.cycleTo()
            #expect(model.from != model.to)
            let shown = model.options.map { model.to.value($0) }
            #expect(Set(shown).count == shown.count)
        }
    }

    /// Starting ordered means starting at word 1. The preference has to reach the
    /// model's initialiser, because `init` draws the first word immediately — applying
    /// it afterwards anchored the walk to whatever random word had already been picked,
    /// so a "front to back" sweep began in the middle of the lesson.
    @Test func orderedModeStartsAtTheFirstWord() {
        let vocab = VocabStore.lesson(1).entries
        for _ in 0..<20 {                       // would pass ~1-in-35 of the time by luck
            let model = TrainModel(vocab: vocab, ordered: true)
            #expect(model.answer.id == vocab[0].id)
        }
        // Random stays random — it must not silently become an ordered walk.
        let seen = Set((0..<30).map { _ in TrainModel(vocab: vocab).answer.id })
        #expect(seen.count > 1)
    }

    /// Ordered mode walks the lesson front to back, wrapping — and switching it on
    /// mid-run resumes from the word on screen rather than snapping to word 1.
    @Test func orderedModeWalksTheLessonAndResumesInPlace() {
        let vocab = VocabStore.lesson(1).entries
        let model = TrainModel(vocab: vocab)
        model.ordered = true
        let start = vocab.firstIndex { $0.id == model.answer.id } ?? -1
        for step in 1...vocab.count {                       // one full wrapping lap
            model.next()
            #expect(model.answer.id == vocab[(start + step) % vocab.count].id)
            #expect(model.options.contains { $0.id == model.answer.id })
        }
    }

    @Test func listeningVariantUsesAudioPromptAndWordOptions() {
        // Listening is Train with an audio prompt; the options are the written word.
        let model = TrainModel(vocab: VocabStore.lesson(3).entries, from: .audio)
        #expect(model.from == .audio)
        #expect(model.to == .kana)
        // Cycling the answer side must never land on audio (audio can't be an option).
        for _ in 0..<10 { model.cycleTo(); #expect(model.to != .audio) }
    }

    @Test func promptCanCycleToAudioButBackAgain() {
        let model = TrainModel(vocab: VocabStore.lesson(1).entries)
        var sawAudio = false
        for _ in 0..<VForm.allCases.count { model.cycleFrom(); if model.from == .audio { sawAudio = true } }
        #expect(sawAudio)                 // audio is reachable as a prompt
        #expect(model.from != model.to)   // and never collides with the answer side
    }

    @Test func emptyVocabDegradesInsteadOfCrashing() {
        let model = TrainModel(vocab: [])
        #expect(model.options.count <= 1)    // just the placeholder answer, no crash
        #expect(model.answer.kana.isEmpty)
    }

    @Test func kanaQuizOptionsAreDistinctAndContainAnswer() {
        let pool = KanaData.seion.flatMap { $0 }
        for count in [2, 4] {
            let model = KanaQuizModel(pool: pool, optionCount: count)
            for _ in 0..<30 {
                model.next()
                #expect(model.options.count == count)
                #expect(model.options.contains { $0.romaji == model.answer.romaji })
                let romaji = model.options.map(\.romaji)
                #expect(Set(romaji).count == romaji.count)
            }
        }
    }

    /// Auto-playing the answer's pronunciation must never reveal it: allowed when the
    /// prompt is the word itself (any written form, or the audio question), forbidden
    /// when the prompt is the meaning and the options are the word.
    @Test func promptAudioNeverRevealsAnswer() {
        #expect(TrainModel.promptAudioSafe(from: .kana))
        #expect(TrainModel.promptAudioSafe(from: .kanji))
        #expect(TrainModel.promptAudioSafe(from: .romaji))
        #expect(TrainModel.promptAudioSafe(from: .audio))
        #expect(!TrainModel.promptAudioSafe(from: .translation))
    }
}

// MARK: - Premium products & gating

struct PremiumTests {
    @Test func lineupInvariants() {
        // The paywall must never sell a legacy product, and everything sold must count
        // toward entitlement (otherwise a purchase wouldn't unlock anything).
        #expect(Set(PremiumProduct.purchasable).isDisjoint(with: PremiumProduct.legacy))
        #expect(Set(PremiumProduct.all).isSuperset(of: PremiumProduct.purchasable))
        #expect(Set(PremiumProduct.all).isSuperset(of: PremiumProduct.legacy))   // restores
        #expect(PremiumProduct.purchasable.contains(PremiumProduct.lifetime))
        #expect(PremiumProduct.all.allSatisfy { $0.hasPrefix("com.kfpun.nihongo.premium") })
    }

    @Test func gatingRules() {
        // Lessons 1…7 free in full, 8…50 premium — one rule, no partial trial.
        let free = Gating.freeLessonLimit
        #expect(free == 7)
        for n in 1...50 {
            #expect(Gating.isLocked(lesson: n, isPremium: false) == (n > free))
            #expect(!Gating.isLocked(lesson: n, isPremium: true))
        }
        // The boundary specifically: the last free lesson is, the next one isn't.
        #expect(!Gating.isLocked(lesson: free, isPremium: false))
        #expect(Gating.isLocked(lesson: free + 1, isPremium: false))
    }

    /// The rating ask is open to everyone, not just subscribers. Pinned because it was
    /// subscribers-only and the argument is still accepted — a silent revert would look
    /// like nothing had changed while almost nobody got asked.
    @Test func ratingAsksFreeUsersToo() {
        let enough = RatingPrompt.challengesRequired
        #expect(RatingPrompt.shouldAsk(isPremium: false, passed: true, passedCount: enough))
        #expect(RatingPrompt.shouldAsk(isPremium: true, passed: true, passedCount: enough))
        // The two conditions that do still gate it.
        #expect(!RatingPrompt.shouldAsk(isPremium: true, passed: false, passedCount: enough))
        #expect(!RatingPrompt.shouldAsk(isPremium: true, passed: true, passedCount: enough - 1))
    }
}

// MARK: - Ads configuration

struct AdConfigTests {
    /// The test target builds Debug, where ads must always be Google's test units —
    /// loading real units in development violates AdMob policy.
    @Test func debugBuildsUseTestUnitsOnly() {
        #expect(AdConfig.banner(.kana) == AdConfig.testBanner)
        #expect(AdConfig.banner(.today) == AdConfig.testBanner)
        #expect(AdConfig.interstitial == AdConfig.testInterstitial)
    }
}

// MARK: - Kana sketch matcher (Write mode)

struct KanaSketchTests {
    @Test func templateMatchesItselfPerfectly() throws {
        let a = try #require(KanaSketch.glyphGrid("あ"))
        #expect(KanaSketch.distance(a, a) == 0)
    }

    @Test func distinctKanaAreSeparated() throws {
        // Templates must be non-degenerate: identical to themselves, measurably far
        // from every other seion glyph (guards an all-empty/collapsed pipeline).
        let cells = KanaData.seion.flatMap { $0 }.filter { !$0.isEmpty }
        let grids = try cells.map { (cell: $0, grid: try #require(KanaSketch.glyphGrid($0.hiragana))) }
        for (i, me) in grids.enumerated() {
            #expect(KanaSketch.distance(me.grid, me.grid) == 0)
            for other in grids[(i + 1)...] {
                let d = KanaSketch.distance(me.grid, other.grid)
                #expect(d > 0.3, "\(me.cell.hiragana) vs \(other.cell.hiragana) too close (\(d))")
            }
        }
    }

    @Test func emptyStrokesProduceNoGrid() {
        #expect(KanaSketch.strokeGrid([]) == nil)
        #expect(KanaSketch.strokeGrid([[CGPoint(x: 1, y: 1)]]) == nil)
    }

    @Test func tinyComponentsAreStrippedButRealMarksSurvive() {
        // Stroke-order-number-sized blob (≤6×6) is erased; a dakuten-sized one isn't.
        let size = 32
        var g = [Bool](repeating: false, count: size * size)
        func blob(x0: Int, y0: Int, w: Int, h: Int) {
            for y in y0..<(y0 + h) { for x in x0..<(x0 + w) { g[y * size + x] = true } }
        }
        blob(x0: 2, y0: 2, w: 4, h: 5)     // "digit": should vanish
        blob(x0: 12, y0: 12, w: 12, h: 3)  // real stroke: wide, must stay
        blob(x0: 12, y0: 20, w: 8, h: 6)   // dakuten-sized mark: must stay
        KanaSketch.stripTinyComponents(&g, size: size)
        let lit = (0..<g.count).filter { g[$0] }
        #expect(lit.count == 12 * 3 + 8 * 6)
        #expect(!g[3 * size + 3])   // the digit blob is gone
        #expect(g[13 * size + 13] && g[22 * size + 14])
    }

    @Test func strokeOrderTemplateIsUsableForScoring() throws {
        // The stroke-order font renders with digit annotations; after stripping,
        // its マ should land in the normal same-glyph cross-font range (measured
        // 4.2 vs Hiragino; unstripped digits inflate the bbox well past that).
        let annotated = try #require(KanaSketch.glyphGrid("マ", font: "KanjiStrokeOrders"))
        let clean = try #require(KanaSketch.glyphGrid("マ", font: "HiraginoSans-W6"))
        #expect(KanaSketch.distance(annotated, annotated) == 0)
        #expect(KanaSketch.distance(annotated, clean) < 6)
    }

    @Test func traceTemplateImageIsDigitFreeAndSized() async throws {
        // The on-screen Write template must render the glyph shape without the
        // font's baked-in stroke-number digits (they'd read as clutter, not ink).
        let size = 320
        let img = try #require(await KanaSketch.strokeTemplateImage("マ", pixelSize: size))
        #expect(Int(img.size.width) == size && Int(img.size.height) == size)

        guard let cg = img.cgImage, let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { Issue.record("no pixel data"); return }
        let bpr = cg.bytesPerRow
        var ink = 0
        for y in 0..<size {
            for x in 0..<size where bytes[y * bpr + x * 4 + 3] > 40 { ink += 1 }
        }
        #expect(ink > 0)                       // the glyph itself still renders
        #expect(ink < size * size / 3)         // and isn't just a filled block (stripping worked)
    }

    @Test func strokeCountsCoverEveryDrawableKana() throws {
        // Counts come from the bundled KanaChart.json (minna vocab/kana.json) —
        // spot-check known textbook values, then require them on every cell.
        let all = (KanaData.seion + KanaData.dakuon + KanaData.youon)
            .flatMap { $0 }.filter { !$0.isEmpty }
        let a = try #require(all.first { $0.hiragana == "あ" })
        #expect(a.hiraganaStrokes == 3 && a.katakanaStrokes == 2)     // あ3 / ア2
        let ga = try #require(all.first { $0.hiragana == "が" })
        #expect(ga.hiraganaStrokes == 5 && ga.katakanaStrokes == 4)   // か3+゛2 / カ2+゛2
        let kya = try #require(all.first { $0.hiragana == "きゃ" })
        #expect(kya.katakana == "キャ")                                // chart fixed キァ typo
        #expect(kya.hiraganaStrokes == 7 && kya.katakanaStrokes == 5) // き4+ゃ3 / キ3+ャ2
        for cell in all {
            #expect(cell.hiraganaStrokes > 0 && cell.katakanaStrokes > 0, "\(cell.romaji)")
        }
    }
}

// MARK: - Today deck & widget contract

struct TodayTests {
    private var lesson: [Vocab] { VocabStore.lesson(2).entries }

    /// Today deals the rung's whole pool — new words *and* the review window — because
    /// the challenge asks about both. Dealing only the new words left every review
    /// question unprepared for.
    @Test func deckIsTheChallengePoolNotJustNewWords() {
        let all = lesson
        // Rung 2 is the first that can carry review, so it's where the two differ.
        let pool = Challenge.pool(all, index: 2)
        let new = Challenge.newWords(all, index: 2)
        #expect(pool.count > new.count)
        #expect(new.allSatisfy { w in pool.contains { $0.id == w.id } })
    }

    /// The snapshot is the app↔widget wire format — it must round-trip stably, and a
    /// snapshot written before `challenge` existed must still decode.
    @Test func widgetSnapshotRoundTrips() throws {
        let words = lesson.prefix(7).map {
            TodayShared.Word(kana: $0.kana, kanji: $0.kanji, romaji: $0.romaji, meaning: $0.translation)
        }
        let snap = TodayShared.Snapshot(lesson: 2, words: Array(words), challenge: 3)
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(TodayShared.Snapshot.self, from: data)
        #expect(back.lesson == 2)
        #expect(back.words == Array(words))
        #expect(back.challenge == 3)

        let legacy = #"{"lesson":2,"words":[]}"#.data(using: .utf8)!
        let old = try JSONDecoder().decode(TodayShared.Snapshot.self, from: legacy)
        #expect(old.challenge == nil)
    }

    /// The whole point of deriving the rotation from the clock: the widget's timeline is
    /// rebuilt on every visit to the Today tab, and the word shown must not depend on *when*
    /// that rebuild happened. Two rebuilds inside one hour have to agree.
    @Test func rotationIsStableWithinAnHour() {
        // Written as a multiple of 3600 on purpose: the whole assertion is "same hour", so
        // the fixture has to start *on* a boundary. An arbitrary-looking epoch (1_700_000_000
        // is 800s past one) puts `late` in the next hour and fails for the wrong reason.
        let hour = Date(timeIntervalSince1970: 472_222 * 3600)
        let early = hour.addingTimeInterval(60)
        let late = hour.addingTimeInterval(59 * 60)
        #expect(TodayShared.rotationIndex(count: 7, at: early)
                == TodayShared.rotationIndex(count: 7, at: late))
    }

    /// ...and it must actually move on the hour, or nothing rotates at all.
    @Test func rotationAdvancesEveryHour() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let indices = (0..<7).map {
            TodayShared.rotationIndex(count: 7, at: base.addingTimeInterval(Double($0) * 3600))
        }
        #expect(Set(indices).count == 7)          // a full deck in 7 hours, no repeats
        #expect(TodayShared.rotationIndex(count: 7, at: base.addingTimeInterval(7 * 3600))
                == indices[0])                    // then wraps
    }

    /// A negative cursor is reachable by paging back on the widget, and Swift's `%` keeps
    /// the dividend's sign — an unguarded index would trap on `words[-1]`.
    @Test func rotationHandlesNegativeCursors() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for cursor in -20...20 {
            let idx = TodayShared.rotationIndex(count: 7, cursor: cursor, at: base)
            #expect((0..<7).contains(idx))
        }
        #expect(TodayShared.rotationIndex(count: 0, cursor: -3, at: base) == 0)   // empty deck
    }

    /// Entry dates have to land on clock hours, not on `now + n`, or every rebuild shifts
    /// the schedule and the rotation drifts.
    @Test func nextHourLandsOnAClockBoundary() {
        let mid = Date(timeIntervalSince1970: 1_700_001_234)      // mid-hour
        let next = TodayShared.nextHour(after: mid)
        #expect(next > mid)
        #expect(next.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600) == 0)
        #expect(next.timeIntervalSince(mid) <= 3600)
    }
}

// MARK: - Survey submissions

/// The survey schemas are enforced *server-side* by `firestore.rules`, whose `hasOnly` /
/// `hasAll` lists must match the app's field names exactly. A mismatch rejects every write
/// with no user-visible symptom — the failure surfaces only as a console line and a
/// `survey_failed` event — so these tests transcribe the published rules and compare.
///
/// This is the test that was missing when the shared context was introduced: the app began
/// sending five new fields while the deployed rules still closed on the old set, which would
/// have silently rejected every intro submission.
struct SurveyTests {
    /// Transcribed from `firestore.rules`' `context()`. Update both together, never one.
    private static let ruleContextKeys: Set<String> = [
        "platform", "app_version", "os", "device",
        "os_language", "app_language", "vocab_language", "region",
        "is_premium", "tier", "challenges_passed", "kana_answered",
        "sound_on", "analytics_excluded", "shown_fields",
        "text_size", "appearance", "last_screen",
        "knows_kana", "goal", "textbook_lesson",
        "debug", "v", "at",
    ]

    /// The primitive initializer, which is the only one a test can use: the convenience one
    /// is `@MainActor` because it reads `UIApplication`, and these tests are not.
    private var context: Survey.Context {
        Survey.Context(isPremium: false, tier: "none", challengesPassed: 0,
                       kanaAnswered: 0, textSize: "L", appearance: "light")
    }

    @Test func contextKeysMatchThePublishedRules() {
        #expect(Survey.Context.keys == Self.ruleContextKeys)
        // `fields` omits `at` deliberately — the server stamps it, so the map the app
        // builds is the declared set minus that one key.
        #expect(Set(context.fields.keys) == Self.ruleContextKeys.subtracting(["at"]))
    }

    /// The intro adds no fields of its own any more — its three answers are context fields
    /// that every collection carries, which is why the rules take `hasExactly(data, [])`
    /// there. `submit(_ intro:)` still merges them, to decide the *value*, not the key set.
    @Test func introSubmissionIsExactlyTheContext() {
        let answers: Set<String> = ["knows_kana", "textbook_lesson", "goal"]
        #expect(answers.isSubset(of: Survey.Context.keys))
        let all = Set(context.fields.keys).union(answers)
        #expect(all == Self.ruleContextKeys.subtracting(["at"]))
        // Values the rules pin to a closed set.
        #expect(context.fields["platform"] as? String == "iOS")
    }

    /// One row per star tap, in its own collection — `survey_feedback` requires a non-empty
    /// `message`, which a rating has no way to supply.
    @Test func ratingSubmissionCarriesContextPlusItsStars() {
        let own: Set<String> = ["stars"]
        let all = Set(context.fields.keys).union(own)
        #expect(all == Self.ruleContextKeys.subtracting(["at"]).union(own))
        // The rules accept 1-5 only: no answer writes no row rather than a 0.
        #expect(Survey.Rating(stars: 1).stars >= 1)
        #expect(Survey.Rating(stars: 5).stars <= 5)
    }

    /// Transcribed from `firestore.rules`' `survey_feedback` own-field list. The three
    /// second-level fields (`area`, `lesson`, `item`) are the reason this is spelled out
    /// separately: they were added to the payload and the rules in one change, and the
    /// moment those two lists disagree every feedback write is rejected with nothing to
    /// show for it but a console line.
    private static let ruleFeedbackKeys: Set<String> = [
        "kind", "area", "message", "email", "source", "stars", "lesson", "item",
    ]

    @Test func feedbackSubmissionCarriesContextPlusItsOwnFields() {
        let all = Set(context.fields.keys).union(Self.ruleFeedbackKeys)
        #expect(all == Self.ruleContextKeys.subtracting(["at"]).union(Self.ruleFeedbackKeys))
        // The payload the app actually builds, not just the declared set — a field named in
        // the rules but never sent fails `hasAll` exactly as loudly as an unexpected one
        // fails `hasOnly`.
        let draft = FeedbackDraft(kind: .bug, area: .audio, message: "no sound", stars: 3)
        let submission = draft.submission(source: .settings)
        #expect(submission != nil)
        #expect(Set(Self.feedbackPayload(submission!).keys) == Self.ruleFeedbackKeys)
    }

    /// The same merge `Survey.submit(_ feedback:)` performs, minus the context — kept here
    /// because the real one writes to Firestore and can't be inspected.
    private static func feedbackPayload(_ f: Survey.Feedback) -> [String: Any] {
        ["kind": f.kind, "area": f.area, "message": f.message, "email": f.email,
         "source": f.source, "stars": f.stars, "lesson": f.lesson, "item": f.item]
    }

    /// Every closed-set value in the feedback payload, against the rules' own lists. A value
    /// the app can produce but the rules reject is a submission that vanishes.
    @Test func feedbackEnumsAreWithinWhatTheRulesAccept() {
        let sources: Set<String> = ["settings", "rating", "hidden", "card"]
        #expect(Set(Feedback.Source.allCases.map(\.rawValue)) == sources)
        let areas: Set<String> = ["audio", "kana", "lesson", "challenge",
                                  "today", "watch", "purchase", "other"]
        #expect(Set(Feedback.Area.allCases.map(\.rawValue)) == areas)
        // The rules accept the eight plus "" — unanswered, and the value every non-bug row
        // carries. Nothing else may reach the field.
        let accepted = areas.union([""])
        for kind in Feedback.Kind.allCases {
            for area in Feedback.Area.allCases {
                var draft = FeedbackDraft(kind: kind, message: "x")
                draft.area = area
                #expect(accepted.contains(draft.submittedArea))
            }
        }
    }

    /// The lesson int the rules bound to 0…50, and the romaji they length-cap. The cap has to
    /// bite in the app, because over the limit the rules reject the whole document rather
    /// than the one field.
    @Test func reportedItemStaysWithinTheRulesBounds() {
        for lesson in [1, 25, 50] {
            let draft = FeedbackDraft(kind: .content,
                                      item: Feedback.Item(lesson: lesson, romaji: "tsukue"),
                                      message: "wrong meaning")
            #expect(draft.submittedLesson >= 0 && draft.submittedLesson <= 50)
            #expect(draft.submittedItem.count <= Feedback.itemLimit)
        }
        let long = FeedbackDraft(kind: .content,
                                 item: Feedback.Item(lesson: 47,
                                                     romaji: String(repeating: "a", count: 200)),
                                 message: "wrong meaning")
        #expect(long.submittedItem.count == Feedback.itemLimit)
        // The longest romaji in the bundled data, so the cap is headroom rather than a
        // truncation anybody meets.
        let longest = VocabStore.allVocab().map(\.romaji.count).max() ?? 0
        #expect(longest <= Feedback.itemLimit)
    }

    /// Every enum the rules validate. A value the app can produce but the rules reject is
    /// a silently dropped submission.
    @Test func enumsAreWithinWhatTheRulesAccept() {
        let kana: Set<String> = ["none", "hiragana", "both"]
        #expect(Set(Intro.KanaLevel.allCases.map(\.rawValue)) == kana)
        let goals: Set<String> = ["travel", "jlpt", "work", "culture", "other"]
        #expect(Set(Intro.Goal.allCases.map(\.rawValue)) == goals)
        // The context carries the same two answers for *every* collection, where "not
        // asked yet" is legitimate — hence one extra accepted value in each list, and it
        // has to be the sentinel `IntroAnswers` already reports to Analytics.
        #expect(IntroAnswers.unanswered == "unanswered")
        #expect(IntroAnswers.unansweredLesson == -1)
        #expect(kana.union([IntroAnswers.unanswered])
                .contains(context.fields["knows_kana"] as? String ?? ""))
        #expect(goals.union([IntroAnswers.unanswered])
                .contains(context.fields["goal"] as? String ?? ""))
        // -1 (unanswered) through 50, so the sentinel can't be read as lesson 0.
        let lesson = context.fields["textbook_lesson"] as? Int ?? -99
        #expect(lesson >= -1 && lesson <= 50)
    }

    /// `shown_fields` is one comma-joined string in a fixed order, not four fields and not
    /// a map: the rules close the key set, and a fixed order means two senders with the
    /// same card configuration produce the identical value instead of two spellings of it.
    @Test func shownFieldsIsAFixedOrderCommaList() {
        let value = context.fields["shown_fields"] as? String ?? "?"
        #expect(value.count <= 40)
        let parts = value.isEmpty ? [] : value.components(separatedBy: ",")
        let order = ["kanji", "kana", "romaji", "translation"]
        #expect(parts.allSatisfy(order.contains))
        // Subsequence, not just membership — the order is the guarantee.
        #expect(parts == order.filter(parts.contains))
    }

    /// Truncated to the length the rules cap, because a long screen name must degrade to a
    /// short one rather than rejecting the whole document.
    @Test func lastScreenIsRecordedAndCapped() {
        Survey.recordScreen(String(repeating: "x", count: 60))
        #expect(Survey.lastScreen.count == 40)
        Survey.recordScreen("kana_write")
        #expect(context.fields["last_screen"] as? String == "kana_write")
    }

    /// The two UIKit reads, on the actor they require. `appearance` is the one field the
    /// rules pin to an exact pair of values, so a third one would reject every write.
    @Test @MainActor func textSizeAndAppearanceAreWithinWhatTheRulesAccept() {
        #expect(["light", "dark"].contains(AppInfo.appearance))
        let sizes = ["XS", "S", "M", "L", "XL", "XXL", "XXXL",
                     "AX1", "AX2", "AX3", "AX4", "AX5", "unknown"]
        #expect(sizes.contains(AppInfo.textSize))
        #expect(AppInfo.textSize.count <= 20)
    }

    /// The build-flavour discriminator has to actually discriminate, or dev rows can't be
    /// filtered out of real results.
    @Test func debugBuildIsFlaggedInTheTestTarget() {
        #expect(AppInfo.isDebugBuild)
        #expect(context.fields["debug"] as? Bool == true)
    }

    @Test func appInfoReportsUsableDiagnostics() {
        #expect(AppInfo.os.hasPrefix("iOS "))
        #expect(!AppInfo.version.isEmpty)
        #expect(!AppInfo.device.isEmpty)
    }
}

// MARK: - The feedback draft (what the sheet holds, and what it sends)

/// The gate and the two second-level answers, tested without presenting a sheet — the whole
/// reason `Feedback`/`FeedbackDraft` are view-free.
///
/// The rule these all circle is that **only an empty message may block a send**. Every field
/// added to this form since is optional, and each new one is a new chance to accidentally
/// make it a second gate.
struct FeedbackTests {
    @Test func onlyAnEmptyMessageBlocksSending() {
        #expect(!FeedbackDraft().isValid)
        #expect(!FeedbackDraft(message: "   \n ").isValid)
        // No kind, no area, no item, no email, no stars — still sendable.
        let bare = FeedbackDraft(message: "the audio cuts out")
        #expect(bare.isValid)
        let submission = bare.submission(source: .settings)
        #expect(submission?.kind == "other")   // unpicked goes to the wire as `other`
        #expect(submission?.area == "")
        #expect(submission?.lesson == 0)
        #expect(submission?.item == "")
    }

    /// `area` belongs to `Something's broken` alone. The scoping is in the draft rather than
    /// the view because the kind can be re-picked after the area was answered, and a row
    /// whose `area` contradicts its `kind` would make both fields unreadable.
    @Test func areaIsEmptyUnlessTheKindIsBug() {
        for kind in Feedback.Kind.allCases {
            var draft = FeedbackDraft(kind: kind, message: "x")
            draft.area = .audio
            #expect(draft.submittedArea == (kind == .bug ? "audio" : ""))
            #expect(draft.submission(source: .settings)?.area == (kind == .bug ? "audio" : ""))
        }
        // A bug report that skipped the follow-up is "" too — indistinguishable from an
        // idea's empty area on purpose: both mean nobody said.
        #expect(FeedbackDraft(kind: .bug, message: "x").submittedArea == "")
    }

    /// `lesson` and `item` belong to `A wrong word, meaning or sound` alone, for the same
    /// reason: re-picking the kind must not leave a word attached to a report that is no
    /// longer about one.
    @Test func lessonAndItemAreEmptyUnlessTheKindIsContent() {
        for kind in Feedback.Kind.allCases {
            var draft = FeedbackDraft(kind: kind, message: "x")
            draft.item = Feedback.Item(lesson: 12, romaji: "tsukue")
            let content = kind == .content
            #expect(draft.submittedLesson == (content ? 12 : 0))
            #expect(draft.submittedItem == (content ? "tsukue" : ""))
        }
    }

    /// The flag on a practice screen: the sheet opens knowing the bucket and the word, so the
    /// sender only has to say what's wrong. This is the only route that fills these two
    /// fields — the form itself has no word field.
    @Test func aReportFromTheFlagSendsWithJustAMessage() throws {
        // A real entry, read out of the bundled data rather than spelled here: the assertion
        // below is that the two stored fields reconstruct this word's own `Vocab.id`.
        let word = try #require(VocabStore.lesson(12).entries.first)
        var draft = FeedbackDraft()
        draft.kind = .content
        draft.item = Feedback.Item(lesson: word.lesson, romaji: word.romaji)
        #expect(!draft.isValid)   // the word alone is not a report
        draft.message = "the English says desk, this is a chair"
        let submission = try #require(draft.submission(source: .card))
        #expect(submission.source == "card")
        #expect(submission.kind == "content")
        #expect(submission.lesson == 12)
        #expect(submission.item == word.romaji)
        // `lesson` + `item` reconstruct `Vocab.id`, which is the point of storing both.
        #expect("\(submission.lesson)/\(submission.item)" == word.id)
    }

    /// A kana flashcard has no lesson: 0 with a non-empty item is a legitimate row, and the
    /// rules allow exactly that. Without this, kana reports would either be rejected or have
    /// to lie about a lesson.
    @Test func aKanaReportCarriesNoLessonButStillNamesTheItem() {
        var draft = FeedbackDraft(kind: .content, message: "this clip is cut short")
        draft.item = Feedback.Item(lesson: 0, romaji: "kya")
        #expect(draft.submittedLesson == 0)
        #expect(draft.submittedItem == "kya")
    }

    /// The analytics half. Buckets travel (they aggregate), the romaji never does — `Track` is
    /// the aggregate seam and content belongs only in the collection the sender wrote to.
    @Test func trackParamsCountBucketsAndNeverContent() {
        var draft = FeedbackDraft(kind: .content, message: "wrong meaning", email: "a@b.c")
        draft.item = Feedback.Item(lesson: 12, romaji: "tsukue")
        let params = draft.trackParams(source: .card)
        #expect(params["area"] as? String == "")
        #expect(params["lesson"] as? Int == 12)
        #expect(params["has_item"] as? Bool == true)
        #expect(params["has_email"] as? Bool == true)
        #expect(params["message_length"] as? Int == 13)
        let values = params.values.compactMap { $0 as? String }
        #expect(!values.contains("tsukue"))
        #expect(!values.contains("wrong meaning"))
        #expect(!values.contains("a@b.c"))
    }

    /// Both follow-up lists are closed sets with a localized label and an SF Symbol per case,
    /// like every other chip list in the app. A missing label would render as the raw key.
    @Test func everyAreaHasALabelAndAnIcon() {
        #expect(Feedback.Area.allCases.count == 8)
        for area in Feedback.Area.allCases {
            #expect(!area.titleKey.isEmpty)
            #expect(!area.title.isEmpty)
            #expect(!area.icon.isEmpty)
        }
        // Three labels are deliberately the tab names already in the table, so the chip calls
        // that part of the app what the tab bar calls it.
        #expect(Feedback.Area.kana.titleKey == "Kana")
        #expect(Feedback.Area.lesson.titleKey == "Lessons")
    }
}

// MARK: - Legal documents

struct LegalTests {
    @Test func privacyAndTermsAreBundled() throws {
        for name in ["PrivacyPolicy", "TermsOfUse"] {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "txt"),
                                   "\(name).txt not bundled")
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.count > 200)
        }
    }
}

// MARK: - App localization (UIStrings.json)

struct LocalizationTests {
    private func table() throws -> [String: [String: String]] {
        let url = try #require(Bundle.main.url(forResource: "UIStrings", withExtension: "json"))
        return try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: url))
    }

    @Test func uiStringsCoverEveryLanguageAndKey() throws {
        let table = try table()
        // The UI list is UIStrings' own key set, and every meaning language must have a
        // UI to sit in — but not the reverse. They were the same 17 codes while Minna
        // was the only course; JLPT ships three meaning languages against the same 17
        // UI languages, so equality here would be asserting a coincidence.
        #expect(Set(table.keys) == Set(L.availableLanguages))
        #expect(Set(VocabStore.availableLanguages).isSubset(of: Set(table.keys)))
        let enKeys = try #require(table["en"]).keys
        #expect(enKeys.count >= 70)
        for (lang, dict) in table {
            #expect(Set(dict.keys) == Set(enKeys), "key mismatch in \(lang)")
            #expect(dict.values.allSatisfy { !$0.isEmpty }, "blank translation in \(lang)")
        }
    }

    /// Every translation of a format string must keep its %@ placeholders — a missing
    /// one renders broken UI text in that language.
    @Test func formatPlaceholdersSurviveTranslation() throws {
        let table = try table()
        let en = try #require(table["en"])
        let formatKeys = en.keys.filter { $0.contains("%@") }
        #expect(!formatKeys.isEmpty)
        for (lang, dict) in table {
            for key in formatKeys {
                let expected = en[key]!.components(separatedBy: "%@").count - 1
                let got = (dict[key] ?? "").components(separatedBy: "%@").count - 1
                #expect(got == expected, "\(lang) '\(key)' has \(got) placeholders, wants \(expected)")
            }
        }
    }

    /// Every literal `%` must be escaped as `%%`.
    ///
    /// `L.t(_:_:)` runs the string through `String(format:)`, so a bare `%` is read as
    /// the start of a format specifier. A trailing one ("Save %@%") is simply eaten —
    /// the sign vanishes from the UI. Worse, a `%` before a letter ("%@ % sparen")
    /// parses as `%s`, i.e. a C-string specifier applied to something that isn't one.
    /// Both only ever show up by eye, in one language, on one screen.
    @Test func literalPercentSignsAreEscaped() throws {
        for (lang, dict) in try table() {
            for (key, value) in dict {
                let leftover = value
                    .replacingOccurrences(of: "%@", with: "")
                    .replacingOccurrences(of: "%%", with: "")
                #expect(!leftover.contains("%"),
                        "\(lang) '\(key)' has an unescaped % — write %% for a literal sign")
            }
        }
    }

    /// And the escaping must actually round-trip: formatting a percent string has to
    /// produce exactly one visible `%`.
    @Test func formattedPercentStringsRenderTheSign() throws {
        let table = try table()
        for (lang, dict) in table {
            for key in dict.keys where key.contains("%@%") {
                let rendered = String(format: dict[key]!, "42")
                #expect(rendered.contains("42"), "\(lang) '\(key)' lost its number")
                #expect(rendered.filter { $0 == "%" }.count == 1,
                        "\(lang) '\(key)' rendered \(rendered) — expected exactly one % sign")
            }
        }
    }

    @Test func lookupFallsBackAndDeviceDefaultShips() {
        #expect(L.t("a key that does not exist") == "a key that does not exist")
        #expect(L.availableLanguages.contains(L.deviceDefault))
    }
}

// MARK: - KanaResult persistence (SwiftData)

@MainActor
struct PersistenceTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: KanaResult.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// Answering the quiz upserts one row per kana (unique romaji) — never duplicates —
    /// and the session score tracks the number of answers.
    @Test func upsertNeverDuplicatesAndTracksScore() throws {
        let ctx = try makeContext()
        let model = KanaQuizModel(pool: KanaData.seion.flatMap { $0 })
        var answered = Set<String>()
        for _ in 0..<40 {
            answered.insert(model.answer.romaji)
            model.choose(0, context: ctx)   // records model.answer regardless of pick
            model.next()
        }
        let stored = try ctx.fetch(FetchDescriptor<KanaResult>())
        #expect(stored.count == answered.count)
        #expect(Set(stored.map(\.romaji)).count == stored.count)
        #expect(model.total == 40)
    }

    /// Mirrors KanaBrowserView.clearAll — wipes all learned results.
    @Test func clearAllEmptiesTheStore() throws {
        let ctx = try makeContext()
        ctx.insert(KanaResult(romaji: "a", isCorrect: true))
        ctx.insert(KanaResult(romaji: "ka", isCorrect: false))
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<KanaResult>()).count == 2)

        try ctx.delete(model: KanaResult.self)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<KanaResult>()).isEmpty)
    }
}

// MARK: - Challenge ladder

@MainActor
struct ChallengeTests {
    private var lesson1: [Vocab] { VocabStore.lesson(1).entries }

    /// Every lesson gets a ladder covering exactly its words — no word unreachable,
    /// none counted twice.
    @Test func laddersCoverEveryLessonExactly() {
        for lesson in VocabStore.lessons() {
            let words = lesson.entries
            let steps = Challenge.steps(wordCount: words.count)
            #expect(steps.reduce(0, +) == words.count)
            #expect(Challenge.count(wordCount: words.count) == steps.count)

            // Coverage is the union of what each rung introduces — the pool is now a
            // sliding window, so no single rung sees the whole lesson.
            var introduced = Set<String>()
            for i in 1...steps.count {
                introduced.formUnion(Challenge.newWords(words, index: i).map(\.id))
            }
            #expect(introduced.count == words.count)
        }
    }

    /// The review window: a challenge sees its own words plus the previous two steps,
    /// never the whole lesson. That's what stops review thinning out as a lesson grows.
    @Test func poolIsASlidingWindow() {
        let words = VocabStore.lesson(40).entries       // 63 words — the longest ladder
        let steps = Challenge.steps(wordCount: words.count)
        #expect(steps.count > Challenge.reviewWindow)   // long enough for the window to bite

        for i in 1...steps.count {
            let pool = Challenge.pool(words, index: i)
            let expected = steps[max(0, i - Challenge.reviewWindow)..<i].reduce(0, +)
            #expect(pool.count == expected)
            // Every new word is in its own pool, and there's room left for review.
            let new = Challenge.newWords(words, index: i)
            #expect(new.allSatisfy { w in pool.contains { $0.id == w.id } })
            if i > 1 { #expect(pool.count > new.count) }
        }
        // The final rung must not see the whole lesson any more.
        #expect(Challenge.pool(words, index: steps.count).count < words.count)
    }

    /// The balance guarantees, checked on real data — these are the whole reason the
    /// steps are computed rather than fixed.
    @Test func everyRungIsWellSized() {
        for lesson in VocabStore.lessons() {
            let words = lesson.entries
            let steps = Challenge.steps(wordCount: words.count)

            // Rung 1 is a full quiz's worth: nothing to review yet, and a short first
            // rung would be the strictest in the lesson (fewer questions = fewer
            // mistakes allowed to reach the pass mark).
            #expect(steps[0] == Challenge.questionsPerChallenge)

            for (i, size) in steps.enumerated().dropFirst() {
                // Never a token rung — a lesson must not end on "1 new word".
                #expect(size >= 3, "lesson \(lesson.number) rung \(i + 1) adds only \(size)")
                // Always room left for review, or the cumulative pool is pointless:
                // a rung of 10 new words would fill all 10 questions with itself.
                #expect(size <= Challenge.questionsPerChallenge - Challenge.minReviewSlots,
                        "lesson \(lesson.number) rung \(i + 1) leaves no review room")
            }

            // Every rung can therefore ask the full, uniform question count.
            for i in 1...steps.count {
                #expect(Challenge.pool(words, index: i).count >= Challenge.questionsPerChallenge)
            }
        }
    }

    /// Uniform length is what makes the pass bar and the star bands mean the same
    /// thing on every rung: exactly 2 misses allowed, and 100/90/80 all reachable.
    @Test func everyChallengeAsksTheSameNumberOfQuestions() {
        for lesson in VocabStore.lessons() {
            let words = lesson.entries
            let total = Challenge.count(wordCount: words.count)
            for i in 1...total {
                let model = ChallengeModel(lessonNumber: lesson.number, index: i,
                                           total: total, words: words)
                #expect(model.questions.count == Challenge.questionsPerChallenge)
            }
        }
        // 8/10 passes, 7/10 does not — the same bar everywhere.
        #expect(Challenge.stars(score: 80) == 1)
        #expect(Challenge.stars(score: 70) == 0)
    }

    /// The pool grows monotonically and every challenge introduces something new —
    /// otherwise a rung would be pure review and teach nothing.
    @Test func eachStepIntroducesGenuinelyNewWords() {
        for lesson in VocabStore.lessons() {
            let words = lesson.entries
            let n = Challenge.count(wordCount: words.count)
            var seen = Set<String>()
            for i in 1...n {
                let new = Challenge.newWords(words, index: i)
                #expect(!new.isEmpty)
                // Never re-introduces a word an earlier rung already taught.
                #expect(new.allSatisfy { !seen.contains($0.id) })
                seen.formUnion(new.map(\.id))
                // And a rung can always draw on what it just introduced.
                let pool = Challenge.pool(words, index: i)
                #expect(new.allSatisfy { w in pool.contains { $0.id == w.id } })
            }
        }
    }

    /// Difficulty climbs by absolute rung, and — crucially — doesn't stretch out for
    /// long lessons. Only the first challenge may be single-form.
    @Test func formsHardenAcrossTheLadder() {
        for total in [2, 5, 9] {
            #expect(Challenge.forms(index: 1, of: total).count == 1)      // recognition only
            #expect(!Challenge.forms(index: 1, of: total).contains { $0.from == .audio })
            for i in 2...max(2, total) {
                // Recall arrives immediately after the intro rung, in every lesson.
                #expect(Challenge.forms(index: i, of: total).count > 1)
                #expect(Challenge.forms(index: i, of: total).contains { $0.to == .kana })
            }
            #expect(Challenge.forms(index: 3, of: total).contains { $0.from == .audio })
        }
        // No lesson may spend more than its first rung on a single form.
        for lesson in VocabStore.lessons() {
            let total = Challenge.count(wordCount: lesson.entries.count)
            let singleForm = (1...total).filter { Challenge.forms(index: $0, of: total).count == 1 }
            #expect(singleForm == [1], "lesson \(lesson.number) has single-form rungs \(singleForm)")
        }
    }

    /// A generated challenge must actually *use* the variety it unlocked. Sampling a
    /// pair per question independently could still yield ten identical forms by
    /// chance, so the pairs are dealt in rotation — this pins that down.
    @Test func challengesMixPromptDirections() {
        for lesson in VocabStore.lessons() {
            let words = lesson.entries
            let total = Challenge.count(wordCount: words.count)
            for i in 2...total {
                let model = ChallengeModel(lessonNumber: lesson.number, index: i,
                                           total: total, words: words)
                let used = Set(model.questions.map { "\($0.from.label)->\($0.to.label)" })
                #expect(used.count >= 2,
                        "lesson \(lesson.number) challenge \(i) used only \(used)")
                // Both directions present: recognition and recall.
                #expect(model.questions.contains { $0.to == .translation })
                #expect(model.questions.contains { $0.to != .translation })
            }
        }
    }

    /// Stars follow the documented bands, and nothing below the pass mark scores one.
    @Test func starBands() {
        #expect(Challenge.stars(score: 100) == 3)
        #expect(Challenge.stars(score: 95) == 2)
        #expect(Challenge.stars(score: 90) == 2)
        #expect(Challenge.stars(score: 85) == 1)
        #expect(Challenge.stars(score: Challenge.passScore) == 1)
        #expect(Challenge.stars(score: Challenge.passScore - 1) == 0)
        #expect(Challenge.stars(score: 0) == 0)
    }

    /// Generated questions are always answerable: bounded in number, four distinct
    /// options, the answer present, and the form pair valid for that word.
    @Test func generatedQuestionsAreAnswerable() {
        for lesson in VocabStore.lessons() {
            let words = lesson.entries
            let total = Challenge.count(wordCount: words.count)
            for i in 1...total {
                let model = ChallengeModel(lessonNumber: lesson.number, index: i,
                                           total: total, words: words)
                let pool = Challenge.pool(words, index: i)
                #expect(model.questions.count == min(Challenge.questionsPerChallenge, pool.count))

                for q in model.questions {
                    #expect(q.options.contains { $0.id == q.answer.id })
                    // Usually 4; a pool with homophones / shared glosses may yield 3
                    // after the prompt-collision guard, never fewer than 2.
                    #expect((2...4).contains(q.options.count))
                    if pool.count >= 6 { #expect(q.options.count >= 3) }
                    // Option labels must be distinct, or two buttons look identical.
                    let labels = q.options.map { q.to.value($0) }
                    #expect(Set(labels).count == labels.count)
                    // And no distractor may match the prompt: a homophone under an
                    // audio prompt, or a shared gloss under a translation prompt,
                    // would be a second right answer that gets marked wrong.
                    let prompt = q.from.value(q.answer)
                    #expect(q.options.allSatisfy { $0.id == q.answer.id || q.from.value($0) != prompt })
                    #expect(Challenge.supports(q.answer, from: q.from, to: q.to)
                            || (q.from == .kana && q.to == .translation))
                    #expect(pool.contains { $0.id == q.answer.id })
                }
            }
        }
    }

    /// A challenge always tests what it just taught: every newly introduced word gets
    /// asked (as long as there's room in the question cap).
    @Test func newWordsAreAlwaysAsked() {
        let words = lesson1
        let total = Challenge.count(wordCount: words.count)
        for i in 1...total {
            let model = ChallengeModel(lessonNumber: 1, index: i, total: total, words: words)
            let new = Challenge.newWords(words, index: i)
            guard new.count <= Challenge.questionsPerChallenge else { continue }
            let asked = Set(model.questions.map(\.answer.id))
            #expect(new.allSatisfy { asked.contains($0.id) })
        }
    }

    /// Scoring a full run: all-correct passes with 3 stars, all-wrong fails with none,
    /// and the model refuses to advance past an unanswered question.
    @Test func scoringAndFlow() {
        let words = lesson1
        let total = Challenge.count(wordCount: words.count)

        let perfect = ChallengeModel(lessonNumber: 1, index: 1, total: total, words: words)
        while let q = perfect.question {
            let right = q.options.firstIndex { $0.id == q.answer.id }!
            perfect.advance()                      // no-op: nothing picked yet
            #expect(perfect.question?.id == q.id)
            perfect.choose(right)
            perfect.choose(right)                  // second pick ignored
            perfect.advance()
        }
        #expect(perfect.isDone)
        #expect(perfect.scorePercent == 100)
        #expect(perfect.passed)
        #expect(perfect.stars == 3)
        #expect(perfect.missed.isEmpty)

        let failed = ChallengeModel(lessonNumber: 1, index: 1, total: total, words: words)
        let questionCount = failed.questions.count
        while let q = failed.question {
            failed.choose(q.options.firstIndex { $0.id != q.answer.id }!)
            failed.advance()
        }
        #expect(failed.scorePercent == 0)
        #expect(!failed.passed)
        #expect(failed.stars == 0)
        #expect(failed.missed.count == questionCount)
    }
}

// MARK: - Challenge persistence

@MainActor
struct ChallengeResultTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ChallengeResult.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// Repeated attempts upsert one row, keep the *best* score, and never regress.
    @Test func keepsBestScoreAcrossAttempts() throws {
        let ctx = try makeContext()
        ChallengeResult.record(lesson: 1, index: 1, score: 60, context: ctx)
        ChallengeResult.record(lesson: 1, index: 1, score: 90, context: ctx)
        ChallengeResult.record(lesson: 1, index: 1, score: 70, context: ctx)

        let rows = try ctx.fetch(FetchDescriptor<ChallengeResult>())
        #expect(rows.count == 1)
        let row = rows[0]
        #expect(row.attempts == 3)
        #expect(row.bestScore == 90)
        #expect(row.stars == 2)
        #expect(row.isPassed)
    }

    /// A failing run records the attempt but leaves the challenge incomplete.
    @Test func failingDoesNotComplete() throws {
        let ctx = try makeContext()
        let row = ChallengeResult.record(lesson: 2, index: 1,
                                         score: Challenge.passScore - 1, context: ctx)
        #expect(row.attempts == 1)
        #expect(!row.isPassed)
        #expect(row.stars == 0)
    }

    /// completedAt marks the *first* pass, so replaying later doesn't move it.
    @Test func completionTimestampIsStable() throws {
        let ctx = try makeContext()
        let first = ChallengeResult.record(lesson: 3, index: 1, score: 80, context: ctx)
        let stamp = first.completedAt
        #expect(stamp != nil)
        let again = ChallengeResult.record(lesson: 3, index: 1, score: 100, context: ctx)
        #expect(again.completedAt == stamp)
        #expect(again.bestScore == 100)
    }

    /// Unlocking is sequential — challenge 1 always open, the rest need the prior pass.
    @Test func unlockingIsSequential() throws {
        let ctx = try makeContext()
        var results = ChallengeResult.byIndex(lesson: 4, context: ctx)
        #expect(ChallengeResult.isUnlocked(index: 1, results: results))
        #expect(!ChallengeResult.isUnlocked(index: 2, results: results))

        ChallengeResult.record(lesson: 4, index: 1, score: 50, context: ctx)   // failed
        results = ChallengeResult.byIndex(lesson: 4, context: ctx)
        #expect(!ChallengeResult.isUnlocked(index: 2, results: results))
        #expect(ChallengeResult.passedCount(results: results) == 0)

        ChallengeResult.record(lesson: 4, index: 1, score: 80, context: ctx)   // passed
        results = ChallengeResult.byIndex(lesson: 4, context: ctx)
        #expect(ChallengeResult.isUnlocked(index: 2, results: results))
        #expect(!ChallengeResult.isUnlocked(index: 3, results: results))
        #expect(ChallengeResult.passedCount(results: results) == 1)
    }

    /// Today's study deck points at the first unpassed rung: 1 on a fresh lesson,
    /// skipping passed rungs (not failed ones), nil once the ladder is cleared.
    @Test func firstUnpassedTracksTheLadder() throws {
        let ctx = try makeContext()
        var results = ChallengeResult.byIndex(lesson: 7, context: ctx)
        #expect(ChallengeResult.firstUnpassed(total: 3, results: results) == 1)

        ChallengeResult.record(lesson: 7, index: 1, score: 90, context: ctx)   // passed
        ChallengeResult.record(lesson: 7, index: 2, score: 50, context: ctx)   // failed
        results = ChallengeResult.byIndex(lesson: 7, context: ctx)
        #expect(ChallengeResult.firstUnpassed(total: 3, results: results) == 2)

        ChallengeResult.record(lesson: 7, index: 2, score: 80, context: ctx)
        ChallengeResult.record(lesson: 7, index: 3, score: 100, context: ctx)
        results = ChallengeResult.byIndex(lesson: 7, context: ctx)
        #expect(ChallengeResult.firstUnpassed(total: 3, results: results) == nil)
        #expect(ChallengeResult.firstUnpassed(total: 0, results: results) == nil)
    }

    /// CloudKit forbids unique constraints, so a two-device merge can leave duplicate
    /// rows for one challenge. Readers must collapse them to the strongest — and a
    /// later `record` must update that strongest row, not a weaker twin.
    @Test func duplicateRowsFromSyncCollapseToTheStrongest() throws {
        let ctx = try makeContext()
        // Simulate a merge: two rows for lesson 9 / challenge 1 from different devices.
        ctx.insert(ChallengeResult(lesson: 9, index: 1, bestScore: 70, stars: 0, attempts: 4))
        ctx.insert(ChallengeResult(lesson: 9, index: 1, bestScore: 90, stars: 2,
                                   attempts: 1, completedAt: .now))
        try ctx.save()

        let results = ChallengeResult.byIndex(lesson: 9, context: ctx)
        #expect(results[1]?.bestScore == 90)                 // strongest wins the read
        #expect(ChallengeResult.passedCount(results: results) == 1)   // counted once
        #expect(ChallengeResult.isUnlocked(index: 2, results: results))

        // Recording another attempt lands on the strongest row and keeps its best.
        let row = ChallengeResult.record(lesson: 9, index: 1, score: 80, context: ctx)
        #expect(row.bestScore == 90)
        #expect(row.attempts == 2)
    }

    /// Results are scoped per lesson — lesson 5's ladder can't be unlocked by lesson 4.
    @Test func resultsAreScopedPerLesson() throws {
        let ctx = try makeContext()
        ChallengeResult.record(lesson: 4, index: 1, score: 100, context: ctx)
        let other = ChallengeResult.byIndex(lesson: 5, context: ctx)
        #expect(other.isEmpty)
        #expect(!ChallengeResult.isUnlocked(index: 2, results: other))
    }
}

// MARK: - First-launch intro

struct IntroTests {
    /// An isolated defaults domain per test — the real one belongs to the simulator's app
    /// and Swift Testing runs cases in parallel.
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "IntroTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, suite)
    }

    /// Five cards, numbered 1…5 in paging order — the raw values are what `intro_card`
    /// and `intro_skip` report, so they double as the analytics contract.
    @Test func fiveCardsNumberedInPagingOrder() {
        #expect(Intro.Card.allCases.count == 5)
        #expect(Intro.Card.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
        #expect(Intro.Card.allCases == [.meanings, .kana, .modes, .challenge, .today])
    }

    /// The one answer with a behavioural consumer. Only "not yet" diverts the landing
    /// tab; an unanswered question is not a "no".
    @Test func onlyNoKanaDivertsTheLandingTab() {
        #expect(Intro.landingTab(kana: .notYet) == .kana)
        #expect(Intro.landingTab(kana: .hiragana) == .today)
        #expect(Intro.landingTab(kana: .both) == .today)
        #expect(Intro.landingTab(kana: nil) == .today)
        // The raw values are the stored/reported wire format, not display text.
        #expect(Intro.KanaLevel.notYet.rawValue == "none")
        #expect(Intro.KanaLevel.allCases.map(\.rawValue) == ["none", "hiragana", "both"])
    }

    @Test func answersMapOntoPreferences() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        IntroAnswers(kana: .both, textbookLesson: 12, goal: .jlpt).save(to: defaults)
        #expect(defaults.bool(forKey: Pref.introAnswered))
        #expect(defaults.string(forKey: Pref.knowsKana) == "both")
        #expect(defaults.integer(forKey: Pref.textbookLesson) == 12)
        #expect(defaults.string(forKey: Pref.goal) == "jlpt")
    }

    /// "Never studied it" is the answer 0, not the absence of one — it has to be written,
    /// or a fresh beginner is indistinguishable from someone who skipped the card.
    @Test func startingFreshIsStoredAsZero() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        IntroAnswers(textbookLesson: 0).save(to: defaults)
        #expect(defaults.object(forKey: Pref.textbookLesson) as? Int == 0)
    }

    /// A skipped question writes no preference at all — the app keeps its own defaults
    /// rather than a guess. But the intro is still marked seen, or the tour reopens.
    @Test func skippedQuestionsWriteNothingButStillCloseTheIntro() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        IntroAnswers().save(to: defaults)
        #expect(defaults.bool(forKey: Pref.introAnswered))
        #expect(defaults.object(forKey: Pref.knowsKana) == nil)
        #expect(defaults.object(forKey: Pref.textbookLesson) == nil)
        #expect(defaults.object(forKey: Pref.goal) == nil)
    }

    /// `intro_done` always carries the same three params, answered or not, so a funnel can
    /// count "asked but not answered" instead of finding a param missing.
    @Test func trackParamsAlwaysCarryTheSameThreeKeys() {
        let empty = IntroAnswers().trackParams
        #expect(Set(empty.keys) == ["knows_kana", "textbook_lesson", "goal"])
        #expect(empty["knows_kana"] as? String == IntroAnswers.unanswered)
        #expect(empty["goal"] as? String == IntroAnswers.unanswered)
        #expect(empty["textbook_lesson"] as? Int == IntroAnswers.unansweredLesson)

        let full = IntroAnswers(kana: .hiragana, textbookLesson: 0, goal: .travel)
        #expect(Set(full.trackParams.keys) == Set(empty.keys))
        #expect(full.trackParams["knows_kana"] as? String == "hiragana")
        #expect(full.trackParams["textbook_lesson"] as? Int == 0)
        #expect(full.trackParams["goal"] as? String == "travel")

        #expect(full.isComplete)
        #expect(!IntroAnswers(kana: .hiragana, goal: .travel).isComplete)
    }

    /// Card 3's chips are the real mode rows: `SelectModeView`'s order, its titles, its
    /// subtitles, its SF Symbols. If any of those strings is renamed there, this fails
    /// here rather than silently falling back to the raw key on the intro card.
    @Test func modeChipsReuseSelectModeStrings() throws {
        #expect(Intro.Mode.allCases == [.vocabList, .flashcards, .train, .learn])
        #expect(Intro.Mode.allCases.map(\.titleKey)
                == ["Vocab List", "Flashcards", "Train", "Learn"])
        #expect(Intro.Mode.allCases.map(\.subtitleKey)
                == ["Browse & hear all words", "Swipe right if you know it",
                    "Swipe to the right answer", "Rebuild the reading from tiles"])
        #expect(Intro.Mode.allCases.map(\.icon)
                == ["list.bullet", "rectangle.on.rectangle.angled",
                    "arrow.left.arrow.right", "square.grid.2x2"])
        for mode in Intro.Mode.allCases {
            #expect(UIImage(systemName: mode.icon) != nil, "missing SF Symbol \(mode.icon)")
        }
    }

    /// Every string the intro asks for resolves to a real English entry. `L.t` falls back
    /// to the key itself, so a typo shows up as English-looking text that no translation
    /// pass will ever cover — invisible without this check.
    @Test func introStringsHaveEnglishEntries() throws {
        let url = try #require(Bundle.main.url(forResource: "UIStrings", withExtension: "json"))
        let table = try JSONDecoder().decode([String: [String: String]].self,
                                             from: Data(contentsOf: url))
        let en = try #require(table["en"])

        var keys = Intro.Mode.allCases.flatMap { [$0.titleKey, $0.subtitleKey] }
        keys += Intro.KanaLevel.allCases.map(\.titleKey)
        keys += Intro.Goal.allCases.map(\.titleKey)
        keys += ["Skip", "Start learning", "Next",
                 "Meanings in %@", "Tap any word to hear it.", "Change language",
                 "All of Kana is free.",
                 "The chart, the quizzes, and drawing a kana to have your strokes scored.",
                 "Do you read kana already?",
                 "Four ways through a lesson.", "Many ways to learn. All of them fun.",
                 "Challenge", "Challenge %@", "Best %@%", "Beat Challenge %@ to unlock",
                 "%@ questions a rung", "%@% to pass, up to three stars",
                 "Pass one and the next opens.",
                 "Studied Minna no Nihongo before?", "No, starting fresh",
                 "Yes — up to lesson %@", "Lesson %@", "Ready for Challenge %@?",
                 "Today deals exactly the words your next challenge will ask.",
                 "The same deck sits on your Lock Screen, Home Screen and Watch.",
                 "Why are you learning?"]
        for key in keys {
            #expect(en[key] != nil, "UIStrings.en is missing '\(key)'")
        }
    }

    @Test func goalsAreFiveWithStableRawValues() {
        #expect(Intro.Goal.allCases.map(\.rawValue)
                == ["travel", "jlpt", "work", "culture", "other"])
        for goal in Intro.Goal.allCases {
            #expect(UIImage(systemName: goal.icon) != nil, "missing SF Symbol \(goal.icon)")
        }
    }

    /// The intro records the textbook answer and nothing else: no lesson floor, no seeded
    /// ladder rows. Seeding would sync invented history to every device and inflate the
    /// count that gates the rating prompt, so this pins the *absence* of that behaviour.
    @MainActor @Test func textbookAnswerIsRecordedOnly() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        IntroAnswers(kana: .both, textbookLesson: 30, goal: .work).save(to: defaults)

        let container = try ModelContainer(
            for: ChallengeResult.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        #expect(try ctx.fetch(FetchDescriptor<ChallengeResult>()).isEmpty)
        #expect(ChallengeResult.totalPassed(context: ctx) == 0)
    }
}
