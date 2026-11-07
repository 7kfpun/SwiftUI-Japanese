package com.kfpun.japanesedaily.data

import com.kfpun.japanesedaily.data.vocab.AudioVoice
import com.kfpun.japanesedaily.data.vocab.ExampleSentence
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.KanaData
import com.kfpun.japanesedaily.data.vocab.LanguageOrder
import com.kfpun.japanesedaily.data.vocab.VocabStore
import com.kfpun.japanesedaily.data.vocab.cleanWord
import com.kfpun.japanesedaily.data.vocab.searchVocab
import java.io.File
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ports of the nihongoTests data canaries (`DataTests`, `KanaTests`, `TextTests`). They read the
 * generated `nihongo/Resources` in place, so a regeneration that changes the shape fails here.
 * Unit tests run with `android/app` as the working directory.
 */
class DataTest {
    private val resources = File("../../nihongo/Resources")
    private val assets = FileAssetSource(resources)
    private val store = VocabStore(assets)
    private val kana = KanaData(assets)

    @Test
    fun generatedDataShape() {
        // Regeneration canaries: update together with `scripts/build-minna-data.py` output.
        assertEquals(2100, store.allVocab().size)
        assertEquals(2100, store.allVocab().count { it.audio != null })
        assertEquals((1..50).toList(), store.lessons().map { it.number })
        assertEquals(50, Course.current.lessonCount)
    }

    @Test
    fun vocabIdsAreGloballyUnique() {
        val ids = store.allVocab().map { it.id }
        assertEquals(ids.size, ids.toSet().size)
    }

    @Test
    fun everyWordHasAClipOnDisk() {
        for (v in store.allVocab()) {
            val path = store.audioPath(v)
            assertNotNull("no clip for ${v.id}", path)
            assertTrue("$path is missing", File(resources, path!!).isFile)
            // The alternate voice ships beside it, which is what makes the ladder's listening rungs real.
            val alt = store.audioPath(v, AudioVoice.Alternate)!!
            assertTrue("no alternate clip for ${v.id}", alt.endsWith("-kenzaki.m4a"))
        }
    }

    @Test
    fun everyKanaCellHasAClip() {
        for (cell in (kana.seion + kana.dakuon + kana.youon).flatten().filterNot { it.isEmpty }) {
            val path = store.kanaAudioPath(cell.romaji)
            assertNotNull("no kana clip for ${cell.romaji}", path)
            assertTrue(File(resources, path!!).isFile)
        }
        assertNull(store.kanaAudioPath(""))
    }

    @Test
    fun cheerClipsResolveWithVoiceFallback() {
        assertNotNull(store.cheerAudioPath("sugoi"))
        assertTrue(store.cheerAudioPath("sugoi", AudioVoice.Alternate)!!.endsWith("-kenzaki.m4a"))
        assertNull(store.cheerAudioPath(""))
        assertNull(store.cheerAudioPath("no-such-cheer"))
    }

    @Test
    fun everyLessonSupportsGameplay() {
        for (lesson in store.lessons()) {
            assertTrue("lesson ${lesson.number} has too few words", lesson.entries.size >= 7)
            // A four-option quiz needs four distinct kana readings.
            val distinct = lesson.entries.map { it.kana }.toSet().size
            assertTrue("lesson ${lesson.number} lacks 4 distinct kana", distinct >= 4)
        }
    }

    @Test
    fun wordCountReadsTheDataWithoutBuildingALanguage() {
        for (lesson in store.lessons()) assertEquals(lesson.entries.size, store.wordCount(lesson.number))
        assertEquals(0, store.wordCount(0))
        assertEquals(0, store.wordCount(51))
    }

    @Test
    fun nineteenLanguagesAllResolveEveryWord() {
        assertEquals(19, store.availableLanguages.size)
        assertEquals(LanguageOrder.order, store.availableLanguages)
        for (lang in store.availableLanguages) {
            for (lesson in store.lessons(lang)) {
                for (v in lesson.entries) {
                    assertTrue("no $lang meaning for ${v.id}", v.translation.isNotEmpty())
                }
            }
        }
    }

    @Test
    fun translationsSwitchWithLanguage() {
        val en = store.lesson(1, "en").entries.first { it.romaji == "watashi" }.translation
        val zh = store.lesson(1, "zh").entries.first { it.romaji == "watashi" }.translation
        assertEquals("I", en)
        assertTrue(zh.isNotEmpty() && zh != en)
    }

