package com.kfpun.japanesedaily.ladder

import com.kfpun.japanesedaily.data.Course
import com.kfpun.japanesedaily.data.progress.ChallengeResult
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.data.vocab.VocabStore
import com.kfpun.japanesedaily.lessons.Gating
import com.kfpun.japanesedaily.lessons.LessonStanding
import com.kfpun.japanesedaily.lessons.VForm
import java.io.File
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ports of the iOS `ChallengeTests` (sizing, window, forms, questions, scoring) and the earned-unlock rule. */
class ChallengeModelTest {
    private val store = VocabStore(FileAssetSource(File("../../nihongo/Resources")))
    private fun words(lesson: Int): List<Vocab> = store.lesson(lesson, "en").entries
    private val lessons = (1..50)

    @Test
    fun everyRungIsWellSized() {
        for (n in lessons) {
            val w = words(n)
            val steps = Challenge.steps(w.size)
            assertEquals("lesson $n sum", w.size, steps.sum())
            assertEquals(Challenge.QUESTIONS_PER_CHALLENGE.coerceAtMost(w.size), steps[0])
            for (size in steps.drop(1)) {
                assertTrue("lesson $n rung of $size", size >= 3)
                assertTrue(size <= Challenge.QUESTIONS_PER_CHALLENGE - Challenge.MIN_REVIEW_SLOTS)
            }
            for (i in 2..steps.size) assertTrue(Challenge.pool(w, i).size >= Challenge.QUESTIONS_PER_CHALLENGE)
        }
        // Lesson 22 is the edge case: an unguarded even split gives [10, 10] and no review at all.
        assertEquals(listOf(10, 5, 5), Challenge.steps(20))
    }

    @Test
    fun poolIsASlidingWindow() {
        val w = words(40)
        val steps = Challenge.steps(w.size)
        assertTrue(steps.size > Challenge.REVIEW_WINDOW)
        for (i in 1..steps.size) {
            val expected = steps.subList(maxOf(0, i - Challenge.REVIEW_WINDOW), i).sum()
            assertEquals(expected, Challenge.pool(w, i).size)
            assertEquals(steps[i - 1], Challenge.newWords(w, i).size)
        }
        assertTrue(Challenge.pool(w, steps.size).size < w.size)
    }

    @Test
    fun everyWordIsIntroducedExactlyOnce() {
        for (n in lessons) {
            val w = words(n)
            val introduced = (1..Challenge.count(w.size)).flatMap { Challenge.newWords(w, it).map { v -> v.id } }
            assertEquals(w.map { it.id }, introduced)
        }
    }

    @Test
    fun formsHardenAcrossTheLadder() {
        for (n in lessons) {
            val total = Challenge.count(words(n).size)
            assertEquals(1, Challenge.forms(1, total).size)
            assertFalse(Challenge.forms(1, total).any { it.from == VForm.Audio })
            val single = (1..total).filter { Challenge.forms(it, total).size == 1 }
            assertEquals(listOf(1), single)
            for (i in 2..total) assertTrue(Challenge.forms(i, total).any { it.to == VForm.Kana })
            if (total >= 3) assertTrue(Challenge.forms(3, total).any { it.from == VForm.Audio })
        }
    }

    @Test
    fun challengesMixPromptDirections() {
        for (n in lessons) {
            val w = words(n)
            val total = Challenge.count(w.size)
            for (i in 2..total) {
                val model = ChallengeModel(n, i, total, w, Random(i * 31 + n))
                assertTrue("$n/$i", model.questions.map { it.from to it.to }.toSet().size >= 2)
            }
        }
    }

    @Test
    fun generatedQuestionsAreAnswerable() {
        for (n in lessons) {
            val w = words(n)
            val total = Challenge.count(w.size)
            for (i in 1..total) {
                val model = ChallengeModel(n, i, total, w, Random(n * 100 + i))
                val pool = Challenge.pool(w, i)
                assertEquals(minOf(Challenge.QUESTIONS_PER_CHALLENGE, pool.size), model.questions.size)
                for (q in model.questions) {
                    assertTrue(q.options.any { it.id == q.answer.id })
                    assertTrue("${q.options.size} options", q.options.size in 2..4)
                    if (pool.size >= 6) assertTrue(q.options.size >= 3)
                    val labels = q.options.map { q.to.value(it) }
                    assertEquals(labels.size, labels.toSet().size)
                    val prompt = q.from.value(q.answer)
                    assertTrue(q.options.all { it.id == q.answer.id || q.from.value(it) != prompt })
                    assertTrue(
                        Challenge.supports(q.answer, q.from, q.to) ||
                            (q.from == VForm.Kana && q.to == VForm.Translation)
                    )
                    assertTrue(pool.any { it.id == q.answer.id })
                }
            }
        }
    }

