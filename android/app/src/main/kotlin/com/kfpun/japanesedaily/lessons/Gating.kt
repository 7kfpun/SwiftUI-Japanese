package com.kfpun.japanesedaily.lessons

import com.kfpun.japanesedaily.audio.PlaybackRates
import com.kfpun.japanesedaily.data.Course

/** How much of each word Read along reads out (port of `ReadMode`). */
enum class ReadMode(val key: String) {
    /** The Japanese only: free for everyone. */
    Japanese("japanese"),

    /** Japanese, then the meaning in the learner's own language. Premium. */
    WithMeaning("withMeaning"),

    /** Japanese, the meaning, the example sentence, then its meaning. Premium, and the longest. */
    WithExample("withExample");

    /**
     * Whether this mode reads anything beyond the word itself. The gate is on *that*, not on the
     * specific mode: a fourth mode reading something else would still be paid.
     */
    val readsBeyondTheWord: Boolean get() = this != Japanese
}

/**
 * Lesson gating as pure rules (port of iOS `Gating`, `Store/Store.swift`). Nothing here reads a
 * store or the billing library, so every rule is unit-tested; callers pass `isPremium` in.
 *
 * Lessons `1..freeLessonLimit` are free in full, plus two documented ways past that and no others:
 * the **earned** first band ([hasEarnedFirstGroup]) and Read along's **previewed** meanings
 * ([wordsToRead]). Vocab List is free on every lesson.
 */
object Gating {
    /** How many words "Japanese + meaning" reads before the paywall. Must stay below every lesson's size. */
    const val FREE_MEANING_PREVIEW = 7

    /** The Read along speed that is not premium. */
    const val NORMAL_RATE = 1.0

    /** The highest lesson playable without paying and without earning anything. */
    fun freeLessonLimit(course: Course = Course.current): Int = course.freeLessonLimit

    /**
     * The band earned by mastering the free lessons: Minna's "Beginning 1" (to lesson 13). Always the
     * first group: the reward has to be the stretch that *follows* the free lessons.
     */
    fun earnableGroup(course: Course = Course.current): Course.Group? = course.groups.firstOrNull()

    /**
     * Three stars on every challenge of lessons `1..freeLessonLimit`. Three stars, not merely passed:
     * the ladder already needs a pass to advance, so passing would be no bar at all. [rungs] is how many
     * challenges each lesson has; [threeStarred] how many of them are cleanly swept.
     */
    fun hasEarnedFirstGroup(
        rungs: Map<Int, Int>,
        threeStarred: Map<Int, Int>,
        course: Course = Course.current
    ): Boolean {
        if (course.freeLessonLimit < 1) return false
        return (1..course.freeLessonLimit).all { lesson ->
            // A lesson with no known rung count has only failed to be measured, not been mastered.
            val total = rungs[lesson]
            total != null && total > 0 && (threeStarred[lesson] ?: 0) == total
        }
    }

    /** The highest lesson playable without paying. */
    fun freeThrough(earnedFirstGroup: Boolean, course: Course = Course.current): Int {
        val band = earnableGroup(course)
        if (!earnedFirstGroup || band == null) return course.freeLessonLimit
        // `max`: earning the band must never take lessons away.
        return maxOf(course.freeLessonLimit, band.last)
    }

    /**
     * Read along's speed: the stored preference is remembered, not honoured, for a lapsed subscriber.
     * 1x for everyone, the stored rate for Pro.
     */
    fun rate(stored: Double, isPremium: Boolean): Double = PlaybackRates.effective(stored, isPremium)

    /**
     * True when a lesson needs premium (everything but Vocab List). [earnedFirstGroup] defaults to false
     * so a caller that has not looked it up fails *closed*: a lock a tap can clear.
     */
    fun isLocked(
        lesson: Int,
        isPremium: Boolean,
        earnedFirstGroup: Boolean = false,
        course: Course = Course.current
    ): Boolean = !isPremium && lesson > freeThrough(earnedFirstGroup, course)

    /**
     * How many of a lesson's [count] words Read along reads: the whole lesson, except the meanings modes
     * without premium, which get [FREE_MEANING_PREVIEW]. Premium, not lesson-locked: the same paid feature
     * must not behave differently by lesson.
     */
    fun wordsToRead(mode: ReadMode, count: Int, isPremium: Boolean): Int =
        if (!mode.readsBeyondTheWord || isPremium) count else minOf(FREE_MEANING_PREVIEW, count)

    /** Whether Read along may start over at the top and keep going: subscribers only, in every mode. */
    @Suppress("UNUSED_PARAMETER")
    fun loopsForever(mode: ReadMode, isPremium: Boolean): Boolean = isPremium
}
