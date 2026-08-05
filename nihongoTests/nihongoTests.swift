//
//  nihongoTests.swift
//  nihongoTests
//
//  Created by KF PUN on 5/8/26.
//

import Testing
import Foundation
import SwiftData
@testable import nihongo

// MARK: - Bundled data integrity

struct DataTests {
    @Test func totalEntries() {
        #expect(VocabStore.allVocab().count == 2089)
    }

    @Test func fiftyLessonsNoGaps() {
        #expect(VocabStore.lessons().count == 50)
        #expect(VocabStore.lessons().map(\.number) == Array(1...50))
    }

    @Test func allEnglishTranslationsResolved() {
        #expect(VocabStore.allVocab().allSatisfy { !$0.translation.isEmpty })
    }

    @Test func schemaCounts() {
        #expect(VocabStore.allVocab().filter(\.useKana).count == 32)
        #expect(VocabStore.allVocab().filter { $0.dictionary != nil }.count == 284)
    }

    @Test func idsAreGloballyUnique() {
        let ids = VocabStore.allVocab().map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func romajiIsNotGloballyUnique() {
        // 111 romaji repeat across lessons — this is why id must include the lesson.
        let r = VocabStore.allVocab().map(\.romaji)
        #expect(Set(r).count < r.count)
    }

    @Test func audioAttachedToMostEntries() {
        // 2087 of 2089 have a Kyoko clip (2 sentence-like entries are intentionally skipped).
        #expect(VocabStore.allVocab().filter { $0.audio != nil }.count == 2087)
    }

    @Test func sampleAudioClipIsBundled() {
        let watashi = VocabStore.lesson(1).entries.first { $0.romaji == "watashi" }
        #expect(watashi?.audio == "audio/kyoko/1/watashi.m4a")
        #expect(VocabStore.audioURL(for: watashi!) != nil)
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
    }
}

// MARK: - Kana data (generated from kana.js)

struct KanaTests {
    private func nonEmpty(_ t: [[K]]) -> Int { t.flatMap { $0 }.filter { !$0.isEmpty }.count }

    @Test func tableCounts() {
        #expect(nonEmpty(KanaData.seion) == 46)
        #expect(nonEmpty(KanaData.dakuon) == 25)
        #expect(nonEmpty(KanaData.youon) == 33)
    }

    @Test func poolSizes() {
        #expect(KanaData.hiraganaPool.count == 74)
        #expect(KanaData.katakanaPool.count == 74)
    }
}

// MARK: - Search

struct SearchTests {
    @Test func findsByRomaji() {
        #expect(searchVocab("watashi").contains { $0.romaji == "watashi" })
    }
    @Test func findsByTranslation() {
        #expect(!searchVocab("teacher").isEmpty)
    }
    @Test func emptyQueryReturnsNothing() {
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

// MARK: - Quiz models

struct QuizTests {
    @Test func mcHasFourDistinctOptionsIncludingAnswer() {
        let model = QuizModel(vocab: VocabStore.lesson(5).entries)
        for _ in 0..<50 {
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

    @Test func kanaQuizHasFourDistinctOptionsIncludingAnswer() {
        let pool = KanaData.seion.flatMap { $0 }
        let model = KanaQuizModel(pool: pool)
        for _ in 0..<50 {
            model.next()
            #expect(model.options.count == 4)
            #expect(model.options.contains { $0.romaji == model.answer.romaji })
            let romaji = model.options.map(\.romaji)
            #expect(Set(romaji).count == romaji.count)
        }
    }

    @Test func kanaSwipeQuizHasTwoDistinctOptionsIncludingAnswer() {
        let pool = KanaData.seion.flatMap { $0 }
        let model = KanaQuizModel(pool: pool, optionCount: 2)
        for _ in 0..<50 {
            model.next()
            #expect(model.options.count == 2)
            #expect(model.options.contains { $0.romaji == model.answer.romaji })
            #expect(model.options[0].romaji != model.options[1].romaji)
        }
    }
}

// MARK: - App localization (UIStrings.json)

struct LocalizationTests {
    private let langs = ["en", "zh", "zh-Hant", "vi", "de", "th", "my"]

    @Test func uiStringsCoverEveryLanguageAndKey() throws {
        let url = try #require(Bundle.main.url(forResource: "UIStrings", withExtension: "json"))
        let table = try JSONDecoder().decode([String: [String: String]].self,
                                              from: Data(contentsOf: url))
        let enKeys = try #require(table["en"]).keys
        #expect(enKeys.count >= 40)
        for lang in langs {
            let dict = try #require(table[lang], "missing language \(lang)")
            #expect(Set(dict.keys) == Set(enKeys))          // no missing / extra keys
            #expect(dict.values.allSatisfy { !$0.isEmpty })  // no blank translations
        }
    }

    @Test func localizedLookupFallsBackToKey() {
        #expect(L.t("a key that does not exist") == "a key that does not exist")
    }

    @Test func deviceDefaultIsShipped() {
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
        for _ in 0..<60 {
            answered.insert(model.answer.romaji)
            model.choose(0, context: ctx)   // records model.answer regardless of pick
            model.next()
        }
        let stored = try ctx.fetch(FetchDescriptor<KanaResult>())
        #expect(stored.count == answered.count)
        #expect(Set(stored.map(\.romaji)).count == stored.count)
        #expect(model.total == 60)
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