    @Test
    fun newWordsAreAlwaysAsked() {
        for (n in listOf(1, 11, 22)) {
            val w = words(n)
            val total = Challenge.count(w.size)
            for (i in 1..total) {
                val asked = ChallengeModel(n, i, total, w, Random(i)).questions.map { it.answer.id }.toSet()
                val new = Challenge.newWords(w, i)
                if (new.size <= Challenge.QUESTIONS_PER_CHALLENGE) assertTrue(new.all { it.id in asked })
            }
        }
    }

    @Test
    fun theAlternateVoiceIsRolledAcrossAListeningRung() {
        val w = words(1)
        val voices = (1..20).flatMap { seed ->
            ChallengeModel(1, 3, Challenge.count(w.size), w, Random(seed)).questions
        }
            .map { it.voice }.toSet()
        assertEquals(2, voices.size)
    }

    @Test
    fun scoringAndFlow() {
        val w = words(1)
        val total = Challenge.count(w.size)
        val perfect = ChallengeModel(1, 1, total, w, Random(1))
        while (true) {
            val q = perfect.question ?: break
            val right = q.options.indexOfFirst { it.id == q.answer.id }
            perfect.advance() // nothing picked yet: no skipping
            assertEquals(q.id, perfect.question?.id)
            perfect.choose(right)
            perfect.choose((right + 1) % q.options.size) // a second pick is ignored
            perfect.advance()
        }
        assertTrue(perfect.isDone)
        assertEquals(100, perfect.scorePercent)
        assertTrue(perfect.passed)
        assertEquals(3, perfect.stars)
        assertTrue(perfect.missed.isEmpty())

        val failed = ChallengeModel(1, 1, total, w, Random(2))
        val count = failed.questions.size
        while (true) {
            val q = failed.question ?: break
            failed.choose(q.options.indexOfFirst { it.id != q.answer.id })
            failed.advance()
        }
        assertEquals(0, failed.scorePercent)
        assertFalse(failed.passed)
        assertEquals(0, failed.stars)
        assertEquals(count, failed.missed.size)
    }

    @Test
    fun passMarkAndStarBandsOnATenQuestionRun() {
        val w = words(1)
        fun run(wrong: Int): ChallengeModel {
            val m = ChallengeModel(1, 1, Challenge.count(w.size), w, Random(wrong))
            var misses = 0
            while (true) {
                val q = m.question ?: break
                if (misses < wrong) {
                    m.choose(q.options.indexOfFirst { it.id != q.answer.id })
                    misses++
                } else {
                    m.choose(q.options.indexOfFirst { it.id == q.answer.id })
                }
                m.advance()
            }
            return m
        }
        assertEquals(listOf(3, 2, 1, 0), listOf(0, 1, 2, 3).map { run(it).stars })
        assertTrue(run(2).passed)
        assertFalse(run(3).passed)
    }

    @Test
    fun cheerNeverRepeatsBackToBackAndHoldsPerfectForCleanSweeps() {
        assertEquals(Cheer.Tier.Perfect, Cheer.tier(3, true))
        assertEquals(Cheer.Tier.Passed, Cheer.tier(2, true))
        assertEquals(Cheer.Tier.Missed, Cheer.tier(0, false))
        var last: Cheer? = null
        repeat(50) {
            val next = Cheer.pick(Cheer.perfect, last)!!
            assertNotEquals(last, next)
            last = next
        }
        assertNotNull(Cheer.next(1, true))
    }

    // region The earned unlock

    private fun result(lesson: Int, index: Int, stars: Int) = ChallengeResult(
        lesson,
        index,
        bestScore = if (stars == 3) 100 else 80,
        stars = stars,
        attempts = 1,
        completedAt = 1L
    )

    private fun threeStarEverything(lessonRange: IntRange, skip: Pair<Int, Int>? = null): List<ChallengeResult> =
        lessonRange.flatMap { l ->
            (1..Challenge.count(store.wordCount(l))).filter { l to it != skip }.map { result(l, it, 3) }
        }

    @Test
    fun threeStarsEverywhereInLessons1To5UnlocksSixThroughThirteenAndNothingPast() {
        val results = threeStarEverything(1..5)
        val earned = LessonStanding.earnedFirstGroup(results, store::wordCount)
        assertTrue(earned)
        for (n in 1..13) assertFalse("lesson $n", Gating.isLocked(n, isPremium = false, earnedFirstGroup = earned))
        for (n in 14..50) assertTrue("lesson $n", Gating.isLocked(n, isPremium = false, earnedFirstGroup = earned))
        assertEquals(13, Course.current.groups.first().last)
    }

    @Test
    fun oneMissingStarKeepsTheBandShutAndAPassIsNotEnough() {
        val missingOne = threeStarEverything(1..5, skip = 3 to 1) + result(3, 1, 2)
        assertFalse(LessonStanding.earnedFirstGroup(missingOne, store::wordCount))
        val onlyPassed = (1..5).flatMap { l -> (1..Challenge.count(store.wordCount(l))).map { result(l, it, 1) } }
        assertFalse(LessonStanding.earnedFirstGroup(onlyPassed, store::wordCount))
        assertTrue(Gating.isLocked(6, isPremium = false)) // an un-plumbed caller fails closed
    }

    // endregion
}
