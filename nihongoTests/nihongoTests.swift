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
        #expect(VocabStore.allVocab().count == 2100)
        #expect(VocabStore.allVocab().filter { $0.audio != nil }.count == 2100)
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
        // The nudge is tied to something having visibly worked, not to opening the app.
        #expect(!SharePrompt.shouldAsk(passed: true, passedCount: 0, ratingShown: false))
        #expect(!SharePrompt.shouldAsk(passed: true, passedCount: enough - 1, ratingShown: false))

        // Lower bar than the rating: this asks for a recommendation, not a public verdict.
        #expect(SharePrompt.challengesRequired == 7)
        #expect(SharePrompt.challengesRequired < RatingPrompt.challengesRequired)
        // The windows are deliberately the *same* two months — the prompts are separated
        // by what they ask for and by the rating's precedence, not by cadence. What must
        // never converge is the storage: one key would let each silence the other.
        #expect(SharePrompt.askAgainAfter == RatingPrompt.askAgainAfter)
        #expect(Pref.shareAskedAt != Pref.ratingAskedAt)
    }

    /// The share text must carry *this* app's listing. Two apps, two listings, and a
    /// recommendation pointing at the other one would look like it worked.
    @Test func shareLinkPointsAtThisCoursesListing() {
        #expect(SharePrompt.appStoreURL().absoluteString == Course.current.appStoreURL)
        #expect(Course.minna.appStoreURL != Course.jlpt.appStoreURL)

        // Every share carries a campaign token, and every token still resolves to this
        // course's listing — a tagged link that pointed at the other app, or dropped the
        // path while adding the query, would look fine and send installs elsewhere.
        for campaign in [SharePrompt.Campaign.prompt, .settings] {
            let url = SharePrompt.appStoreURL(campaign: campaign)
            #expect(url.absoluteString.hasPrefix(Course.current.appStoreURL))
            #expect(SharePrompt.shareText(campaign: campaign).contains(url.absoluteString))

            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(items.first { $0.name == "ct" }?.value == campaign.rawValue)
            // Apple caps `ct` at 40 characters and silently truncates past it, which
            // would merge two campaigns into one row in App Analytics.
            #expect(campaign.rawValue.count <= 40)
            // `utm_*` is inert on apps.apple.com — if one ever appears here it means
            // someone reached for the Google convention and got no reporting at all.
            #expect(!items.contains { $0.name.hasPrefix("utm_") })
        }

        // Distinct tokens, or the whole exercise reports one undifferentiated number.
        #expect(SharePrompt.Campaign.prompt.rawValue != SharePrompt.Campaign.settings.rawValue)
    }

    /// The analytics profile carries what only the app knows, and nothing that could
    /// identify anyone.
    ///
    /// A predecessor of this app shipped fifteen user properties duplicating dimensions
    /// GA4 collects on its own (device model, OS, screen, locale, app version) plus a
    /// `user_id` and a `deviceId` both holding `identifierForVendor`. Both mistakes are
    /// worth a test: the duplicates spend from a hard cap of 25 properties, and the
    /// identifier is the thing this codebase exists not to send.
    @Test func analyticsProfileSegmentsWithoutIdentifying() {
        let p = Track.profile(uiLanguage: "zh-Hant", meaningLanguage: "vi",
                              knowsKana: "both", goal: "travel", earnedFirstGroup: true)

        #expect(p["ui_language"] == "zh-Hant")
        // The two language settings are independent by design; collapsing them into one
        // property would lose the configuration this app is unusual for supporting.
        #expect(p["meaning_language"] == "vi")
        #expect(p["knows_kana"] == "both")
        #expect(p["learning_goal"] == "travel")
        #expect(p["earned_first_group"] == "true")

        // A skipped intro answer is its own segment, not a missing key.
        let skipped = Track.profile(uiLanguage: "en", meaningLanguage: "en",
                                    knowsKana: nil, goal: nil, earnedFirstGroup: false)
        #expect(skipped["knows_kana"] == "unanswered")
        #expect(skipped["learning_goal"] == "unanswered")
        #expect(skipped["earned_first_group"] == "false")
        #expect(Set(p.keys) == Set(skipped.keys))     // same shape either way

        // GA4 caps a value at 36 characters and truncates silently past it.
        let long = Track.profile(uiLanguage: String(repeating: "x", count: 80),
                                 meaningLanguage: "en", knowsKana: nil, goal: nil,
                                 earnedFirstGroup: false)
        #expect(long["ui_language"]?.count == 36)
        #expect(p.values.allSatisfy { $0.count <= 36 })

        // Nothing here may name or resemble an identifier, and nothing may duplicate a
        // dimension GA4 already collects for free.
        let forbidden = ["user_id", "device_id", "deviceid", "instance_id", "instanceid",
                         "idfv", "idfa", "vendor_id", "install_id",
                         "device_model", "os_version", "app_version", "app_build",
                         "screen_width", "screen_height", "locale", "timezone", "country"]
        for name in p.keys {
            #expect(!forbidden.contains(name), "\(name) is an identifier or a GA4 duplicate")
            // lower_snake_case, per the house rule.
            #expect(name == name.lowercased())
            #expect(!name.contains(" "))
        }
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

    /// Every entry ships an example sentence, each sentence is distinct, and the
    /// English translation resolves — the wholesale-en fallback means every language
    /// then shows *something* under the sentence. Distinctness matters because the
    /// upstream data promises it: two words sharing a sentence reads as a copy bug.
    /// Furigana annotates the kanji core only — shared tails (です。) and shared
    /// prefixes are already visible on the main line, and repeating them reads as a
    /// typo rather than a reading.
    @Test func furiganaTrimsToTheKanjiCore() {
        let ex = ExampleSentence(kanji: ["わたしは", "学生です。"],
                                 kana:  ["わたしは", "がくせいです。"],
                                 romaji: ["watashiwa", "gakuseidesu"])
        #expect(ex.reading(at: 0) == nil)               // all kana — nothing to annotate
        #expect(ex.reading(at: 1) == "がくせい")          // です。 trimmed

        let mid = ExampleSentence(kanji: ["人は"], kana: ["ひとは"], romaji: ["hitowa"])
        #expect(mid.reading(at: 0) == "ひと")             // trailing particle trimmed

        let pre = ExampleSentence(kanji: ["お名前は"], kana: ["おなまえは"], romaji: ["onamaewa"])
        #expect(pre.reading(at: 0) == "なまえ")           // honorific prefix trimmed too

        #expect(ex.reading(at: 9) == nil)               // out of range degrades, never traps
    }

    @Test func everyEntryCarriesADistinctExample() {
        let all = VocabStore.allVocab()
        let examples = all.compactMap(\.example)
        #expect(examples.count == all.count)

        // The flag the example *controls* are gated on — Read along's "+ Example" rung
        // and the Vocab List examples switch. Inverted or misread it either hides a
        // working feature from every Minna learner or restores a dead button to JLPT,
        // and neither shows up as a crash. This suite runs against Minna, whose answer
        // is true; the JLPT half is pinned by the count above being the whole corpus.
        #expect(VocabStore.hasExamples)
        #expect(all.allSatisfy { !($0.exampleTranslation ?? "").isEmpty })

        // The three arrays are index-aligned by contract — the UI zips them into
        // columns, so a length mismatch is a rendering bug waiting at some row i.
        #expect(examples.allSatisfy {
            !$0.kanji.isEmpty && $0.kanji.count == $0.kana.count && $0.kana.count == $0.romaji.count
        })

        // Distinct sentences, as upstream promises — two words sharing one reads as
        // a copy bug. Joined kanji is the sentence's identity.
        let sentences = examples.map { $0.kanji.joined() }
        #expect(Set(sentences).count == sentences.count)
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

    /// Both recorded voices are bundled, and the suffix `Speech.Voice` appends is exactly
    /// the one `build-minna-data.py` wrote.
    ///
    /// The two are coupled by a bare string and nothing else enforces it, so a rename on
    /// either side would fail silently: `audioURL` falls back to the default clip, every
    /// question would sound identical, and the ladder would quietly stop being a listening
    /// test — with no crash and no missing file to notice.
    @Test func bothVoicesAreBundledAndTheSuffixMatchesTheBuildScript() {
        #expect(Speech.Voice.default.suffix == "")
        #expect(Speech.Voice.alternate.suffix == "-kenzaki")

        let word = try! #require(VocabStore.lesson(1).entries.first { $0.audio != nil })
        let primary = VocabStore.audioURL(for: word, voice: .default)
        let alternate = VocabStore.audioURL(for: word, voice: .alternate)
        #expect(primary != nil)
        #expect(alternate != nil)
        // Distinct files, not the fallback quietly serving the same clip twice.
        #expect(primary != alternate)
        #expect(alternate?.lastPathComponent.contains("-kenzaki") == true)
    }

    /// A challenge run mixes both voices rather than settling on one.
    ///
    /// Ten rungs of ten questions is 100 draws; both voices appearing at least once is
    /// certain enough to assert (the chance of a uniform run is 2^-99). What this really
    /// guards is the *wiring* — a `voice` left at its default everywhere would pass every
    /// other test in the suite.
    @Test func challengeQuestionsUseBothVoices() {
        var seen = Set<String>()
        for index in 1...10 {
            let lesson = VocabStore.lesson(1)
            let model = ChallengeModel(lessonNumber: 1, index: index, total: 10,
                                       words: lesson.entries)
            for q in model.questions { seen.insert(q.voice.suffix) }
        }
        #expect(seen.count == 2, "a run should mix voices, saw \(seen)")
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

    /// Every word with an example ships its recording, under the `ex-` name the flat
    /// bundle requires — and that name must not collide with the word's own clip.
    @Test func exampleSentenceClipsAreBundledAndDistinct() {
        var checked = 0
        for lesson in VocabStore.lessons() {
            for word in lesson.entries where word.example != nil {
                let url = VocabStore.exampleAudioURL(for: word)
                #expect(url != nil, "no example clip for \(word.id)")
                // The sentence and the word are different files. Without the `ex-`
                // prefix they would both be `<lesson>-<slug>.m4a` at the bundle root,
                // and one would silently answer for the other.
                if let url, let wordURL = VocabStore.audioURL(for: word) {
                    #expect(url != wordURL, "\(word.id): sentence and word are one file")
                }
                checked += 1
            }
        }
        #expect(checked > 2000, "only \(checked) words carried an example")
    }

    @Test func strokeOrderFontIsBundled() {
        #expect(UIFont(name: "KanjiStrokeOrders", size: 20) != nil)
    }

    /// The Japanese faces must actually *resolve* on the device, and cover Latin.
    ///
    /// `Font.custom` fails silently: a name iOS doesn't ship falls back to the system
    /// face and nothing looks broken, which is exactly how the watch target spent its
    /// life naming a Maru Gothic that watchOS has never shipped. Latin coverage is the
    /// second half — `CLAUDE.md`'s rule that romaji set in a Japanese face reads plain
    /// rather than as tofu only holds while these faces carry the glyphs.
    @Test func japaneseFacesResolveAndCoverLatin() throws {
        for name in ["HiraMinProN-W3", "HiraMinProN-W6"] {
            let font = try #require(UIFont(name: name, size: 20),
                                    "iOS does not ship '\(name)' — Theme would fall back silently")
            let coverage = try #require(CTFontCopyCharacterSet(font) as CharacterSet?)
            for scalar in "AZaz09.,%\u{2605}".unicodeScalars {
                #expect(coverage.contains(scalar), "\(name) cannot draw '\(scalar)'")
            }
            for scalar in "\u{3042}\u{30A2}\u{6F22}".unicodeScalars {   // あ ア 漢
                #expect(coverage.contains(scalar), "\(name) cannot draw '\(scalar)'")
            }
        }
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

// MARK: - Practice / kana quiz models

@MainActor
struct PracticeTests {
    /// Where a word sits in the queue now, and which face it will show — the re-queue
    /// distance is drawn per word, so tests assert a window rather than an index.
    private static func requeued(_ model: PracticeModel, _ id: String) -> Int? {
        model.queue.firstIndex { $0.vocab.id == id }
    }

    /// The drawn distance, clamped the way `advance` clamps it against a short queue.
    private static func inWindow(_ offset: Int, queueCount: Int) -> Bool {
        let lowest = min(PracticeModel.requeueWindow.lowerBound, queueCount)
        let highest = min(PracticeModel.requeueWindow.upperBound, queueCount)
        return offset >= lowest && offset <= highest
    }

    /// A throwaway store in a temp directory, so tests never touch the real one.
    private static func freshProgress() -> PracticeProgress {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("practice-tests-\(UUID().uuidString)")
        return PracticeProgress(directory: dir)
    }

    @Test func stagesPersistAcrossReload() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("practice-tests-\(UUID().uuidString)")
        let store = PracticeProgress(directory: dir)
        store.set(.recognized, for: "1/watashi")
        store.set(.memorized, for: "1/anata")
        store.saveNow()

        let reloaded = PracticeProgress(directory: dir)
        #expect(reloaded.stage(of: "1/watashi") == .recognized)
        #expect(reloaded.stage(of: "1/anata") == .memorized)
        // Absent is the common case forever — it must read as unseen, not crash.
        #expect(reloaded.stage(of: "1/never-practiced") == .unseen)
    }

    @Test func unseenRemovesTheRowAndAlienStagesClamp() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("practice-tests-\(UUID().uuidString)")
        let store = PracticeProgress(directory: dir)
        store.set(.seen, for: "1/word")
        store.set(.unseen, for: "1/word")
        #expect(store.stages["1/word"] == nil)   // removed, not stored as zero

        // A newer build's stage 7 degrades to the top of the ladder this build knows;
        // junk below zero clamps up. Best-effort, never a wipe.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("PracticeProgress.json")
        try Data(#"{"v":9,"words":{"1/a":7,"1/b":-2,"1/c":2}}"#.utf8).write(to: file)
        let reloaded = PracticeProgress(directory: dir)
        #expect(reloaded.stage(of: "1/a") == .memorized)
        #expect(reloaded.stage(of: "1/b") == .unseen)
        #expect(reloaded.stage(of: "1/c") == .recognized)
    }

    @Test func countsFoldSeenIntoUnseen() {
        let store = Self.freshProgress()
        let entries = VocabStore.lesson(1).entries
        store.set(.memorized, for: entries[0].id)
        store.set(.recognized, for: entries[1].id)
        store.set(.seen, for: entries[2].id)     // display folds this into unseen

        let counts = store.counts(for: entries)
        #expect(counts.memorized == 1)
        #expect(counts.recognized == 1)
        #expect(counts.unseen == entries.count - 2)
    }

    /// **Every card is the same card.** A word the learner has never met is asked like
    /// any other — being asked is how the mode finds out what they know, and what they
    /// didn't know is taught in the reveal that follows a miss. There is no separate
    /// teaching card to tap past first, and so no `face` to get wrong.
    @Test func everyWordIsDealtAsAQuestion() {
        let vocab = VocabStore.lesson(7).entries
        let model = PracticeModel(vocab: vocab, progress: Self.freshProgress())
        #expect(model.sessionTotal == vocab.count)
        #expect(Set(model.queue.map(\.vocab.id)) == Set(vocab.map(\.id)))
        // Two options are dealt from the first card, with nothing tapped through first.
        #expect(model.options.count == PracticeModel.optionCount)
        #expect(model.options.contains { $0.id == model.current?.vocab.id })
    }

    /// Looking at the back of the card costs the round.
    ///
    /// A long press flips the card to its meaning, and a right answer given after
    /// reading the answer is not evidence of knowing the word — so it moves nothing up
    /// the ladder and the word simply comes back. A *wrong* answer still demotes,
    /// peeked or not: missing it with the meaning in front of you is if anything the
    /// clearer signal.
    @Test func peekingCostsTheRoundButNotThePunishment() throws {
        let vocab = VocabStore.lesson(1).entries
        let progress = Self.freshProgress()
        for w in vocab { progress.set(.seen, for: w.id) }
        let model = PracticeModel(vocab: vocab, progress: progress)

        // Right answer, but peeked: stage unchanged, nothing retired, word re-queued.
        let word = try #require(model.current).vocab
        let right = try #require(model.options.firstIndex { $0.id == word.id })
        model.choose(right)
        model.resolve(credited: false)
        #expect(progress.stage(of: word.id) == .seen)
        #expect(model.retired == 0)
        #expect(Self.requeued(model, word.id) != nil)

        // The same answer, credited, does promote — so the clamp above is the peek and
        // not something else swallowing the result.
        let second = try #require(model.current).vocab
        let alsoRight = try #require(model.options.firstIndex { $0.id == second.id })
        model.choose(alsoRight)
        model.resolve()
        #expect(progress.stage(of: second.id) == .recognized)

        // Wrong after a peek still demotes.
        let third = try #require(model.current).vocab
        progress.set(.recognized, for: third.id)
        let wrong = try #require(model.options.firstIndex { $0.id != third.id })
        model.choose(wrong)
        model.resolve(credited: false)
        #expect(progress.stage(of: third.id) == .seen)
    }

    /// **Two correct answers, not one.** With two options a coin flip is right half the
    /// time, so a single hit promotes one rung (`.seen` → `.recognized`) and only the
    /// second reaches `.memorized` and retires the word. A wrong answer drops it to
    /// `.seen` and brings the card back to re-teach it.
    @Test func quizAnswersMoveTheLadderBothWays() throws {
        let vocab = VocabStore.lesson(1).entries
        let progress = Self.freshProgress()
        // Every word *met* — so the session is all quizzes and every one of them is on
        // its first rung, which is what makes the two-step promotion observable.
        for w in vocab { progress.set(.seen, for: w.id) }
        let model = PracticeModel(vocab: vocab, progress: progress)

        // First correct answer: one rung up, still in the queue as a quiz.
        let word = model.current!.vocab
        let right = model.options.firstIndex { $0.id == word.id }!
        model.choose(right)
        model.resolve()
        #expect(progress.stage(of: word.id) == .recognized)
        #expect(model.retired == 0)
        #expect(model.queue.count == vocab.count)
        // Requeued far back — a proven word needs confirming, not another look.
        let promoted = try #require(Self.requeued(model, word.id))
        #expect(promoted >= min(PracticeModel.provenWindow.lowerBound, model.queue.count))

        // Answer it right again and it retires.
        while let item = model.current, item.vocab.id != word.id {
            let i = model.options.firstIndex { $0.id == item.vocab.id } ?? 0
            model.choose(i)
            model.resolve()
        }
        let again = model.options.firstIndex { $0.id == word.id }!
        model.choose(again)
        model.resolve()
        #expect(progress.stage(of: word.id) == .memorized)
        #expect(model.retired >= 1)

        // Wrong: the other chip. Demoted to seen, card face re-queued.
        let retiredBefore = model.retired
        let second = model.current!.vocab
        let wrong = model.options.firstIndex { $0.id != second.id }!
        model.choose(wrong)
        model.resolve()
        #expect(progress.stage(of: second.id) == .seen)
        #expect(model.retired == retiredBefore)
        let requeued = try #require(Self.requeued(model, second.id))
        #expect(Self.inWindow(requeued, queueCount: model.queue.count))
    }

    /// Restart rebuilds from the stages: memorized words sit the session out, and a
    /// fully-memorized lesson re-enters whole as quiz review rather than as nothing.
    @Test func restartBuildsFromStagesAndFullMasteryMeansReview() {
        let vocab = VocabStore.lesson(1).entries
        let progress = Self.freshProgress()
        progress.set(.memorized, for: vocab[0].id)
        let model = PracticeModel(vocab: vocab, progress: progress)
        #expect(model.sessionTotal == vocab.count - 1)
        #expect(!model.queue.contains { $0.vocab.id == vocab[0].id })

        for w in vocab { progress.set(.memorized, for: w.id) }
        model.restart()
        #expect(model.sessionTotal == vocab.count)
    }

    /// The distractor rule holds under every quiz pair, not just kana → meaning:
    /// matching the answer side is a second right answer, matching the prompt side
    /// is an unanswerable question.
    @Test func optionsAreDistinctOnBothFacesUnderEveryPair() {
        let pool = VocabStore.lesson(5).entries
        for from in PracticeModel.quizFaces {
            for to in PracticeModel.quizFaces where to != from {
                for answer in pool.prefix(20) {
                    let opts = PracticeModel.options(for: answer, pool: pool,
                                                     from: from, to: to)
                    #expect(opts.count == 2)
                    #expect(opts.contains { $0.id == answer.id })
                    #expect(Set(opts.map { to.value($0) }).count == opts.count)
                    #expect(Set(opts.map { from.value($0) }).count == opts.count)
                }
            }
        }
    }

    /// Words with no kanji to show skip the kanji *question*, not the word: the
    /// kanji slot moves off kanji, and when that collapses the pair the **degraded**
    /// side moves again — so the side the learner explicitly chose survives.
    @Test func kanjiLessWordsDegradeTheKanjiSlot() {
        let vocab = VocabStore.lesson(1).entries
        guard let plain = vocab.first(where: { !$0.displaysKanji }) else { return }
        let progress = Self.freshProgress()
        let model = PracticeModel(vocab: vocab, progress: progress)

        model.setPair(from: .kanji, to: .translation, mixed: false)
        #expect(model.pair(for: plain) == (.kana, .translation))

        // Prompt-side kanji collapses onto the chosen kana answer, so the *prompt*
        // becomes the meaning: answering in kana is what the learner asked for.
        model.setPair(from: .kanji, to: .kana, mixed: false)
        #expect(model.pair(for: plain) == (.translation, .kana))

        if let written = vocab.first(where: { $0.displaysKanji }) {
            model.setPair(from: .kanji, to: .translation, mixed: false)
            #expect(model.pair(for: written) == (.kanji, .translation))
        }
    }

    /// A session must keep reaching **new words**, not circle the handful it has
    /// already asked.
    ///
    /// Two regressions live here. A fixed re-queue distance preserved order, so the deck
    /// used to play in blocks. Then two-step promotion re-tested proven words near the
    /// front, which crowded the unasked ones out — 16 cards could pass with nothing new
    /// reached. `provenWindow` is what fixed the second: a word's *first* correct answer
    /// sends it far back, because it needs confirming rather than another look.
    @Test func theQueueKeepsReachingWordsItHasNotAskedYet() {
        let vocab = VocabStore.lesson(1).entries
        let model = PracticeModel(vocab: vocab, progress: Self.freshProgress())

        // Answer everything correctly — the path that starved the queue.
        var asked: [String] = []
        var longestRepeatGap = 0, sinceNew = 0
        var seen = Set<String>()
        for _ in 0..<36 {
            guard let item = model.current else { break }
            asked.append(item.vocab.id)
            if seen.insert(item.vocab.id).inserted { sinceNew = 0 } else { sinceNew += 1 }
            longestRepeatGap = max(longestRepeatGap, sinceNew)
            let right = model.options.firstIndex { $0.id == item.vocab.id } ?? 0
            model.choose(right)
            model.resolve()
        }

        // Over 36 cards a 46-word lesson should have met a good share of its words, and
        // never spent a long stretch only re-asking ones already seen.
        #expect(seen.count >= 18, "only \(seen.count) distinct words in 36 cards")
        #expect(longestRepeatGap <= 10,
                "\(longestRepeatGap) cards passed without reaching a new word")
    }

    /// Mixed must be *mixed*, including on a lesson where hardly anything has kanji.
    ///
    /// The first implementation drew one of the six combinations and then rewrote a
    /// kanji slot the word couldn't fill into kana — which funnels four of the six onto
    /// kana→meaning, so a katakana-heavy lesson asked the easiest direction two-thirds
    /// of the time. Reported from a real screen. The fix enumerates what a word supports
    /// and draws from that, so a kana-only word splits evenly between its two.
    @Test func mixedDrawsEvenlyFromWhatEachWordSupports() {
        let vocab = VocabStore.lesson(1).entries
        let model = PracticeModel(vocab: vocab, progress: Self.freshProgress())
        model.setPair(from: .kana, to: .translation, mixed: true)

        if let plain = vocab.first(where: { !$0.displaysKanji }) {
            var seen: [String: Int] = [:]
            for _ in 0..<400 {
                let (f, t) = model.pair(for: plain)
                #expect(f != .kanji && t != .kanji)   // never asks a face it can't draw
                #expect(f != t)
                seen["\(f.label)>\(t.label)", default: 0] += 1
            }
            // Both supported directions, and neither runs away with it: an even split
            // is 200/200, so 100 is a floor no fair draw realistically breaches.
            #expect(seen.count == 2)
            #expect(seen.values.allSatisfy { $0 > 100 })
        }

        if let written = vocab.first(where: { $0.displaysKanji }) {
            var seen = Set<String>()
            for _ in 0..<400 {
                let (f, t) = model.pair(for: written)
                #expect(f != t)
                seen.insert("\(f.label)>\(t.label)")
            }
            // All six ordered pairs of the three faces stay reachable.
            #expect(seen.count == 6)
        }
    }

    /// The faces a word can be asked in — the set everything above draws from.
    @Test func availableFacesFollowTheWord() {
        let vocab = VocabStore.lesson(1).entries
        if let plain = vocab.first(where: { !$0.displaysKanji }) {
            #expect(PracticeModel.faces(for: plain) == [.kana, .translation])
        }
        if let written = vocab.first(where: { $0.displaysKanji }) {
            #expect(PracticeModel.faces(for: written) == [.kana, .kanji, .translation])
        }
    }

    /// The pair only ever takes the three faces, and never prompt == answer — the
    /// sheet's greying rule, enforced in the model where it can't be bypassed.
    @Test func setPairRefusesInvalidCombinations() {
        let model = PracticeModel(vocab: VocabStore.lesson(1).entries,
                                  progress: Self.freshProgress())
        model.setPair(from: .kana, to: .translation, mixed: false)
        model.setPair(from: .kana, to: .kana, mixed: false)      // same face: refused
        #expect(model.from == .kana && model.to == .translation)
        model.setPair(from: .audio, to: .kana, mixed: false)     // not a quiz face: refused
        #expect(model.from == .kana && model.to == .translation)
    }

    @Test func emptyVocabDegradesInsteadOfCrashing() {
        let model = PracticeModel(vocab: [], progress: Self.freshProgress())
        #expect(model.isDone)
        #expect(model.options.isEmpty)
        model.choose(0)    // no crash on an empty queue
        model.resolve()
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
        #expect(VForm.promptAudioSafe(from: .kana))
        #expect(VForm.promptAudioSafe(from: .kanji))
        #expect(VForm.promptAudioSafe(from: .romaji))
        #expect(VForm.promptAudioSafe(from: .audio))
        #expect(!VForm.promptAudioSafe(from: .translation))
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

    /// The exact strings App Store Connect holds for JLPT — pinned because they look
    /// like mistakes and are not, and because a "correction" is unfixable.
    ///
    /// Product IDs are immutable and reserved per *team* forever. `premium.lifetime` was
    /// created for this app and deleted during setup, so Apple has retired the word here
    /// permanently — hence `forever`. The lowercase `3m`/`6m` are simply the clean choice:
    /// minna's uppercase `3M`/`6M` are a workaround for IDs its RN predecessor burned, and
    /// JLPT has no such history to inherit.
    ///
    /// Get any of these wrong and `Product.products(for:)` silently returns fewer plans —
    /// the paywall renders what it got and nothing reports an error.
    @Test func jlptProductIDsMatchAppStoreConnect() {
        let p = Course.jlpt.products
        #expect(p.lifetime == "com.kfpun.jlptjp.premium.forever")
        #expect(p.subscriptions == [
            "com.kfpun.jlptjp.premium.1m",
            "com.kfpun.jlptjp.premium.3m",
            "com.kfpun.jlptjp.premium.6m",
        ])
        // The burned ID must never reappear: it cannot be created, so shipping it would
        // mean the lifetime row simply never loads.
        #expect(p.lifetime != "com.kfpun.jlptjp.premium.lifetime")
        #expect(!p.subscriptions.contains { $0.hasSuffix("M") })
        // Nothing sold yet, so nothing to honour on restore.
        #expect(p.legacy.isEmpty)

        // The two courses must not share a product: one purchase would unlock both apps.
        let minna = Set([Course.minna.products.lifetime] + Course.minna.products.subscriptions
                        + Course.minna.products.legacy)
        let jlpt = Set([p.lifetime] + p.subscriptions + p.legacy)
        #expect(minna.isDisjoint(with: jlpt))
    }

    /// Minna's list, pinned like JLPT's above and for the same reason: a wrong ID means
    /// `Product.products(for:)` silently returns fewer plans and the paywall renders
    /// what it got. The 12-month is the uppercase `12M` created 2026-08 — the lowercase
    /// `12m` is the RN app's burned ID and must stay in `legacy`, never here.
    @Test func minnaProductIDsMatchAppStoreConnect() {
        let p = Course.minna.products
        #expect(p.lifetime == "com.kfpun.nihongo.premium.lifetime")
        #expect(p.subscriptions == [
            "com.kfpun.nihongo.premium.1m",
            "com.kfpun.nihongo.premium.3M",
            "com.kfpun.nihongo.premium.6M",
            "com.kfpun.nihongo.premium.12M",
        ])
        #expect(p.legacy.contains("com.kfpun.nihongo.premium.12m"))
        #expect(!p.subscriptions.contains("com.kfpun.nihongo.premium.12m"))
    }

    /// `premium_tier` reports one of five plan labels, and nothing else.
    ///
    /// The label names the plan, not the SKU: the burned 2019 IDs differ from the current
    /// lineup only in case, and folding each onto its current twin is deliberate. What
    /// this pins is that the *set* stays closed — a new product whose ID ends in anything
    /// unexpected would quietly introduce a sixth label that no dashboard is grouped by.
    /// Read along's speed dial is premium — and the *feature* is not.
    ///
    /// A free listener still hears the whole lesson; what they don't get is the dial.
    /// The failure mode this pins is the lapsed subscriber: 1.2× stays in
    /// `Pref.playbackRate` after a subscription ends, and reading it straight back would
    /// keep handing out a paid benefit forever. `Gating.rate` clamps instead — the
    /// preference is remembered, not honoured, so resubscribing restores it exactly.
    /// The meanings mode is premium **on every lesson**, free ones included.
    ///
    /// It used to key off the lesson lock, so it played in full on lessons 1–5 and
    /// previewed everywhere else: the same paid feature behaving two ways depending on
    /// where it was opened, and invisible as paid to anyone who stayed in the free
    /// lessons. Japanese-only is the half that stays free everywhere.
    @Test func readingMeaningsAloudIsPremiumOnEveryLesson() {
        let lessonSizes = [8, 16, 46]
        for count in lessonSizes {
            // Free listener: preview only, whichever lesson this is.
            #expect(Gating.wordsToRead(mode: .withMeaning, count: count, isPremium: false)
                    == min(Gating.freeMeaningPreview, count))
            #expect(!Gating.loopsForever(mode: .withMeaning, isPremium: false))
            // Subscriber: the whole lesson, looping.
            #expect(Gating.wordsToRead(mode: .withMeaning, count: count, isPremium: true) == count)
            #expect(Gating.loopsForever(mode: .withMeaning, isPremium: true))
            // Japanese-only always reads the *whole* lesson — what a free listener
            // doesn't get is the repeat.
            for premium in [true, false] {
                #expect(Gating.wordsToRead(mode: .japanese, count: count, isPremium: premium) == count)
            }
            #expect(!Gating.loopsForever(mode: .japanese, isPremium: false))
            #expect(Gating.loopsForever(mode: .japanese, isPremium: true))
        }
    }

    @Test func playbackSpeedIsPremiumButNormalSpeedIsNot() {
        for stored in [0.8, 1.0, 1.2, 1.5] {
            #expect(Gating.rate(stored, isPremium: true) == stored)
            #expect(Gating.rate(stored, isPremium: false) == Gating.normalRate)
        }
        // Normal speed is what a free listener gets, and it is a real speed — not a
        // silence, and not a slower one.
        #expect(Gating.normalRate == 1.0)
    }

    @Test func premiumTierUsesTheFivePlanLabels() {
        let p = Course.minna.products
        let expected: Set<String> = ["1m", "3m", "6m", "12m", "lifetime"]

        #expect(Store.tierLabel(p.lifetime) == "lifetime")
        // Case-folded onto one bucket on purpose — a legacy 12-month subscriber and a new
        // one are the same plan to every question this label answers.
        #expect(Store.tierLabel("com.kfpun.nihongo.premium.12M") == "12m")
        #expect(Store.tierLabel("com.kfpun.nihongo.premium.12m") == "12m")

        // `Course.current` only: `tierLabel` compares against the *running* course's
        // lifetime ID, so JLPT's `premium.forever` only reads as "lifetime" in a JLPT
        // build. Checking the other course's IDs here would assert against a mapping
        // that never happens.
        let labels = Set(PremiumProduct.all.map(Store.tierLabel))
        #expect(labels.isSubset(of: expected), "unexpected tier label in \(labels)")
        #expect(labels.allSatisfy { $0 == $0.lowercased() })

        // Simultaneous entitlements resolve to one stable answer. `currentEntitlements`
        // promises no order, so this used to depend on which arrived last.
        #expect(Store.tier(from: []) == "none")
        let both = [p.subscriptions[0], p.lifetime]
        #expect(Store.tier(from: both) == "lifetime")
        #expect(Store.tier(from: both.reversed()) == "lifetime")
        let subs = Array(p.subscriptions.prefix(2))
        #expect(Store.tier(from: subs) == Store.tier(from: subs.reversed()))
    }

    /// Mastering the free lessons opens the course's first band without paying.
    ///
    /// Three stars, not a pass: `Challenge.stars` awards three only for a clean 100%, so
    /// the bar is real. A pass would be no bar at all — the ladder already requires one
    /// to advance, so everyone who finished the free lessons would qualify by default.
    @Test func masteringTheFreeLessonsEarnsTheFirstBand() {
        let free = Gating.freeLessonLimit
        #expect(free == 5)

        // Every free lesson swept.
        let rungs = Dictionary(uniqueKeysWithValues: (1...free).map { ($0, 4) })
        #expect(Gating.hasEarnedFirstGroup(rungs: rungs, threeStarred: rungs))

        // One rung short anywhere is not earned — the sweep has to be complete.
        for lesson in 1...free {
            var partial = rungs
            partial[lesson] = 3
            #expect(!Gating.hasEarnedFirstGroup(rungs: rungs, threeStarred: partial),
                    "lesson \(lesson) one rung short should not earn the band")
        }

        // A lesson whose rung count is unknown has not been *proven* mastered. Absence of
        // measurement must not read as success, or a data hiccup would hand out the band.
        var gap = rungs; gap[3] = nil
        #expect(!Gating.hasEarnedFirstGroup(rungs: gap, threeStarred: rungs))
        var zero = rungs; zero[3] = 0
        #expect(!Gating.hasEarnedFirstGroup(rungs: zero, threeStarred: zero))
    }

    /// What the reward actually opens, and that it can only ever add.
    @Test func earningTheBandExtendsTheFreeRangeAndNeverShrinksIt() {
        let free = Gating.freeLessonLimit
        let band = Gating.earnableGroup
        #expect(band != nil)
        // Always the *first* band, or the reward would open nothing new.
        #expect(band?.first == 1)
        #expect(band!.last > free, "the band must reach past the free lessons to be a reward")

        #expect(Gating.freeThrough(earnedFirstGroup: false) == free)
        #expect(Gating.freeThrough(earnedFirstGroup: true) == band!.last)

        // The gate itself: a lesson inside the band is locked before, open after.
        let inside = band!.last
        #expect(Gating.isLocked(lesson: inside, isPremium: false, earnedFirstGroup: false))
        #expect(!Gating.isLocked(lesson: inside, isPremium: false, earnedFirstGroup: true))
        // Beyond the band still needs premium — the reward is one band, not the course.
        #expect(Gating.isLocked(lesson: band!.last + 1, isPremium: false, earnedFirstGroup: true))
        // Premium is unaffected either way.
        #expect(!Gating.isLocked(lesson: band!.last + 1, isPremium: true, earnedFirstGroup: true))

        // Defaulting to unearned makes an un-plumbed caller fail *closed*: a lock a tap
        // can clear, never a lesson handed out unearned.
        #expect(Gating.isLocked(lesson: inside, isPremium: false))
    }

    @Test func gatingRules() {
        // Lessons 1…5 free in full, 6…50 premium — *before* anything is earned. Two
        // documented exceptions: the meaning preview below, and the first band, which
        // three-starring these five opens outright.
        let free = Gating.freeLessonLimit
        #expect(free == 5)
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

    /// Reading the Japanese aloud is free on every lesson — locked or not, premium or not.
    /// Only the meanings are paid, and only the meanings get cut short.
    ///
    /// Pinned because the lock lives on a *lesson* everywhere else in the app, so the
    /// obvious implementation is to check `isLocked` and truncate. That would take away a
    /// feature that has always been free and that nobody asked to charge for.
    @Test func plainReadAllIsFreeEvenOnALockedLesson() {
        for count in [17, 30, 63] {
            #expect(Gating.wordsToRead(mode: .japanese, count: count, isPremium: false) == count)
            #expect(Gating.wordsToRead(mode: .japanese, count: count, isPremium: true) == count)
            // The meanings mode is only cut short when the lesson is actually locked.
            #expect(Gating.wordsToRead(mode: .withMeaning, count: count, isPremium: true) == count)
            #expect(Gating.wordsToRead(mode: .withMeaning, count: count, isPremium: false)
                    == Gating.freeMeaningPreview)
        }
    }

    /// The preview has to stop *short* of the lesson, or it isn't one: it would read every
    /// word and then demand payment for what the listener had already heard in full — the
    /// worst version of this feature, and indistinguishable from a bug in the logs.
    @Test func previewStopsShortOfEveryLesson() {
        let smallest = VocabStore.lessons().map(\.entries.count).min() ?? 0
        #expect(smallest > 0)
        #expect(Gating.freeMeaningPreview < smallest,
                "preview of \(Gating.freeMeaningPreview) does not stop short of a \(smallest)-word lesson")
        // And it must leave something behind to buy — a one-word remainder is not an offer.
        #expect(smallest - Gating.freeMeaningPreview >= 5)
    }

    /// The locked meanings preview is the one thing that must never loop. Its paywall
    /// hangs off playback *ending*, so a looping preview would both skip the ask and read
    /// the paid mode aloud forever — the premium feature, free, on a locked lesson.
    ///
    /// Plain "Play all" loops on every lesson, locked or not, because it was always free.
    @Test func lockedMeaningPreviewNeverLoops() {
        // Looping is premium in *every* mode — a free listener hears the lesson once.
        #expect(!Gating.loopsForever(mode: .withMeaning, isPremium: false))
        #expect(Gating.loopsForever(mode: .withMeaning, isPremium: true))
        #expect(!Gating.loopsForever(mode: .japanese, isPremium: false))
        #expect(Gating.loopsForever(mode: .japanese, isPremium: true))
        #expect(!Gating.loopsForever(mode: .withExample, isPremium: false))
        #expect(Gating.loopsForever(mode: .withExample, isPremium: true))
        // The rule is the same one that truncates the list: whatever is cut short must be
        // exactly what is denied a loop, or one of the two is a way round the other.
        for count in [3, 7, 17, 63] {
            let cut = Gating.wordsToRead(mode: .withMeaning, count: count, isPremium: false) < count
            #expect(cut || !Gating.loopsForever(mode: .withMeaning, isPremium: false))
        }
    }
}

