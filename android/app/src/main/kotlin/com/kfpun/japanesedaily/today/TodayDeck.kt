package com.kfpun.japanesedaily.today

import com.kfpun.japanesedaily.data.Course
import com.kfpun.japanesedaily.data.progress.ChallengeResult
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.ladder.Challenge

/** The deck Today deals: the lesson, the rung it prepares for and whether that rung is still to be taken. */
data class TodayDeal(
    val lesson: Int,
    /** The rung these cards prepare for (the lesson's last rung when everything is passed). */
    val upNext: Int,
    /** False once every rung of every lesson is passed: the deck is then the last rung kept as review. */
    val hasNext: Boolean,
    val words: List<Vocab>
)

/**
 * Today's deck as a function of progress (port of `TodayView.studyLesson` / `loadPicks`): the next unpassed rung
 * of the first lesson that still holds one, walking lessons 1 to the last. The pool rules are the ladder's own
 * ([Challenge.pool]); nothing here re-implements them. Nothing is persisted and nothing is paywalled: it is a
 * pure read of the results, so it can always be recomputed and never drifts.
 */
object TodayDeck {
    /**
     * The lesson Today studies: the first one still holding an unpassed challenge. Deliberately not capped at
     * the free lesson ceiling: Today is a reading surface, not a graded one.
     *
     * [wordCount] rather than the lesson's entries: it is 0 for a lesson the data lacks, which the ladder still
     * counts as one rung (`Challenge.count(0) == 1`, as on iOS), so that lesson deals an empty deck instead of failing.
     * Once everything is cleared the last lesson stays, as review.
     */
    fun studyLesson(
        results: Collection<ChallengeResult>,
        wordCount: (Int) -> Int,
        course: Course = Course.current
    ): Int {
        val passed = results.filter { it.isPassed }.groupBy { it.lesson }.mapValues { (_, rows) ->
            rows.map { it.index }.toSet()
        }
        for (lesson in 1..course.lessonCount) {
            val total = Challenge.count(wordCount(lesson))
            if ((passed[lesson]?.size ?: 0) < total) return lesson
        }
        return course.lessonCount
    }

    /** The deal for [lesson], given its [entries] and the results of every lesson. */
    fun deal(lesson: Int, entries: List<Vocab>, results: Collection<ChallengeResult>): TodayDeal {
        val total = Challenge.count(entries.size)
        val byIndex = results.filter { it.lesson == lesson }.associateBy { it.index }
        val next = ChallengeResult.firstUnpassed(total, byIndex)
        val rung = next ?: total
        return TodayDeal(lesson, rung, next != null, Challenge.pool(entries, rung))
    }

    /** Both steps: which lesson, then its deal. [entries] is only asked for the chosen lesson. */
    fun derive(
        results: Collection<ChallengeResult>,
        wordCount: (Int) -> Int,
        entries: (Int) -> List<Vocab>,
        course: Course = Course.current
    ): TodayDeal {
        val lesson = studyLesson(results, wordCount, course)
        return deal(lesson, entries(lesson), results)
    }

    /** The widget's wire format for a [deal]. */
    fun snapshot(deal: TodayDeal): TodayShared.Snapshot = TodayShared.Snapshot(
        lesson = deal.lesson,
        words = deal.words.map { TodayShared.Word(it.kana, it.kanji, it.romaji, it.translation) },
        challenge = deal.upNext
    )
}
