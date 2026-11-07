package com.kfpun.japanesedaily.lessons

import com.kfpun.japanesedaily.data.Course
import com.kfpun.japanesedaily.data.progress.ChallengeResult
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.VocabStore
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of the iOS `GatingTests` and `UnlockTests`: the lesson gate is pure and exactly as on iOS. */
class GatingTest {
    private val store = VocabStore(FileAssetSource(File("../../nihongo/Resources")))

    @Test
    fun firstFiveLessonsAreFreeAndTheRestLockedByDefault() {
        assertEquals(5, Gating.freeLessonLimit())
        for (n in 1..5) assertFalse(Gating.isLocked(n, isPremium = false))
        for (n in 6..50) assertTrue("lesson $n", Gating.isLocked(n, isPremium = false))
    }

    @Test
    fun premiumUnlocksEverything() {
        for (n in 1..50) assertFalse(Gating.isLocked(n, isPremium = true))
    }

    @Test
    fun theEarnedBandRunsToTheEndOfBeginning1AndNoFurther() {
        assertEquals(13, Gating.earnableGroup()?.last)
        assertEquals(13, Gating.freeThrough(earnedFirstGroup = true))
        assertEquals(5, Gating.freeThrough(earnedFirstGroup = false))
        assertFalse(Gating.isLocked(13, isPremium = false, earnedFirstGroup = true))
        assertTrue(Gating.isLocked(14, isPremium = false, earnedFirstGroup = true))
    }

    @Test
    fun anUnPlumbedCallerFailsClosed() {
        // earnedFirstGroup defaults to false: a lock a tap can clear, never an unearned open lesson.
        assertTrue(Gating.isLocked(6, isPremium = false))
        assertTrue(Gating.isLocked(13, isPremium = false))
    }

    @Test
    fun earningNeverTakesLessonsAway() {
        val tiny = Course.Minna.copy(freeLessonLimit = 20)
        assertEquals(20, Gating.freeThrough(earnedFirstGroup = true, course = tiny))
    }

    @Test
    fun earnedNeedsThreeStarsOnEveryRungOfEveryFreeLesson() {
        val rungs = (1..5).associateWith { 3 }
        val all = (1..5).associateWith { 3 }
        assertTrue(Gating.hasEarnedFirstGroup(rungs, all))
        assertFalse(Gating.hasEarnedFirstGroup(rungs, all + (5 to 2)))
        assertFalse(Gating.hasEarnedFirstGroup(rungs, all - 3))
    }

    @Test
    fun aLessonWithNoKnownRungCountIsNotMastered() {
        val all = (1..5).associateWith { 3 }
        assertFalse(Gating.hasEarnedFirstGroup((1..4).associateWith { 3 }, all))
        assertFalse(Gating.hasEarnedFirstGroup((1..5).associateWith { if (it == 2) 0 else 3 }, all))
        assertFalse(Gating.hasEarnedFirstGroup(emptyMap(), emptyMap()))
    }

    @Test
    fun readAlongPreviewsMeaningsForEveryoneWhoHasNotSubscribed() {
        assertEquals(7, Gating.FREE_MEANING_PREVIEW)
        assertEquals(7, Gating.wordsToRead(ReadMode.WithMeaning, 40, isPremium = false))
        assertEquals(7, Gating.wordsToRead(ReadMode.WithExample, 40, isPremium = false))
        assertEquals(40, Gating.wordsToRead(ReadMode.WithMeaning, 40, isPremium = true))
        // Japanese only is free in full, on every lesson.
        assertEquals(40, Gating.wordsToRead(ReadMode.Japanese, 40, isPremium = false))
        // A short cut is read whole rather than padded.
        assertEquals(3, Gating.wordsToRead(ReadMode.WithMeaning, 3, isPremium = false))
    }

    @Test
    fun previewStopsShortOfEveryLesson() {
        // Otherwise a "preview" would read the whole lesson and then charge for it.
        for (lesson in store.lessons()) {
            assertTrue("lesson ${lesson.number}", Gating.FREE_MEANING_PREVIEW < lesson.entries.size)
        }
    }