// MARK: - Lesson playback sequencing

/// The wrap in `LessonPlayer`. Only the pure step function is reachable without audio and
/// a screen, which is why it exists — the rest is delegate callbacks.
struct LessonPlayerTests {



    /// Every mode that reads past the word is premium — the gate is on *that*, so a
    /// fourth mode reading something else is paid without `Gating` being edited.
    @Test func everyModeBeyondTheWordIsPremium() {
        #expect(!ReadMode.japanese.readsBeyondTheWord)
        #expect(ReadMode.withMeaning.readsBeyondTheWord)
        #expect(ReadMode.withExample.readsBeyondTheWord)
        for mode in [ReadMode.withMeaning, .withExample] {
            #expect(Gating.wordsToRead(mode: mode, count: 46, isPremium: false)
                    == Gating.freeMeaningPreview)
            #expect(Gating.wordsToRead(mode: mode, count: 46, isPremium: true) == 46)
            #expect(!Gating.loopsForever(mode: mode, isPremium: false))
        }
    }

    /// Mid-list, looping changes nothing: the next word is the next word.
    @Test func advancesThroughTheListRegardlessOfLooping() {
        for loops in [true, false] {
            #expect(LessonPlayer.step(after: 0, count: 5, loops: loops) == .next(1))
            #expect(LessonPlayer.step(after: 3, count: 5, loops: loops) == .next(4))
        }
    }

    /// The last word wraps when looping and ends when not. This is the whole feature.
    @Test func lastWordWrapsOnlyWhenLooping() {
        #expect(LessonPlayer.step(after: 4, count: 5, loops: true) == .wrap)
        #expect(LessonPlayer.step(after: 4, count: 5, loops: false) == .end)
        // A one-word list is still a lap: it wraps onto itself rather than stopping.
        #expect(LessonPlayer.step(after: 0, count: 1, loops: true) == .wrap)
        #expect(LessonPlayer.step(after: 0, count: 1, loops: false) == .end)
    }

    /// An empty list ends even when looping — a wrap with nothing to play is a silent
    /// spin the user cannot tell apart from a hang.
    @Test func emptyListNeverWraps() {
        #expect(LessonPlayer.step(after: 0, count: 0, loops: true) == .end)
        #expect(LessonPlayer.step(after: 0, count: 0, loops: false) == .end)
    }

    /// Laps run forever: every wrap lands back on word 0 and the next pass behaves like
    /// the first, so nothing accumulates that could stop playback after a few rounds.
    @Test func loopingRepeatsIndefinitely() {
        let count = 4
        var i = 0
        var laps = 0
        for _ in 0..<(count * 10) {
            switch LessonPlayer.step(after: i, count: count, loops: true) {
            case .next(let n): i = n
            case .wrap:        i = 0; laps += 1
            case .end:         Issue.record("looping playback reached an end at \(i)")
            }
        }
        #expect(laps == 10)
        #expect(i == 0)
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

// MARK: - Streak reminder (local notifications)

struct StreakReminderTests {
    /// A fixed 10am on 2026-08-11, so "has the fire time passed" is a decision the test
    /// makes rather than one the clock makes.
    private func morning() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 11; c.hour = 10
        return StudyDay.calendar.date(from: c)!
    }

    /// The whole point of the feature: it must never nag someone who is already done.
    /// A reminder that fires after you've studied is the one that gets notifications
    /// turned off permanently, and iOS only ever asks for permission once.
    @Test func todayIsSkippedOnceItHasBeenStudied() {
        let now = morning()
        let today = StudyDay.stamp(now)

        let open = StreakReminder.plan(now: now, studiedToday: false, hour: 20, horizon: 3)
        #expect(open.first == today)
        #expect(open.count == 4)                      // today + 3 ahead

        let done = StreakReminder.plan(now: now, studiedToday: true, hour: 20, horizon: 3)
        #expect(!done.contains(today))
        #expect(done.count == 3)                      // tomorrow onward only
        // Skipping today must not shorten the horizon — a studied day still gets the
        // same week of cover ahead of it.
        #expect(done == Array(open.dropFirst()))
    }

    /// iOS silently drops a calendar trigger whose components are in the past, so a plan
    /// that includes today after the fire time has gone looks scheduled and is not.
    @Test func todayIsSkippedOnceItsHourHasPassed() {
        let now = morning()                            // 10:00
        let today = StudyDay.stamp(now)
        #expect(StreakReminder.plan(now: now, studiedToday: false, hour: 20).contains(today))
        #expect(!StreakReminder.plan(now: now, studiedToday: false, hour: 9).contains(today))
        // The boundary: the hour it is right now has already begun, so it's too late.
        #expect(!StreakReminder.plan(now: now, studiedToday: false, hour: 10).contains(today))
    }

    /// Days are walked through `Calendar`, not by adding one to an integer — 20260228 + 1
    /// is not 20260229, and a month end is exactly where a hand-rolled plan breaks.
    @Test func planWalksRealCalendarDays() {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 30; c.hour = 10
        let now = StudyDay.calendar.date(from: c)!

        let days = StreakReminder.plan(now: now, studiedToday: false, hour: 20, horizon: 3)
        #expect(days == [20260830, 20260831, 20260901, 20260902])
        // Every stamp is a real date, and they strictly increase.
        #expect(days == days.sorted())
    }

    /// Well inside the 64 pending-request ceiling iOS enforces, past which it silently
    /// drops the rest — the horizon is a week for reasons of tone, not of limits.
    @Test func horizonStaysFarBelowTheSystemLimit() {
        let days = StreakReminder.plan(now: morning(), studiedToday: false)
        #expect(days.count <= 8)
        #expect(StreakReminder.horizon == 7)
    }

    /// An unset key reads 0 from `UserDefaults`, which is indistinguishable from a
    /// deliberate midnight — so the getter has to treat it as "never chosen".
    @Test func hourFallsBackRatherThanReadingMidnight() {
        let key = Pref.streakReminderHour
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(StreakReminder.resolvedHour == StreakReminder.defaultHour)
        UserDefaults.standard.set(0, forKey: key)
        #expect(StreakReminder.resolvedHour == StreakReminder.defaultHour)
        UserDefaults.standard.set(7, forKey: key)
        #expect(StreakReminder.resolvedHour == 7)
        UserDefaults.standard.set(99, forKey: key)
        #expect(StreakReminder.resolvedHour == StreakReminder.defaultHour)
    }

    /// The trigger is built from components, never a resolved `Date`, so iOS matches them
    /// against the calendar at fire time and a learner who flies still gets reminded at
    /// 8pm where they are.
    @Test func triggerComponentsCarryTheLocalHour() {
        let c = StreakReminder.components(day: 20260901, hour: 20)
        #expect(c.year == 2026 && c.month == 9 && c.day == 1)
        #expect(c.hour == 20 && c.minute == 0)
        // No timezone pinned — that is what lets it follow the device.
        #expect(c.timeZone == nil)
    }
}

