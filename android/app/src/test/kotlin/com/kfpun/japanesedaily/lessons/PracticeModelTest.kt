package com.kfpun.japanesedaily.lessons

import com.kfpun.japanesedaily.data.progress.PracticeProgress
import com.kfpun.japanesedaily.data.progress.WordStage
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.data.vocab.VocabStore
import java.io.File
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of the iOS `PracticeTests`: stage scheduling, the pair rules and the distractor rule. */
class PracticeModelTest {
    private val store = VocabStore(FileAssetSource(File("../../nihongo/Resources")))
    private val lesson1: List<Vocab> get() = store.lesson(1).entries

    private class MapStages : StageStore {
        val map = HashMap<String, WordStage>()

        override fun stage(word: String) = map[word] ?: WordStage.Unseen

        override fun set(stage: WordStage, word: String) {
            map[word] = stage
        }
    }

    private fun model(
        stages: StageStore = MapStages(),
        vocab: List<Vocab> = lesson1,
        mixed: Boolean = false,
        seed: Int = 1
    ) = PracticeModel(vocab, stages, initialMixed = mixed, random = Random(seed))

    /** Answers the current card by picking its right (or a wrong) option. */
    private fun PracticeModel.answer(correct: Boolean, credited: Boolean = true) {
        val right = options.indexOfFirst { it.id == current!!.vocab.id }
        choose(if (correct) right else 1 - right)
        resolve(credited)
    }

    @Test
    fun everyCardIsATwoOptionQuizWhateverTheStage() {
        val stages = MapStages()
        lesson1.take(5).forEachIndexed { i, v -> stages.map[v.id] = WordStage.entries[i % 4] }
        val m = model(stages)
        repeat(30) {
            val item = m.current ?: return@repeat
            assertEquals(2, m.options.size)
            assertTrue(m.options.any { it.id == item.vocab.id })
            m.answer(true)
        }
    }

    @Test
    fun twoCorrectAnswersMemoriseAWord() {
        val stages = MapStages()
        val m = model(stages)
        val first = m.current!!.vocab
        m.answer(true)
        assertEquals(WordStage.Recognized, stages.stage(first.id))
        assertEquals(0, m.retired)
        // It comes back, far down the queue; fast-forward by answering until it returns.
        var guard = 0
        while (m.current?.vocab?.id != first.id && guard++ < 200) m.answer(true)
        assertEquals(first.id, m.current!!.vocab.id)
        m.answer(true)
        assertEquals(WordStage.Memorized, stages.stage(first.id))
        assertTrue(m.retired >= 1)
    }

    @Test
    fun aWrongAnswerDemotesToSeenAndTheCardReturns() {
        val stages = MapStages()
        val m = model(stages)
        val word = m.current!!.vocab
        stages.map[word.id] = WordStage.Recognized
        val before = m.queue.size
        m.answer(false)
        assertEquals(WordStage.Seen, stages.stage(word.id))
        assertEquals(before, m.queue.size) // popped and re-inserted
        assertTrue(m.queue.any { it.vocab.id == word.id })
        assertEquals(1, m.answered)
        assertEquals(0, m.retired)
    }

    @Test
    fun peekingCostsTheRoundButNotThePunishment() {
        val stages = MapStages()
        val m = model(stages)
        val word = m.current!!.vocab
        m.answer(true, credited = false)
        // A right answer after reading the answer moves nothing up the ladder.
        assertEquals(WordStage.Unseen, stages.stage(word.id))
        assertTrue(m.queue.any { it.vocab.id == word.id })
        // A wrong answer still demotes, peek or no peek.
        val second = m.current!!.vocab
        stages.map[second.id] = WordStage.Memorized
        m.answer(false, credited = false)
        assertEquals(WordStage.Seen, stages.stage(second.id))
    }

    @Test
    fun resolveWithoutAPickGradesNothing() {
        val stages = MapStages()
        val m = model(stages)
        m.resolve()
        assertEquals(0, m.answered)
        assertTrue(stages.map.isEmpty())
    }