    @Test
    fun theSpeedDialIsRememberedButNotHonouredWithoutPro() {
        assertEquals(1.0, Gating.rate(1.5, isPremium = false), 0.0)
        assertEquals(1.2, Gating.rate(1.2, isPremium = true), 0.0)
        assertEquals(1.0, Gating.NORMAL_RATE, 0.0)
    }

    @Test
    fun onlySubscribersLoop() {
        for (mode in ReadMode.entries) {
            assertFalse(Gating.loopsForever(mode, isPremium = false))
            assertTrue(Gating.loopsForever(mode, isPremium = true))
        }
    }

    @Test
    fun readModesKnowWhatTheyReadBeyondTheWord() {
        assertFalse(ReadMode.Japanese.readsBeyondTheWord)
        assertTrue(ReadMode.WithMeaning.readsBeyondTheWord)
        assertTrue(ReadMode.WithExample.readsBeyondTheWord)
    }

    // region LessonStanding (the iOS Unlock tallies)

    private fun result(lesson: Int, index: Int, stars: Int, passed: Boolean = stars > 0) =
        ChallengeResult(lesson, index, bestScore = stars * 30, stars = stars, completedAt = if (passed) 1L else null)

    @Test
    fun standingTalliesPassedAndSweptPerLesson() {
        val rows = listOf(result(1, 1, 3), result(1, 2, 1), result(2, 1, 3), result(3, 1, 0))
        assertEquals(mapOf(1 to 2, 2 to 1), LessonStanding.passedByLesson(rows))
        assertEquals(mapOf(1 to 1, 2 to 1), LessonStanding.threeStarredByLesson(rows))
    }

    @Test
    fun sweepingEveryFreeRungEarnsTheBand() {
        val rungs = LessonStanding.rungs(store::wordCount)
        assertEquals(5, rungs.size)
        val sweep = rungs.flatMap { (lesson, n) -> (1..n).map { result(lesson, it, 3) } }
        assertTrue(LessonStanding.earnedFirstGroup(sweep, store::wordCount))
        assertFalse(LessonStanding.earnedFirstGroup(sweep.drop(1), store::wordCount))
        val (swept, total) = LessonStanding.firstGroupProgress(sweep.drop(1), store::wordCount)
        assertEquals(total - 1, swept)
    }

    @Test
    fun continueLessonIsTheFirstWithAnUnpassedRung() {
        val wc = store::wordCount
        assertEquals(1, LessonStanding.continueLesson(emptyMap(), wc))
        val passedLesson1 = mapOf(1 to com.kfpun.japanesedaily.data.progress.LadderRules.count(wc(1)))
        assertEquals(2, LessonStanding.continueLesson(passedLesson1, wc))
        val all = (1..50).associateWith { com.kfpun.japanesedaily.data.progress.LadderRules.count(wc(it)) }
        assertNull(LessonStanding.continueLesson(all, wc))
    }

    @Test
    fun retryTargetIsTheFewestStarsThenTheLaterRung() {
        val r = listOf(result(1, 1, 2), result(1, 2, 1), result(1, 3, 1), result(1, 4, 3))
            .associateBy { it.index }
        assertEquals(3, LessonStanding.retryTarget(r))
        assertNull(LessonStanding.retryTarget(mapOf(1 to result(1, 1, 3))))
        assertNull(LessonStanding.retryTarget(emptyMap()))
    }

    @Test
    fun nextIndexIsTheFirstUnlockedUnpassedRung() {
        val r = mapOf(1 to result(1, 1, 3), 2 to result(1, 2, 1))
        assertEquals(3, LessonStanding.nextIndex(5, r))
        assertEquals(1, LessonStanding.nextIndex(5, emptyMap()))
        assertNull(LessonStanding.nextIndex(2, r))
    }

    // endregion
}