    @Test
    fun anUnknownLanguageFallsBackToEnglishWholesale() {
        val v = store.lesson(1, "xx").entries.first { it.romaji == "watashi" }
        assertEquals("I", v.translation)
    }

    @Test
    fun everyEntryCarriesAnExample() {
        assertTrue(store.hasExamples)
        val all = store.allVocab()
        assertTrue(all.all { it.example != null })
        assertTrue(all.mapNotNull { it.example?.spoken }.toSet().size == all.size)
    }

    @Test
    fun deviceDefaultLanguageFollowsTheDataNotTheLocale() {
        assertEquals("vi", store.deviceDefaultLanguage(Locale.forLanguageTag("vi-VN")))
        assertEquals("zh-Hant", store.deviceDefaultLanguage(Locale.forLanguageTag("zh-CN")))
        assertEquals("zh-Hant", store.deviceDefaultLanguage(Locale.forLanguageTag("zh-TW")))
        assertEquals("id", store.deviceDefaultLanguage(Locale("in", "ID")))
        assertEquals("fil", store.deviceDefaultLanguage(Locale("tl", "PH")))
        assertEquals("en", store.deviceDefaultLanguage(Locale.forLanguageTag("sw")))
    }

    @Test
    fun kanaChartHasTheTextbookCounts() {
        fun count(grid: List<List<com.kfpun.japanesedaily.data.vocab.K>>) = grid.flatten().count { !it.isEmpty }
        assertEquals(46, count(kana.seion))
        assertEquals(25, count(kana.dakuon))
        assertEquals(33, count(kana.youon))
        assertEquals(74, KanaData.hiraganaPool.size)
        assertEquals(74, KanaData.katakanaPool.size)
        // ん sits alone on the last row, matching the printed chart.
        assertEquals(1, kana.seion.last().size)
        assertEquals("ん", kana.seion.last().single().hiragana)
    }

    @Test
    fun strokeCountsCoverEveryDrawableKana() {
        for (cell in kana.seion.flatten().filterNot { it.isEmpty }) {
            assertTrue("no stroke count for ${cell.romaji}", cell.hiraganaStrokes > 0 && cell.katakanaStrokes > 0)
        }
    }

    @Test
    fun cleanWordStripsAnnotations() {
        assertEquals("のります", cleanWord("のります［でんしゃに～］"))
        assertEquals("大変", cleanWord("大変「な」"))
        assertEquals("お問い合わせの番号", cleanWord("お問い合わせの番号。"))
        assertEquals("さん", cleanWord("～さん"))
        assertEquals("", cleanWord(""))
    }

    @Test
    fun searchMatchesAcrossFieldsAndIgnoresBlank() {
        val all = store.allVocab()
        assertTrue(searchVocab("watashi", all).any { it.romaji == "watashi" })
        assertTrue(searchVocab("teacher", all).isNotEmpty())
        assertTrue(searchVocab("   ", all).isEmpty())
    }

    @Test
    fun furiganaTrimsToTheKanjiCore() {
        val ex = ExampleSentence(
            kanji = listOf("わたしは", "学生です。"),
            kana = listOf("わたしは", "がくせいです。"),
            romaji = listOf("watashiwa", "gakuseidesu")
        )
        assertNull(ex.reading(0))
        assertEquals("がくせい", ex.reading(1))
        assertEquals("ひと", ExampleSentence(listOf("人は"), listOf("ひとは"), listOf("hitowa")).reading(0))
        assertEquals("なまえ", ExampleSentence(listOf("お名前は"), listOf("おなまえは"), listOf("onamaewa")).reading(0))
        assertNull(ex.reading(9))
    }

    @Test
    fun lessonGroupsTileEveryLesson() {
        val groups = Course.current.groups
        assertEquals(1, groups.first().first)
        assertEquals(Course.current.lessonCount, groups.last().last)
        for ((a, b) in groups.zipWithNext()) assertEquals("gap or overlap after ${a.name}", a.last + 1, b.first)
    }

    @Test
    fun theGeneratedFilesAreNotTreatedAsMissing() {
        assertFalse(store.availableLanguages.isEmpty())
    }
}