    @Test
    fun aFullyMemorisedLessonReentersWholeAsReview() {
        val stages = MapStages()
        lesson1.forEach { stages.map[it.id] = WordStage.Memorized }
        val m = model(stages)
        assertEquals(lesson1.size, m.queue.size)
        // A wrong answer in review still demotes: the reason to reopen the mode.
        m.answer(false)
        assertEquals(1, stages.map.values.count { it == WordStage.Seen })
    }

    @Test
    fun restartBuildsFromCurrentStagesSoTheQueueShrinks() {
        val stages = MapStages()
        val m = model(stages)
        val total = m.sessionTotal
        lesson1.take(4).forEach { stages.map[it.id] = WordStage.Memorized }
        m.restart()
        assertEquals(total - 4, m.sessionTotal)
        assertEquals(0, m.answered)
    }

    @Test
    fun fractionDoneMovesOnEveryCorrectAnswerAndDipsOnAMiss() {
        val m = model()
        assertEquals(0.0, m.fractionDone, 0.0)
        m.answer(true)
        val afterOne = m.fractionDone
        assertTrue(afterOne > 0.0)
        m.answer(false)
        assertTrue(m.fractionDone < afterOne + 0.0001 || m.fractionDone <= afterOne)
        assertTrue(m.fractionDone in 0.0..1.0)
    }

    @Test
    fun aMissOnAReviewLapDoesNotPinTheBarAtZero() {
        // Every word at one owed answer: a miss grows the owed work past the session total, and the
        // total ratchets so the bar still moves on the next right answers.
        val stages = MapStages()
        lesson1.forEach { stages.map[it.id] = WordStage.Recognized }
        val m = model(stages)
        m.answer(false)
        val afterMiss = m.fractionDone
        m.answer(true)
        m.answer(true)
        assertTrue(m.fractionDone > afterMiss)
    }

    @Test
    fun theQueueKeepsReachingWordsItHasNotAskedYet() {
        // The near window must not starve unseen words behind a wall of re-tests.
        val m = model(seed = 7)
        val seen = HashSet<String>()
        var longestRun = 0
        var run = 0
        repeat(lesson1.size * 3) {
            val id = m.current?.vocab?.id ?: return@repeat
            if (seen.add(id)) run = 0 else run++
            longestRun = maxOf(longestRun, run)
            m.answer(true)
        }
        assertTrue("run of $longestRun re-tests", longestRun <= 18)
        assertTrue(seen.size > lesson1.size / 2)
    }

    @Test
    fun facesInterleaveRatherThanBlock() {
        // Requeue distance is drawn per word, so a re-asked word does not return in lockstep order.
        val windows = (1..50).map { PracticeModel.REQUEUE_WINDOW.random(Random(it)) }.toSet()
        assertTrue(windows.size > 1)
        assertTrue(PracticeModel.PROVEN_WINDOW.first > PracticeModel.REQUEUE_WINDOW.last)
    }

    // region Pair and distractor rules

    @Test
    fun aWordWithNoKanjiHasTwoFacesNotThree() {
        val plain = lesson1.first { !it.displaysKanji }
        val kanji = store.allVocab().first { it.displaysKanji }
        assertEquals(listOf(VForm.Kana, VForm.Translation), PracticeModel.faces(plain))
        assertEquals(listOf(VForm.Kana, VForm.Kanji, VForm.Translation), PracticeModel.faces(kanji))
    }

    @Test
    fun mixedDrawsEvenlyFromWhatEachWordSupports() {
        val plain = lesson1.first { !it.displaysKanji }
        val m = model(mixed = true)
        val counts = HashMap<Pair<VForm, VForm>, Int>()
        repeat(2000) { counts.merge(m.pair(plain), 1, Int::plus) }
        // Only the two kana-only combinations exist, and neither is starved (the loaded-die bug was ~2/3).
        assertEquals(setOf(VForm.Kana to VForm.Translation, VForm.Translation to VForm.Kana), counts.keys)
        counts.values.forEach { assertTrue("uneven: $counts", it in 800..1200) }
    }

