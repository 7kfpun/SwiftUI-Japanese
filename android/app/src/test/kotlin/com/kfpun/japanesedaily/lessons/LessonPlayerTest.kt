package com.kfpun.japanesedaily.lessons

import com.kfpun.japanesedaily.audio.Pronouncer
import com.kfpun.japanesedaily.data.vocab.AudioVoice
import com.kfpun.japanesedaily.data.vocab.ExampleSentence
import com.kfpun.japanesedaily.data.vocab.K
import com.kfpun.japanesedaily.data.vocab.Vocab
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LessonPlayerTest {
    /** Records every leg and finishes it at once, so the sequencing is what is under test. */
    private class FakePronouncer : Pronouncer {
        val legs = mutableListOf<String>()
        var stops = 0

        override fun speak(vocab: Vocab, voice: AudioVoice, rate: Float, onDone: () -> Unit) {
            legs += "word:${vocab.romaji}@$rate"
            onDone()
        }

        override fun speak(kana: K) = Unit

        override fun speakText(text: String, rate: Float, onDone: () -> Unit) = Unit

        override fun speakCheer(key: String, fallbackText: String) = Unit

        override fun speakExample(vocab: Vocab, rate: Float, onDone: () -> Unit) {
            legs += "example:${vocab.romaji}"
            onDone()
        }

        override fun speakMeaning(text: String, languageTag: String, rate: Float, onDone: () -> Unit) {
            legs += "meaning:$text:$languageTag"
            onDone()
        }

        override fun stop() {
            stops++
        }
    }

    private fun word(romaji: String, meaning: String = "m-$romaji", example: Boolean = false) = Vocab(
        lesson = 1,
        kanji = romaji,
        kana = romaji,
        romaji = romaji,
        dictionary = null,
        useKana = false,
        translation = meaning,
        audio = null,
        key = null,
        example = if (example) ExampleSentence(listOf("a"), listOf("a"), listOf("a")) else null,
        exampleTranslation = if (example) "t-$romaji" else null
    )

    private fun TestScope.player(p: FakePronouncer) = LessonPlayer(p, this)

    @Test
    fun japaneseOnlyReadsEachWordOnceAndThenFinishes() = kotlinx.coroutines.test.runTest(StandardTestDispatcher()) {
        val p = FakePronouncer()
        val player = player(p)
        var finished = 0
        player.onFinished = { finished++ }
        player.toggle(listOf(word("a"), word("b")), ReadMode.Japanese, "en", loops = false)
        advanceUntilIdle()
        assertEquals(listOf("word:a@1.0", "word:b@1.0"), p.legs)
        assertEquals(1, finished)
        assertFalse(player.isPlaying)
        assertNull(player.currentIndex)
    }

    @Test
    fun meaningModeReadsTheMeaningInTheLearnersLanguage() = kotlinx.coroutines.test.runTest(StandardTestDispatcher()) {
        val p = FakePronouncer()
        val player = player(p)
        player.toggle(listOf(word("a")), ReadMode.WithMeaning, "zh-Hant", loops = false)
        advanceUntilIdle()
        assertEquals(listOf("word:a@1.0", "meaning:m-a:zh-TW"), p.legs)
    }

    @Test
    fun exampleModeReadsFourLegsAndSkipsWhatAWordLacks() = kotlinx.coroutines.test.runTest(StandardTestDispatcher()) {
        val p = FakePronouncer()
        val player = player(p)
        player.toggle(listOf(word("a", example = true), word("b", meaning = "")), ReadMode.WithExample, "en", false)
        advanceUntilIdle()
        assertEquals(
            listOf("word:a@1.0", "meaning:m-a:en-US", "example:a", "meaning:t-a:en-US", "word:b@1.0"),
            p.legs
        )
    }

    @Test
    fun loopingWrapsCountsLapsAndKeepsGoingUntilStopped() = kotlinx.coroutines.test.runTest(StandardTestDispatcher()) {
        val p = FakePronouncer()
        val player = player(p)
        val laps = mutableListOf<Int>()
        player.onLap = { laps += it }
        player.toggle(listOf(word("a")), ReadMode.Japanese, "en", loops = true)
        advanceTimeBy(LessonPlayer.BETWEEN_WORDS_MILLIS * 3 + 100)
        runCurrent()
        assertTrue(laps.size >= 2)
        assertEquals(listOf(2, 3), laps.take(2))
        assertTrue(player.isPlaying)
        player.stop()
        val spoken = p.legs.size
        advanceTimeBy(10_000)
        assertEquals(spoken, p.legs.size) // a stopped run never advances
    }

    @Test
    fun rateAppliesToTheClips() = kotlinx.coroutines.test.runTest(StandardTestDispatcher()) {
        val p = FakePronouncer()
        val player = player(p)
        player.rate = 0.8
        player.toggle(listOf(word("a")), ReadMode.Japanese, "en", loops = false)
        advanceUntilIdle()
        assertEquals(listOf("word:a@0.8"), p.legs)
    }

    @Test
    fun pauseStopsAndResumeRestartsTheCurrentWord() = kotlinx.coroutines.test.runTest(StandardTestDispatcher()) {
        val p = FakePronouncer()
        val player = player(p)
        player.toggle(listOf(word("a"), word("b"), word("c")), ReadMode.Japanese, "en", loops = false)
        runCurrent()
        assertEquals(0, player.currentIndex)
        advanceTimeBy(LessonPlayer.BETWEEN_WORDS_MILLIS + 10)
        assertEquals(1, player.currentIndex)
        player.pause()
        assertTrue(player.isPaused)
        val before = p.legs.toList()
        advanceTimeBy(10_000)
        assertEquals(before, p.legs)
        player.resume()
        runCurrent()
        assertFalse(player.isPaused)
        assertEquals("word:b@1.0", p.legs.last())
    }

    @Test
    fun jumpingPlaysThatWordAndResumesFromPaused() = kotlinx.coroutines.test.runTest(StandardTestDispatcher()) {
        val p = FakePronouncer()
        val player = player(p)
        player.toggle(listOf(word("a"), word("b"), word("c")), ReadMode.Japanese, "en", loops = false)
        runCurrent()
        player.pause()
        player.play(2)
        runCurrent()
        assertFalse(player.isPaused)
        assertEquals(2, player.currentIndex)
        assertEquals("word:c@1.0", p.legs.last())
    }

    @Test
    fun tappingTheSameModeStopsIt() = kotlinx.coroutines.test.runTest(StandardTestDispatcher()) {
        val p = FakePronouncer()
        val player = player(p)
        val list = listOf(word("a"), word("b"))
        player.toggle(list, ReadMode.Japanese, "en", loops = true)
        runCurrent()
        assertTrue(player.isPlaying)
        player.toggle(list, ReadMode.Japanese, "en", loops = true)
        assertFalse(player.isPlaying)
        player.toggle(list, ReadMode.WithMeaning, "en", loops = true)
        assertTrue(player.isPlaying)
        player.release()
    }

    @Test
    fun anEmptyListCannotWrapOntoItself() {
        assertEquals(LessonPlayer.Step.End, LessonPlayer.step(0, 0, loops = true))
        assertEquals(LessonPlayer.Step.Next(1), LessonPlayer.step(0, 2, loops = false))
        assertEquals(LessonPlayer.Step.Wrap, LessonPlayer.step(1, 2, loops = true))
        assertEquals(LessonPlayer.Step.End, LessonPlayer.step(1, 2, loops = false))
    }

    @Test
    fun aLegThatNeverStartsTimesOutAndTheRunMovesOn() = kotlinx.coroutines.test.runTest(StandardTestDispatcher()) {
        val silent = object : Pronouncer by FakePronouncer() {
            val spoken = mutableListOf<String>()

            override fun speak(vocab: Vocab, voice: AudioVoice, rate: Float, onDone: () -> Unit) {
                spoken += vocab.romaji // never reports done: no voice installed, focus denied...
            }
        }
        val player = LessonPlayer(silent, this)
        player.toggle(listOf(word("a"), word("b")), ReadMode.Japanese, "en", loops = false)
        advanceUntilIdle()
        assertEquals(listOf("a", "b"), silent.spoken)
        assertFalse(player.isPlaying)
    }
}
