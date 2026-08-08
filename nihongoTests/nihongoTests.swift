//
//  nihongoTests.swift
//  nihongoTests
//
//  Created by KF PUN on 5/8/26.
//

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
        #expect(VocabStore.allVocab().filter { $0.audio != nil }.count == 2087)
        #expect(VocabStore.lessons().map(\.number) == Array(1...50))
    }

    @Test func idsAreGloballyUnique() {
        // Romaji repeats across lessons, so Vocab.id must include the lesson number.
        let ids = VocabStore.allVocab().map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// Every screen's minimum data needs, checked for all 50 lessons: the Today tab
    /// picks 7 words, and the quiz needs 4 distinct-kana options.
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

// MARK: - Kana data (generated from kana.js)

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
                      dictionary: nil, useKana: false, translation: "I", audio: nil)

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
        // The old Listening mode is Train with an audio prompt; options are the word.
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
        // Lessons 1…3 free in full, 4…50 premium — one rule, no partial trial.
        #expect(Gating.freeLessonLimit == 3)
        for n in 1...50 {
            #expect(Gating.isLocked(lesson: n, isPremium: false) == (n > 3))
            #expect(!Gating.isLocked(lesson: n, isPremium: true))
        }
        // The boundary specifically: 3 free, 4 locked.
        #expect(!Gating.isLocked(lesson: 3, isPremium: false))
        #expect(Gating.isLocked(lesson: 4, isPremium: false))
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
        // The UI languages are exactly the vocabulary languages — one picker list.
        #expect(Set(table.keys) == Set(VocabStore.availableLanguages))
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