    @Test
    fun aFixedPairNeverAsksKanjiOfAWordWithoutIt() {
        val plain = lesson1.first { !it.displaysKanji }
        val m = model()
        m.setPair(VForm.Kanji, VForm.Translation, mixed = false)
        val (f, t) = m.pair(plain)
        assertNotEquals(VForm.Kanji, f)
        assertNotEquals(f, t)
        // The side the learner chose survives: answering in kana keeps answering in kana.
        m.setPair(VForm.Translation, VForm.Kanji, mixed = false)
        val (f2, t2) = m.pair(plain)
        assertEquals(VForm.Translation, f2)
        assertEquals(VForm.Kana, t2)
    }

    @Test
    fun setPairRefusesIdenticalOrNonQuizFaces() {
        val m = model()
        m.setPair(VForm.Kana, VForm.Kana, false)
        m.setPair(VForm.Romaji, VForm.Kana, false)
        m.setPair(VForm.Audio, VForm.Kana, false)
        assertEquals(VForm.Kana, m.from)
        assertEquals(VForm.Translation, m.to)
        var saved: Triple<VForm, VForm, Boolean>? = null
        val p = PracticeModel(
            lesson1,
            MapStages(),
            persistPair = { f, t, x -> saved = Triple(f, t, x) },
            random = Random(1)
        )
        p.setPair(VForm.Translation, VForm.Kana, mixed = true)
        assertEquals(Triple(VForm.Translation, VForm.Kana, true), saved)
        assertTrue(p.mixed)
    }

    @Test
    fun aStoredHalfPairFallsBackToTheDefault() {
        val m = PracticeModel(lesson1, MapStages(), VForm.Translation, VForm.Translation, random = Random(1))
        assertEquals(VForm.Kana, m.from)
        assertEquals(VForm.Translation, m.to)
        assertEquals(VForm.Kanji, PracticeModel.face("kanji"))
        assertEquals(null, PracticeModel.face("romaji"))
    }

    @Test
    fun aDistractorDiffersFromTheAnswerOnBothFaces() {
        val random = Random(3)
        for (answer in store.allVocab().take(300)) {
            val opts = PracticeModel.options(answer, store.allVocab(), VForm.Kana, VForm.Translation, random)
            assertEquals(2, opts.size)
            val other = opts.first { it.id != answer.id }
            assertNotEquals(answer.kana, other.kana)
            assertNotEquals(answer.translation, other.translation)
        }
    }

    @Test
    fun aSingleWordPoolStillDealsAOneOptionCard() {
        val only = lesson1.take(1)
        assertEquals(1, PracticeModel.options(only[0], only).size)
    }

    @Test
    fun audioSafetyFollowsTheWholePair() {
        assertFalse(VForm.promptAudioSafe(VForm.Translation))
        assertTrue(VForm.promptAudioSafe(VForm.Kana, VForm.Translation))
        assertFalse(VForm.promptAudioSafe(VForm.Translation, VForm.Kana))
        // Kanji -> kana: hearing the word would read the answer out loud.
        assertFalse(VForm.promptAudioSafe(VForm.Kanji, VForm.Kana))
        assertTrue(VForm.promptAudioSafe(VForm.Audio, VForm.Kana))
        assertTrue(VForm.isJapaneseFaces())
    }

    private fun VForm.Companion.isJapaneseFaces() =
        VForm.Kana.isJapanese && VForm.Kanji.isJapanese && !VForm.Romaji.isJapanese && !VForm.Translation.isJapanese

    // endregion

    @Test
    fun heroEstimateRoundsUpAndReviewsAWholeLesson() {
        assertEquals(1 to 1, heroEstimate(PracticeProgress.Counts(0, 0, 1), 1))
        assertEquals(7 to 20, heroEstimate(PracticeProgress.Counts(5, 5, 15), 25))
        // Fully memorised: the whole lesson again, as review.
        assertEquals(9 to 25, heroEstimate(PracticeProgress.Counts(25, 0, 0), 25))
    }

    @Test
    fun practiceNeverWritesAnythingButStages() {
        // The model's only side effects are StageStore.set calls and the pair callback.
        val stages = MapStages()
        val m = model(stages)
        m.answer(true)
        assertEquals(1, stages.map.size)
    }
}