// MARK: - Notification opt-in policy

struct NotificationOptInTests {
    private func streak(_ current: Int, today: Int = 20260811) -> Streak {
        let days = (0..<max(0, current)).map { StudyDay.stamp(today, offsetBy: -$0) }
        return Streak(days: Set(days), today: today)
    }

    /// The rule the whole design exists for: iOS shows its permission alert **once per
    /// install**, so a soft "not now" must never be followed by the real thing, and a
    /// system-level denial must stop the soft ask too — there is nowhere for a yes to go.
    @Test func neverAsksWhenTheSystemAlertCouldNotHelp() {
        #expect(NotificationOptIn.mayAsk(isOn: false, status: .notDetermined, lastAsked: nil))
        // Already on: nothing to offer.
        #expect(!NotificationOptIn.mayAsk(isOn: true, status: .notDetermined, lastAsked: nil))
        // Denied: iOS will never ask again, only the Settings app can undo it.
        #expect(!NotificationOptIn.mayAsk(isOn: false, status: .denied, lastAsked: nil))
        // Authorized but our toggle is off is a real state — permission granted, reminder
        // later switched off — and is worth asking about.
        #expect(NotificationOptIn.mayAsk(isOn: false, status: .authorized, lastAsked: nil))
    }

    @Test func aNotNowIsRespectedForTheWholeWindow() {
        let now = Date()
        let justAsked = now.addingTimeInterval(-60)
        let longAgo = now.addingTimeInterval(-NotificationOptIn.askAgainAfter - 60)

        #expect(!NotificationOptIn.mayAsk(isOn: false, status: .notDetermined,
                                          lastAsked: justAsked, now: now))
        #expect(NotificationOptIn.mayAsk(isOn: false, status: .notDetermined,
                                         lastAsked: longAgo, now: now))
        // Long enough that the prompt-about-prompts can't become its own nag.
        #expect(NotificationOptIn.askAgainAfter >= 30 * 24 * 60 * 60)
    }

    /// The offer is to protect the run you are *on*. A 30-day record means nothing if
    /// today is day 1 — there is no streak at stake tonight, and saying otherwise is the
    /// kind of manufactured urgency this app doesn't do.
    @Test func theStreakAskWaitsForAStreakWorthProtecting() {
        let threshold = NotificationOptIn.streakThreshold
        #expect(threshold == 7)

        for n in 0..<threshold {
            #expect(!NotificationOptIn.shouldAskAfterStreak(streak(n), isOn: false,
                                                            status: .notDetermined, lastAsked: nil))
        }
        #expect(NotificationOptIn.shouldAskAfterStreak(streak(threshold), isOn: false,
                                                       status: .notDetermined, lastAsked: nil))
        #expect(NotificationOptIn.shouldAskAfterStreak(streak(threshold + 5), isOn: false,
                                                       status: .notDetermined, lastAsked: nil))

        // A long best streak that is currently broken must not trigger it.
        let brokenButDecorated = Streak(days: Set((5...20).map { StudyDay.stamp(20260811, offsetBy: -$0) }),
                                        today: 20260811)
        #expect(brokenButDecorated.best >= threshold)
        #expect(brokenButDecorated.current == 0)
        #expect(!NotificationOptIn.shouldAskAfterStreak(brokenButDecorated, isOn: false,
                                                        status: .notDetermined, lastAsked: nil))
    }

    /// Every gate in `mayAsk` still applies once the streak qualifies — the milestone is
    /// an extra condition, never an override.
    @Test func theStreakAskStillObeysEveryOtherGate() {
        let long = streak(30)
        #expect(!NotificationOptIn.shouldAskAfterStreak(long, isOn: true,
                                                        status: .notDetermined, lastAsked: nil))
        #expect(!NotificationOptIn.shouldAskAfterStreak(long, isOn: false,
                                                        status: .denied, lastAsked: nil))
        #expect(!NotificationOptIn.shouldAskAfterStreak(long, isOn: false, status: .notDetermined,
                                                        lastAsked: Date()))
    }
}

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

    /// The Challenge cheers are drawn, not just spoken, so each gloss owes all 17
    /// languages. A missing one doesn't crash — `L.t` hands back the key — so it ships as
    /// silent English in sixteen languages, which is precisely the failure that only a
    /// test catches. The Japanese itself must *not* be in the table: it is content in the
    /// language being learned and stays Japanese in every locale.
    @Test func cheerGlossesAreTranslatedEverywhere() throws {
        let table = try table()
        for (lang, strings) in table {
            for phrase in Cheer.passed + Cheer.missed {
                #expect(strings[phrase.meaning] != nil,
                        "\(lang) has no gloss for \(phrase.text) (\(phrase.meaning))")
                #expect(strings[phrase.text] == nil,
                        "\(lang) translates the Japanese \(phrase.text) — it should not")
            }
        }
    }

    @Test func uiStringsCoverEveryLanguageAndKey() throws {
        let table = try table()
        // The UI list is UIStrings' own key set, and every meaning language must have a
        // UI to sit in — but not the reverse. They were the same 17 codes while Minna
        // was the only course; JLPT ships three meaning languages against the same 17
        // UI languages, so equality here would be asserting a coincidence.
        #expect(Set(table.keys) == Set(L.availableLanguages))
        #expect(Set(VocabStore.availableLanguages).isSubset(of: Set(table.keys)))

        // Both pickers use one order, so they read as one family rather than two
        // unrelated lists of the same languages. The meanings list is a subset, so the
        // check is that it appears in the same *relative* order, not that it matches.
        let ui = L.availableLanguages
        let meanings = VocabStore.availableLanguages
        #expect(meanings == ui.filter(meanings.contains))

        // Every shipped language is placed deliberately. `L.ordered` appends unknowns
        // rather than dropping them, so without this a new language would quietly land
        // at the bottom of both pickers and nobody would notice.
        #expect(Set(table.keys).isSubset(of: Set(L.languageOrder)))

        // The two Chinese variants are one decision to a reader; half a list between them
        // looks like a bug.
        let zh = try #require(L.languageOrder.firstIndex(of: "zh"))
        let zhHant = try #require(L.languageOrder.firstIndex(of: "zh-Hant"))
        #expect(abs(zh - zhHant) == 1)
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

    /// The briefing states the star bands as "up to N wrong", and N has to be derived
    /// from the run's real question count — a short rung allows fewer misses than a
    /// ten-question one, and a hardcoded number would promise a star that never lands.
    @MainActor
    @Test func briefingStarBandsFollowTheQuestionCount() {
        for questions in [4, 6, 8, 10] {
            for minScore in [90, Challenge.passScore] {
                let allowed = ChallengeView.allowedWrong(questions: questions, minScore: minScore)
                // Missing exactly `allowed` still meets the band...
                let atBand = Int((Double(questions - allowed) / Double(questions) * 100).rounded())
                #expect(atBand >= minScore)
                // ...and one more never does.
                if allowed < questions {
                    let past = Int((Double(questions - allowed - 1) / Double(questions) * 100).rounded())
                    #expect(past < minScore)
                }
            }
        }
        // A clean ten-question rung: 1 miss keeps 2★ (90%), 2 keeps 1★ (80%).
        #expect(ChallengeView.allowedWrong(questions: 10, minScore: 90) == 1)
        #expect(ChallengeView.allowedWrong(questions: 10, minScore: Challenge.passScore) == 2)
        // Degenerate input must not divide by zero or loop.
        #expect(ChallengeView.allowedWrong(questions: 0, minScore: 80) == 0)
    }

    /// The lesson screen offers one "worth retrying" rung: passed but short of three
    /// stars, fewest stars first, and the *later* rung when two tie — the freshest gap.
    /// Nil once every passed rung is three-starred, so the card disappears when won.
    @MainActor
    @Test func retryTargetPicksTheWeakestPassedRung() {
        func result(_ index: Int, stars: Int, passed: Bool = true) -> ChallengeResult {
            ChallengeResult(lesson: 1, index: index, bestScore: stars * 30, stars: stars,
                            completedAt: passed ? .now : nil)
        }
        // 2★ at rung 2 and 1★ at rung 4 → the 1★ one, fewest stars wins.
        var rows = [2: result(2, stars: 2), 4: result(4, stars: 1)]
        #expect(SelectModeView.retryTarget(results: rows) == 4)
        // Tie on stars → the later rung.
        rows = [2: result(2, stars: 2), 5: result(5, stars: 2)]
        #expect(SelectModeView.retryTarget(results: rows) == 5)
        // An unpassed rung is the ladder's job, not the retry card's.
        rows = [3: result(3, stars: 0, passed: false)]
        #expect(SelectModeView.retryTarget(results: rows) == nil)
        // Everything three-starred → nothing to win back.
        rows = [1: result(1, stars: 3), 2: result(2, stars: 3)]
        #expect(SelectModeView.retryTarget(results: rows) == nil)
    }

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

    /// Match deals unambiguous rounds, clears a pair only on a real match, and never ends.
    @Test func matchDealsUnambiguousRoundsForever() {
        let words = VocabStore.lesson(1).entries
        let model = MatchModel(vocab: words)

        #expect(model.left.count == MatchModel.pairsPerRound)
        #expect(model.right.count == model.left.count)
        // Same words both sides, different order — two columns in step aren't a puzzle.
        #expect(Set(model.left.map(\.id)) == Set(model.right.map(\.id)))
        #expect(model.left.map(\.id) != model.right.map(\.id))

        // No two tiles may read alike on either side, or one pairing is arbitrary and the
        // resulting miss is the app's fault rather than the learner's.
        #expect(Set(model.left.map(\.text)).count == model.left.count)
        #expect(Set(model.right.map(\.text)).count == model.right.count)

        // A wrong pair scores an attempt, clears nothing, and blocks further taps until
        // it's dismissed — otherwise a fast tapper racks up misses on a frozen board.
        let firstID = model.left[0].id
        let wrongRight = model.right.firstIndex { $0.id != firstID }!
        model.pick(side: .left, index: 0)
        model.pick(side: .right, index: wrongRight)
        #expect(model.wrong)
        #expect(model.matched == 0)
        #expect(model.attempts == 1)
        model.pick(side: .left, index: 1)
        #expect(model.pickedLeft == 0)          // ignored while the miss is showing
        model.clearMiss()
        #expect(!model.wrong && model.pickedLeft == nil)

        // Clearing every pair flags the round done but does NOT deal — the deal waits
        // for the view (`dealNext`), so the fifth match keeps its board long enough to
        // speak its word and show its flash instead of being swallowed by its own
        // success. In the gap, taps are ignored. Then dealing brings a fresh board:
        // the mode is rehearsal, and rehearsal has no last question.
        let firstRound = model.rounds
        for _ in 0..<MatchModel.pairsPerRound {
            let l = model.left.firstIndex { !$0.cleared }!
            let r = model.right.firstIndex { $0.id == model.left[l].id }!
            model.pick(side: .left, index: l)
            model.pick(side: .right, index: r)
        }
        #expect(model.matched == MatchModel.pairsPerRound)
        #expect(model.roundCleared)
        #expect(model.rounds == firstRound)               // board still the old one
        #expect(model.word(id: model.left[0].id) != nil)  // the word is still speakable
        let attemptsBefore = model.attempts
        model.pick(side: .left, index: 0)
        #expect(model.attempts == attemptsBefore)         // gap taps score nothing
        model.dealNext()
        #expect(model.rounds == firstRound + 1)
        #expect(!model.roundCleared)
        #expect(model.left.allSatisfy { !$0.cleared })    // a brand-new board
    }

    /// A lesson smaller than a round still deals, and an empty one doesn't spin forever.
    @Test func matchSurvivesPoolsSmallerThanARound() {
        let words = VocabStore.lesson(1).entries
        let tiny = MatchModel(vocab: Array(words.prefix(2)))
        #expect(tiny.left.count == 2)

        // The degenerate case: `allSatisfy` is vacuously true on an empty board, so
        // without a guard clearing the last pair would deal forever.
        let empty = MatchModel(vocab: [])
        #expect(empty.left.isEmpty && empty.right.isEmpty)
        empty.pick(side: .left, index: 0)     // must not trap on an out-of-range index
        #expect(empty.attempts == 0)
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

    /// The spoken reaction never repeats itself back to back, and every phrase can name a
    /// clip file. "Varied" that can say the same thing twice running is exactly the case a
    /// listener notices, so the no-repeat rule is the part worth pinning.
    /// **Full-marks praise is held for full marks.** はなまる and かんぺき both *mean*
    /// a perfect score, so hearing one after two right out of three tells the learner the
    /// app isn't watching — praise that outranks the result is worth less than silence.
    /// They live in their own pool, reachable only at three stars.
    @Test func fullMarksPhrasesAreHeldForACleanSweep() {
        #expect(Cheer.tier(stars: 3, passed: true) == .perfect)
        #expect(Cheer.tier(stars: 2, passed: true) == .passed)
        #expect(Cheer.tier(stars: 1, passed: true) == .passed)
        #expect(Cheer.tier(stars: 0, passed: false) == .missed)

        // The two that name full marks are in the perfect pool and nowhere else.
        let fullMarks = ["hanamaru", "kanpeki"]
        #expect(fullMarks.allSatisfy { key in Cheer.perfect.contains { $0.key == key } })
        #expect(Cheer.passed.allSatisfy { !fullMarks.contains($0.key) })
        #expect(Cheer.missed.allSatisfy { !fullMarks.contains($0.key) })

        // Every tier still has something to say, and enough of it to vary.
        for tier in [Cheer.Tier.perfect, .passed, .missed] {
            #expect(Cheer.pool(tier).count >= 2)
        }
    }

    @Test func cheersVaryAndCanNameAClip() {
        for pool in [Cheer.perfect, Cheer.passed, Cheer.missed] {
            #expect(pool.count >= 2)      // one phrase can only ever repeat
            for phrase in pool {
                let next = Cheer.pick(from: pool, avoiding: phrase)
                #expect(next != phrase)
                #expect(next.map(pool.contains) == true)
            }
        }

        // Keys become `cheer-<key>.m4a`, so they must be unique across both pools and
        // safe as filenames — a collision would give two phrases the same clip.
        let all = Cheer.perfect + Cheer.passed + Cheer.missed
        let keys = all.map(\.key)
        #expect(Set(keys).count == keys.count)
        #expect(keys.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLowercase || $0 == "-" } })
        #expect(all.allSatisfy { !$0.text.isEmpty })
        #expect(all.allSatisfy { !$0.meaning.isEmpty })

        // Kana only. The generator synthesises `text` verbatim and bare kanji is
        // ambiguous to a TTS engine (角 is *kado* or *tsuno*), so a kanji slipping in
        // here is a clip that says the wrong word — with nothing on screen to show it.
        #expect(all.allSatisfy { !$0.text.contains { ("\u{4E00}"..."\u{9FFF}").contains($0) } })

        // The reading is derived from the key, so it must survive the round trip.
        #expect(all.allSatisfy { !$0.romaji.contains("-") && !$0.romaji.isEmpty })

        // Every phrase must have a clip in *both* voices. The keys are the filenames the
        // build script derives by globbing the submodule, so renaming one here without
        // renaming the clip drops that phrase to live TTS — audible only as one reaction
        // in sixteen sounding like the system voice, which nobody would report.
        for phrase in all {
            #expect(VocabStore.cheerAudioURL(phrase.key, voice: .default) != nil,
                    "no default-voice clip for \(phrase.key)")
            let alt = VocabStore.cheerAudioURL(phrase.key, voice: .alternate)
            #expect(alt != nil)
            #expect(alt?.lastPathComponent.contains(Speech.Voice.alternate.suffix) == true,
                    "\(phrase.key) fell back to the default voice — the alternate is missing")
        }
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

    /// The ladder is sequential across lessons: lesson n opens only when every rung
    /// of lesson n − 1 is passed. Passing is the bar — three stars is the earned-unlock
    /// bar, and demanding it here would let the reward block progress.
    @Test func previousLessonGatesTheNextLadder() throws {
        let ctx = try makeContext()
        #expect(ChallengeResult.previousLessonCleared(lesson: 1, context: ctx))

        // Lesson 1 partially passed: lesson 2 stays shut.
        let total = Challenge.count(wordCount: VocabStore.wordCount(1))
        for i in 1..<total {
            ChallengeResult.record(lesson: 1, index: i, score: 100, context: ctx)
        }
        #expect(!ChallengeResult.previousLessonCleared(lesson: 2, context: ctx))

        // The last rung passed — merely passed, not three-starred — opens it.
        ChallengeResult.record(lesson: 1, index: total, score: Challenge.passScore,
                               context: ctx)
        #expect(ChallengeResult.previousLessonCleared(lesson: 2, context: ctx))
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
    @Test func cardsAreNumberedInPagingOrder() {
        #expect(Intro.Card.allCases.count == 6)
        #expect(Intro.Card.allCases.map(\.rawValue) == [1, 2, 3, 4, 5, 6])
        #expect(Intro.Card.allCases == [.meanings, .kana, .modes, .challenge, .today, .reminders])
        // The ask goes last, after the tour has shown what there is to come back to.
        #expect(Intro.Card.allCases.last == .reminders)
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
        // Order is `SelectModeView`'s shallow → deep order, and the tour must not drift
        // from it: the chips exist to teach the labels the learner meets a tap later.
        #expect(Intro.Mode.allCases == [.vocabList, .flashcards, .practice, .match, .learn])
        #expect(Intro.Mode.allCases.map(\.titleKey)
                == ["Vocab List", "Flashcards", "Practice", "Match", "Learn"])
        #expect(Intro.Mode.allCases.map(\.subtitleKey)
                == ["Browse & hear all words", "Swipe through the words",
                    "Cards first, then a quick quiz",
                    "Pair each word with its meaning",
                    "Rebuild the reading from tiles"])
        // Practice gave up the card-stack glyph when Flashcards came back: that mode
        // *is* a stack of cards, and two modes sharing an icon in one grid is a bug the
        // eye finds before any test does.
        #expect(Intro.Mode.allCases.map(\.icon)
                == ["list.bullet", "rectangle.on.rectangle.angled", "graduationcap",
                    "link", "square.grid.2x2"])
        #expect(Set(Intro.Mode.allCases.map(\.icon)).count == Intro.Mode.allCases.count)
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
                 "Five ways through a lesson.", "Many ways to learn. All of them fun.",
                 "Challenge", "Challenge %@", "Best %@%", "Beat Challenge %@ to unlock",
                 "%@ questions a rung", "%@% to pass, up to three stars",
                 "Pass one and the next opens.",
                 "Studied Minna no Nihongo before?", "Studied Japanese before?",
                 "No, starting fresh",
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
