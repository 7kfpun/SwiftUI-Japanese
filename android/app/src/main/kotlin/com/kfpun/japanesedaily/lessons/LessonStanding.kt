package com.kfpun.japanesedaily.lessons

import com.kfpun.japanesedaily.data.Course
import com.kfpun.japanesedaily.data.progress.ChallengeResult
import com.kfpun.japanesedaily.data.progress.LadderRules

/**
 * Pure tallies over the persisted challenge results, shared by the lesson list rows and the lesson
 * screen (the iOS `reloadProgress` / `Unlock`). One pass over one collapsed result set, so the row bars,
 * the summary line and the lock all agree.
 */
object LessonStanding {
    /** Challenges passed per lesson. */
    fun passedByLesson(results: Collection<ChallengeResult>): Map<Int, Int> =
        results.filter { it.isPassed }.groupingBy { it.lesson }.eachCount()

    /** Three-starred challenges per lesson. */
    fun threeStarredByLesson(results: Collection<ChallengeResult>): Map<Int, Int> =
        results.filter { it.stars >= 3 }.groupingBy { it.lesson }.eachCount()

    /** Rungs per lesson of the free lessons, from the data's word counts. */
    fun rungs(wordCount: (Int) -> Int, course: Course = Course.current): Map<Int, Int> =
        (1..course.freeLessonLimit).associateWith { LadderRules.count(wordCount(it)) }

    /** Whether the first band has been earned: three stars on every rung of the free lessons. */
    fun earnedFirstGroup(
        results: Collection<ChallengeResult>,
        wordCount: (Int) -> Int,
        course: Course = Course.current
    ): Boolean = Gating.hasEarnedFirstGroup(rungs(wordCount, course), threeStarredByLesson(results), course)

    /** (three-starred, total) over the free lessons: the earn hint's progress line. */
    fun firstGroupProgress(
        results: Collection<ChallengeResult>,
        wordCount: (Int) -> Int,
        course: Course = Course.current
    ): Pair<Int, Int> {
        val total = rungs(wordCount, course).values.sum()
        val swept = threeStarredByLesson(results).filterKeys { it <= course.freeLessonLimit }.values.sum()
        return swept to total
    }

    /**
     * The first lesson still holding an unpassed challenge: the "Up next" card. Null once everything is
     * passed: there is nowhere to continue *to*.
     */
    fun continueLesson(passed: Map<Int, Int>, wordCount: (Int) -> Int, course: Course = Course.current): Int? =
        (1..course.lessonCount).firstOrNull { (passed[it] ?: 0) < LadderRules.count(wordCount(it)) }

    /** The passed rung most worth another run: fewest stars first, later rung on a tie. Null once all are 3 stars. */
    fun retryTarget(results: Map<Int, ChallengeResult>): Int? = results.values
        .filter { it.isPassed && it.stars < 3 }
        .sortedWith(compareBy({ it.stars }, { -it.index }))
        .firstOrNull()?.index

    /** The first rung that is unlocked but not yet passed: the ladder's "next up". */
    fun nextIndex(count: Int, results: Map<Int, ChallengeResult>): Int? = (1..count).firstOrNull {
        ChallengeResult.isUnlocked(it, results) && results[it]?.isPassed != true
    }
}
