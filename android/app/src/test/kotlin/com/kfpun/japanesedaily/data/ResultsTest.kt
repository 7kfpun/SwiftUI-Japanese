package com.kfpun.japanesedaily.data

import com.kfpun.japanesedaily.data.progress.Bookmark
import com.kfpun.japanesedaily.data.progress.ChallengeResult
import com.kfpun.japanesedaily.data.progress.KanaResult
import com.kfpun.japanesedaily.data.progress.LadderRules
import com.kfpun.japanesedaily.data.progress.WordStage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** The merge resolvers and ladder arithmetic: pure, so no database is involved. */
class ResultsTest {
    private fun result(score: Int, completedAt: Long? = null, attempts: Int = 1, index: Int = 1) =
        ChallengeResult(1, index, score, LadderRules.stars(score), attempts, completedAt)

    @Test
    fun betterPrefersTheHigherScore() {
        val low = result(70, completedAt = 1)
        val high = result(90, completedAt = 9)
        assertSame(high, ChallengeResult.better(low, high))
        assertSame(high, ChallengeResult.better(high, low))
    }

    @Test
    fun betterPrefersTheEarlierFirstPassOnATie() {
        val early = result(90, completedAt = 100)
        val late = result(90, completedAt = 200)
        assertSame(early, ChallengeResult.better(late, early))
        assertSame(early, ChallengeResult.better(early, late))
    }

    @Test
    fun betterPrefersAPassedRowOverAnUnpassedOneAtTheSameScore() {
        val passed = result(50, completedAt = 5)
        val unpassed = result(50, completedAt = null)
        assertSame(passed, ChallengeResult.better(unpassed, passed))
        assertSame(passed, ChallengeResult.better(passed, unpassed))
    }

    @Test
    fun betterFallsBackToAttemptsThenTheFirstArgument() {
        val few = result(40, attempts = 2)
        val many = result(40, attempts = 5)
        assertSame(many, ChallengeResult.better(few, many))
        assertSame(many, ChallengeResult.better(many, few))
        val a = result(40, attempts = 3)
        val b = result(40, attempts = 3)
        assertSame(a, ChallengeResult.better(a, b))
    }

    @Test
    fun betterIsOrderIndependentAndNeverInventsProgress() {
        val rows = listOf(result(70, null, 4), result(90, 300, 1), result(90, 200, 2), result(60, 100, 9))
        val forward = rows.reduce(ChallengeResult::better)
        val backward = rows.reversed().reduce(ChallengeResult::better)
        assertEquals(forward, backward)
        assertEquals(90, forward.bestScore)
        assertEquals(200L, forward.completedAt)
    }

    @Test
    fun collapseKeepsTheStrongestRowPerChallenge() {
        val rows = listOf(result(70, index = 1), result(100, 1, index = 1), result(60, index = 2))
        val out = ChallengeResult.collapse(rows)
        assertEquals(2, out.size)
        assertEquals(100, out.getValue("1/1").bestScore)
        assertEquals(60, out.getValue("1/2").bestScore)
    }

    @Test
    fun unlockingIsSequential() {
        val none = emptyMap<Int, ChallengeResult>()
        assertTrue(ChallengeResult.isUnlocked(1, none))
        assertTrue(!ChallengeResult.isUnlocked(2, none))
        val failedFirst = mapOf(1 to result(50, index = 1))
        assertTrue(!ChallengeResult.isUnlocked(2, failedFirst))
        val passedFirst = mapOf(1 to result(80, 1, index = 1))
        assertTrue(ChallengeResult.isUnlocked(2, passedFirst))
        assertTrue(!ChallengeResult.isUnlocked(3, passedFirst))
        assertEquals(1, ChallengeResult.passedCount(passedFirst))
    }

    @Test
    fun firstUnpassedTracksTheLadder() {
        assertEquals(1, ChallengeResult.firstUnpassed(3, emptyMap()))
        val partial = mapOf(1 to result(90, 1, index = 1), 2 to result(50, index = 2))
        assertEquals(2, ChallengeResult.firstUnpassed(3, partial))
        val cleared = (1..3).associateWith { result(100, 1, index = it) }
        assertNull(ChallengeResult.firstUnpassed(3, cleared))
        assertNull(ChallengeResult.firstUnpassed(0, cleared))
    }

    @Test
    fun starsAndPassBar() {
        assertEquals(0, LadderRules.stars(79))
        assertEquals(1, LadderRules.stars(80))
        assertEquals(1, LadderRules.stars(89))
        assertEquals(2, LadderRules.stars(90))
        assertEquals(2, LadderRules.stars(99))
        assertEquals(3, LadderRules.stars(100))
    }

    @Test
    fun ladderStepsCoverEveryWordAndKeepReviewSlots() {
        for (words in 1..70) {
            val steps = LadderRules.steps(words)
            assertEquals("words $words", words, steps.sum())
            assertTrue(steps.drop(1).all { it <= 8 })
        }
        // Lesson 22's 20 words must not become 10 + 10: that rung would leave no review slots.
        assertEquals(listOf(10, 5, 5), LadderRules.steps(20))
        assertEquals(1, LadderRules.count(0))
        assertEquals(1, LadderRules.count(10))
    }

    @Test
    fun kanaLatestTimestampWins() {
        val out = KanaResult.latest(
            listOf(KanaResult("a", true, 10), KanaResult("a", false, 20), KanaResult("ka", true, 5))
        )
        assertEquals(false, out.getValue("a").isCorrect)
        assertEquals(20L, out.getValue("a").timestamp)
        assertEquals(2, out.size)
    }

    @Test
    fun bookmarksCollapseToTheNewestAndClampStars() {
        val out = Bookmark.collapse(
            listOf(
                Bookmark("1/a", 1, 1, 100),
                Bookmark("1/a", 1, 3, 200),
                Bookmark("1/b", 1, 9, 50),
                Bookmark("2/c", 2, 0, 300)
            )
        )
        assertEquals(listOf("2/c", "1/a", "1/b"), out.map { it.word })
        assertEquals(3, out[1].stars)
        assertEquals(3, out[2].stars) // 9 files under the nearest tier
        assertEquals(1, out[0].stars) // 0 files under the nearest tier
    }

    @Test
    fun bookmarkTiersCycle() {
        assertEquals(1, Bookmark.next(null))
        assertEquals(2, Bookmark.next(1))
        assertEquals(3, Bookmark.next(2))
        assertNull(Bookmark.next(3))
    }

    @Test
    fun alienStagesClampIntoTheLadder() {
        assertEquals(WordStage.Memorized, WordStage.fromRaw(7))
        assertEquals(WordStage.Unseen, WordStage.fromRaw(-2))
        assertEquals(WordStage.Recognized, WordStage.fromRaw(2))
    }
}
