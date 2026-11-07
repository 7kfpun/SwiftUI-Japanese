package com.kfpun.japanesedaily.kana

import com.kfpun.japanesedaily.data.progress.KanaResult
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.K
import com.kfpun.japanesedaily.data.vocab.KanaData
import com.kfpun.japanesedaily.ui.KanaForm
import java.io.File
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ports of the kana tests in `nihongoTests` (the quiz model, KanaResult persistence rules) plus the deck. */
class KanaModelsTest {
    private val data = KanaData(FileAssetSource(File("../../nihongo/Resources")))

    @Test
    fun everyKanaSetHasPlayableOptions() {
        for (table in KanaTable.entries) {
            val pool = table.pool(data)
            assertTrue("$table pool", pool.size >= 20)
            for (count in listOf(2, 4)) {
                val model = KanaQuizModel(pool, count, Random(7))
                repeat(200) {
                    val wanted = minOf(count, distinctRomaji(pool).size)
                    assertEquals(wanted, model.options.size)
                    assertEquals(wanted, model.options.map { it.romaji }.toSet().size)
                    assertEquals(
                        "exactly one correct option",
                        1,
                        model.options.count {
                            it.romaji == model.answer.romaji
                        }
                    )
                    model.next()
                }
            }
        }
    }

    @Test
    fun chooseRecordsEveryAnswerRightOrWrongAndOnlyOnce() {
        val recorded = mutableListOf<Pair<String, Boolean>>()
        val model = KanaQuizModel(KanaTable.Seion.pool(data), 4, Random(1)) { r, c -> recorded += r to c }
        val wrong = model.options.indexOfFirst { it.romaji != model.answer.romaji }
        assertEquals(false, model.choose(wrong))
        assertNull("second pick is ignored", model.choose(0))
        assertEquals(1, recorded.size)
        assertEquals(model.answer.romaji to false, recorded.single())
        assertEquals(0, model.correct)
        assertEquals(1, model.total)

        model.next()
        assertNull(model.picked)
        val right = model.options.indexOfFirst { it.romaji == model.answer.romaji }
        assertEquals(true, model.choose(right))
        assertEquals(1, model.correct)
        assertEquals(2, model.total)
        assertEquals(2, recorded.size)
    }

    @Test
    fun directionSwapsExchangeWithTheReserveForm() {
        val model = KanaQuizModel(KanaTable.Seion.pool(data))
        assertEquals(KanaForm.Hiragana, model.from)
        assertEquals(KanaForm.Romaji, model.to) // starts on romaji: the usual state is the Latin one
        model.swapFrom()
        assertEquals(KanaForm.Katakana, model.from)
        model.swapTo()
        assertEquals(KanaForm.Hiragana, model.to) // the reserve was hiragana after the first swap
        assertEquals(KanaForm.Katakana, model.from)
    }

    @Test
    fun theTableSplitIsTheJapaneseTermsAndCountsFromTheChart() {
        assertEquals(listOf("seion", "dakuon", "youon"), KanaTable.entries.map { it.raw })
        // じ/ぢ and ず/づ share a romaji, so the chart has fewer distinct answers than tiles.
        val dakuon = KanaTable.Dakuon.pool(data)
        assertTrue(distinctRomaji(dakuon).size < dakuon.size)
    }

    @Test
    fun tileScriptOrderIsAPersistedContract() {
        assertEquals(listOf("あ", "ア", "A"), TileScript.entries.map { it.glyph })
        assertEquals(1, TileScript.next(0))
        assertEquals(2, TileScript.next(1))
        assertEquals(0, TileScript.next(2))
        assertEquals(KanaForm.Romaji, TileScript.of(2).form)
        // Romaji is Latin, so it takes the Latin face; the two kana scripts take the Japanese one.
        assertEquals(listOf(true, true, false), TileScript.entries.map { it.form.isJapanese })
    }

    @Test
    fun learnedCountTakesTheLatestAnswerPerDistinctRomaji() {
        val cells = listOf(K("じ", "ジ", "ji"), K("ぢ", "ヂ", "ji"), K("あ", "ア", "a"), K("", "", ""))
        assertEquals(0, learnedCount(cells, emptyMap()))
        assertEquals(1, learnedCount(cells, mapOf("ji" to true, "a" to false)))
        assertEquals(2, learnedCount(cells, mapOf("ji" to true, "a" to true)))
        assertEquals(2, distinctRomaji(cells).size)
    }

    @Test
    fun latestResultWinsOnDuplicateRows() {
        val rows = listOf(KanaResult("a", true, 1), KanaResult("a", false, 5), KanaResult("a", true, 3))
        assertFalse(KanaResult.latest(rows).getValue("a").isCorrect)
    }

    @Test
    fun flashDeckRetiresOnKnowAndRequeuesOnDontKnow() {
        val deck = FlashDeck(listOf(1, 2, 3), Random(3))
        assertEquals(3, deck.total)
        val first = deck.current
        deck.dontKnow()
        assertEquals(3, deck.remaining)
        assertEquals(first, deck.peek(2).last()) // sent to the back
        deck.know()
        deck.know()
        deck.know()
        assertTrue(deck.isDone)
        assertEquals(3, deck.mastered)
        deck.restart()
        assertEquals(3, deck.remaining)
        assertEquals(0, deck.mastered)
    }

    @Test
    fun writeGradeNeedsTheExactStrokeCountAndTheMark() {
        assertTrue(WriteGrade.passes(80, 3, 3))
        assertFalse("79 is below the bar", WriteGrade.passes(79, 3, 3))
        assertFalse("too few strokes", WriteGrade.passes(95, 2, 3))
        assertFalse("too many strokes", WriteGrade.passes(95, 4, 3))
        assertTrue("no textbook count is shape-only", WriteGrade.passes(80, 7, null))
        assertEquals(80, KanaSketch.PASS_SCORE) // the same bar the Challenge ladder uses
    }
}
