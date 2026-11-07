package com.kfpun.japanesedaily.lessons

import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.data.vocab.VocabStore
import com.kfpun.japanesedaily.data.vocab.cleanWord
import java.io.File
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ports of the iOS `MatchTests` and `LearnTests`. */
class MatchLearnTest {
    private val store = VocabStore(FileAssetSource(File("../../nihongo/Resources")))
    private val lesson1: List<Vocab> get() = store.lesson(1).entries

    // region Match

    private fun match(seed: Int = 1) = MatchModel(lesson1, Random(seed))

    private fun MatchModel.rightIndexOf(id: String) = right.indexOfFirst { it.id == id }

    @Test
    fun dealsFiveDistinctPairsWithTheColumnsOutOfStep() {
        repeat(40) { seed ->
            val m = match(seed)
            assertEquals(5, m.left.size)
            assertEquals(5, m.right.size)
            assertEquals(m.left.map { it.id }.toSet(), m.right.map { it.id }.toSet())
            assertEquals(5, m.left.map { it.text }.toSet().size)
            assertEquals(5, m.right.map { it.text }.toSet().size)
            assertNotEquals(m.left.map { it.id }, m.right.map { it.id })
            assertTrue(m.left.all { it.isJapanese } && m.right.none { it.isJapanese })
        }
    }

    @Test
    fun aMatchClearsBothTilesInEitherTapOrder() {
        val m = match()
        val id = m.left[0].id
        m.pick(MatchModel.Side.Left, 0)
        m.pick(MatchModel.Side.Right, m.rightIndexOf(id))
        assertEquals(1, m.matched)
        assertEquals(1, m.attempts)
        assertEquals(id, m.lastMatched)
        assertTrue(m.left[0].cleared)

        // Meanings first: the recall direction.
        val id2 = m.left[1].id
        m.pick(MatchModel.Side.Right, m.rightIndexOf(id2))
        m.pick(MatchModel.Side.Left, 1)
        assertEquals(2, m.matched)
    }

    @Test
    fun aMissIsCountedBlocksInputAndClearsOnRequest() {
        val m = match()
        val wrongRight = m.right.indexOfFirst { it.id != m.left[0].id }
        m.pick(MatchModel.Side.Left, 0)
        m.pick(MatchModel.Side.Right, wrongRight)
        assertTrue(m.wrong)
        assertEquals(1, m.attempts)
        assertEquals(0, m.matched)
        // Ignored while the miss is showing.
        m.pick(MatchModel.Side.Left, 1)
        assertEquals(0, m.pickedLeft?.let { if (it == 1) 1 else 0 })
        m.clearMiss()
        assertFalse(m.wrong)
        assertNull(m.pickedLeft)
        assertNull(m.pickedRight)
    }

    @Test
    fun matchingComparesIdsNotDisplayedText() {
        val m = match()
        val twin = m.right.indexOfFirst { it.id != m.left[0].id }
        m.pick(MatchModel.Side.Left, 0)
        m.pick(MatchModel.Side.Right, twin)
        assertEquals(0, m.matched)
    }

    @Test
    fun theLastPairFlagsTheRoundAndTheDealIsDeferred() {
        val m = match()
        val firstRound = m.left.map { it.id }
        for (i in 0 until 5) {
            m.pick(MatchModel.Side.Left, i)
            m.pick(MatchModel.Side.Right, m.rightIndexOf(m.left[i].id))
        }
        assertTrue(m.roundCleared)
        assertEquals(firstRound, m.left.map { it.id }) // not swallowed by its own success
        assertEquals(1, m.rounds)
        // Taps between the last match and the next deal are ignored.
        m.pick(MatchModel.Side.Left, 0)
        assertEquals(5, m.attempts)
        m.dealNext()
        assertEquals(2, m.rounds)
        assertFalse(m.roundCleared)
        assertTrue(m.left.none { it.cleared })
    }

    @Test
    fun dealNextIsANoOpMidRound() {
        val m = match()
        m.dealNext()
        assertEquals(1, m.rounds)
    }

    @Test
    fun theBagDealsEveryWordBeforeRepeatingOne() {
        val m = MatchModel(lesson1.take(10), Random(5))
        val seen = HashSet<String>()
        repeat(2) {
            m.left.forEach { seen.add(it.id) }
            for (i in 0 until 5) {
                m.pick(MatchModel.Side.Left, i)
                m.pick(MatchModel.Side.Right, m.rightIndexOf(m.left[i].id))
            }
            m.dealNext()
        }
        assertEquals(10, seen.size)
    }

