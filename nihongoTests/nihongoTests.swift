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

// MARK: - Quiz models

struct QuizTests {
    @Test func mcHasFourDistinctOptionsIncludingAnswer() {
        let model = QuizModel(vocab: VocabStore.lesson(5).entries)
        for _ in 0..<30 {
            model.next()
            #expect(model.options.count == 4)
            #expect(model.options.contains { $0.id == model.answer.id })
            let kanas = model.options.map(\.kana)
            #expect(Set(kanas).count == kanas.count)
        }
    }

    @Test func mcFormCyclingSkipsOtherSide() {
        let model = QuizModel(vocab: VocabStore.lesson(1).entries)
        model.cycleFrom()
        #expect(model.from != model.to)
        model.cycleTo()
        #expect(model.from != model.to)
    }

    @Test func listeningVariantUsesAudioPromptAndWordOptions() {
        // "Listening" is Quiz with an audio prompt; options are the written word (kana).
        let model = QuizModel(vocab: VocabStore.lesson(3).entries, from: .audio)
        #expect(model.from == .audio)
        #expect(model.to == .kana)
        // Cycling the answer side must never land on audio (audio can't be an option).
        for _ in 0..<10 { model.cycleTo(); #expect(model.to != .audio) }
    }

    @Test func promptCanCycleToAudioButBackAgain() {
        let model = QuizModel(vocab: VocabStore.lesson(1).entries)
        var sawAudio = false
        for _ in 0..<VForm.allCases.count { model.cycleFrom(); if model.from == .audio { sawAudio = true } }
        #expect(sawAudio)                 // audio is reachable as a prompt
        #expect(model.from != model.to)   // and never collides with the answer side
    }

    @Test func emptyVocabDegradesInsteadOfCrashing() {
        let model = QuizModel(vocab: [])
        #expect(model.options.isEmpty)
        #expect(model.answer.kana.isEmpty)   // placeholder answer, no crash
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
        #expect(QuizModel.promptAudioSafe(from: .kana))
        #expect(QuizModel.promptAudioSafe(from: .kanji))
        #expect(QuizModel.promptAudioSafe(from: .romaji))
        #expect(QuizModel.promptAudioSafe(from: .audio))
        #expect(!QuizModel.promptAudioSafe(from: .translation))
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
        #expect(Gating.freeLessonLimit == 5)
        #expect(Gating.freeTrialCards == 5)
        for n in 1...50 {
            #expect(Gating.isLocked(lesson: n, isPremium: false) == (n > 5))
            #expect(!Gating.isLocked(lesson: n, isPremium: true))
        }
        #expect(Gating.trialLimit(lesson: 3, isPremium: false) == nil)                   // free lesson
        #expect(Gating.trialLimit(lesson: 6, isPremium: false) == Gating.freeTrialCards) // locked → trial
        #expect(Gating.trialLimit(lesson: 6, isPremium: true) == nil)                    // premium
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

// MARK: - Today daily picker & widget contract

struct TodayTests {
    private var lesson: [Vocab] { VocabStore.lesson(2).entries }

    @Test func randomPickReturnsCountUniqueWords() {
        let picks = DailyPicker.pick(from: lesson, count: 7, savedIDs: [])
        #expect(picks.count == 7)
        #expect(Set(picks.map(\.id)).count == 7)
        #expect(picks.allSatisfy { lesson.contains($0) })
    }

    @Test func savedSelectionRestoresInOrder() {
        let saved: [String] = lesson.prefix(7).map(\.id).reversed()
        let picks = DailyPicker.pick(from: lesson, count: 7, savedIDs: saved)
        #expect(picks.map(\.id) == saved)   // exact words, saved order
    }

    @Test func staleSavedIDsFallBackToFreshPick() {
        let picks = DailyPicker.pick(from: lesson, count: 7, savedIDs: ["999/does-not-exist"])
        #expect(picks.count == 7)
    }

    /// The snapshot is the app↔widget wire format — it must round-trip stably.
    @Test func widgetSnapshotRoundTrips() throws {
        let words = lesson.prefix(7).map {
            TodayShared.Word(kana: $0.kana, kanji: $0.kanji, romaji: $0.romaji, meaning: $0.translation)
        }
        let snap = TodayShared.Snapshot(lesson: 2, words: Array(words))
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(TodayShared.Snapshot.self, from: data)
        #expect(back.lesson == 2)
        #expect(back.words == Array(words))
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