    @Test
    fun aSmallLessonDealsWhatItHasAndAnEmptyOneDealsNothing() {
        assertEquals(3, MatchModel(lesson1.take(3), Random(1)).left.size)
        val empty = MatchModel(emptyList(), Random(1))
        assertTrue(empty.left.isEmpty())
        assertFalse(empty.roundCleared)
        empty.pick(MatchModel.Side.Left, 0)
        assertEquals(0, empty.attempts)
    }

    @Test
    fun theViaIsRecordedForTheAnswerEvent() {
        val m = match()
        m.pick(MatchModel.Side.Left, 0, via = "drag")
        assertEquals("drag", m.lastVia)
    }

    @Test
    fun wordLookupFindsTheCurrentRoundOnly() {
        val m = match()
        assertEquals(m.left[0].id, m.word(m.left[0].id)?.id)
        assertNull(m.word("nope"))
    }

    // endregion

    // region Learn

    @Test
    fun tileGenerationNeverCrashesAndKeepsTheAnswerBuildable() {
        val random = Random(11)
        for (word in store.allVocab()) {
            val m = LearnModel(listOf(word), random)
            val target = m.target.map { it.toString() }
            if (!m.isPlayable) continue
            val pool = m.tiles.map { it.text }.toMutableList()
            for (c in target) assertTrue("${word.id} lacks $c", pool.remove(c))
        }
    }

    @Test
    fun sentenceLengthEntryBails() {
        val long = store.allVocab().filter { cleanWord(it.kana).length > LearnModel.MAX_TARGET }
        assertEquals(1, long.size)
        assertEquals(14, long[0].lesson)
        val m = LearnModel(long, Random(1))
        assertFalse(m.isPlayable)
        assertTrue(m.tiles.isEmpty())
    }

    @Test
    fun anEmptyTargetIsUnplayable() {
        val m = LearnModel(emptyList(), Random(1))
        assertFalse(m.isPlayable)
        m.next()
        m.prev()
        m.random()
        assertEquals(0, m.index)
    }

    @Test
    fun tileCountIsTenOrFifteenMinusTheTargetLength() {
        val word = lesson1.first { cleanWord(it.kana).length in 2..8 }
        val m = LearnModel(listOf(word), Random(2))
        assertEquals(10, m.tiles.size)
        val longer = store.allVocab().first { cleanWord(it.kana).length in 11..15 }
        assertEquals(15, LearnModel(listOf(longer), Random(2)).tiles.size)
    }

    private fun LearnModel.tapTarget(upTo: Int = Int.MAX_VALUE) {
        val used = HashSet<Int>()
        for (c in target.take(upTo).map { it.toString() }) {
            val tile = tiles.first { it.text == c && it.id !in used }
            used.add(tile.id)
            tap(tile)
        }
    }

    @Test
    fun correctTheInstantTheBuiltStringEqualsTheTarget() {
        val m = LearnModel(listOf(lesson1.first { cleanWord(it.kana).length >= 3 }), Random(4))
        m.tapTarget(upTo = m.target.length - 1)
        assertEquals(AnswerState.InProgress, m.state)
        m.tapTarget()
        // tapTarget re-taps from scratch on top of the prefix; rebuild cleanly.
        m.clearAnswer()
        m.tapTarget()
        assertEquals(AnswerState.Correct, m.state)
    }

    @Test
    fun wrongTheInstantItIsNoLongerAPrefix() {
        val m = LearnModel(listOf(lesson1.first { cleanWord(it.kana).length >= 3 }), Random(4))
        val wrong = m.tiles.first { it.text != m.target.take(1) }
        m.tap(wrong)
        assertEquals(AnswerState.Wrong, m.state)
        // A wrong state disables further taps until Clear.
        val before = m.answer
        m.tap(m.tiles.last())
        assertEquals(before, m.answer)
        m.clearAnswer()
        assertEquals(AnswerState.InProgress, m.state)
        assertTrue(m.answer.isEmpty())
    }

    @Test
    fun pagingWrapsAndReloadsTiles() {
        val m = LearnModel(lesson1.take(3), Random(1))
        m.prev()
        assertEquals(2, m.index)
        m.next()
        assertEquals(0, m.index)
        assertEquals(AnswerState.InProgress, m.state)
    }

    // endregion
}
