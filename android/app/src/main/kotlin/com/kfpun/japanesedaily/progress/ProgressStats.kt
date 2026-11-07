package com.kfpun.japanesedaily.progress

import com.kfpun.japanesedaily.data.progress.Bookmark
import com.kfpun.japanesedaily.data.progress.ChallengeResult
import com.kfpun.japanesedaily.data.progress.KanaResult
import com.kfpun.japanesedaily.data.progress.Streak
import com.kfpun.japanesedaily.data.progress.StudyDay
import com.kfpun.japanesedaily.data.vocab.K
import java.time.DayOfWeek
import java.time.Duration
import java.time.LocalDate

/**
 * What the learner has actually done (port of iOS `StatsView`'s numbers). Every figure is **derived from
 * stored rows**, never kept as a running total: a counter has to be right at every write and across merges,
 * and derived numbers were true retroactively the day they shipped. Nothing here is seeded or invented.
 */
data class ProgressStats(
    val streak: Streak,
    val daysStudied: Int,
    val challengesPassed: Int,
    val challengesTotal: Int,
    val kanaLearned: Int,
    val kanaTotal: Int,
    val bookmarkCount: Int
) {
    /** Nothing answered yet: the empty state replaces the streak and the tiles, never Bookmarks. */
    val isEmpty: Boolean get() = daysStudied == 0

    companion object {
        /**
         * [studyDays] and the row lists may hold duplicates from a later merge, so each is collapsed the way
         * iOS does: days by `Set` (counting rows would report more days than the calendar holds), challenges
         * by id through [ChallengeResult.better], kana to the latest row per romaji, bookmarks per word.
         */
        fun from(
            studyDays: Collection<Int>,
            challenges: Collection<ChallengeResult>,
            kana: Collection<KanaResult>,
            bookmarks: Collection<Bookmark>,
            today: Int,
            challengesTotal: Int,
            kanaTotal: Int
        ): ProgressStats {
            val days = studyDays.toSet()
            return ProgressStats(
                streak = Streak(days, today),
                daysStudied = days.size,
                challengesPassed = ChallengeResult.collapse(challenges).values.count { it.isPassed },
                challengesTotal = challengesTotal,
                kanaLearned = KanaResult.latest(kana).values.count { it.isCorrect },
                kanaTotal = kanaTotal,
                bookmarkCount = Bookmark.collapse(bookmarks).size
            )
        }

        /** Distinct kana cells in the chart, counted rather than hardcoded: the chart is generated. */
        fun kanaTotal(chart: List<List<List<K>>>): Int =
            chart.flatMap { group -> group.flatten() }.filter { !it.isEmpty }.map { it.romaji }.toSet().size
    }
}

/** Twelve weeks of study days, a column per week, the current week last (iOS `StudyCalendar`). */
object StudyCalendar {
    const val WEEKS = 12

    /**
     * Columns of seven stamps, oldest week first, laid out on [firstDayOfWeek]; `null` for days still to come.
     * Built from the Gregorian stamps ([StudyDay.offset]), so it can never disagree with the streak above it.
     */
    fun columns(today: Int, firstDayOfWeek: DayOfWeek): List<List<Int?>> {
        val todayDate = LocalDate.of(today / 10_000, (today / 100) % 100, today % 100)
        val intoWeek = (todayDate.dayOfWeek.value - firstDayOfWeek.value + 7) % 7
        val first = StudyDay.offset(today, -((WEEKS - 1) * 7 + intoWeek))
        return (0 until WEEKS).map { week ->
            (0 until 7).map { day ->
                val offset = week * 7 + day
                if (offset > (WEEKS - 1) * 7 + intoWeek) null else StudyDay.offset(first, offset)
            }
        }
    }

    /** Studied days inside the grid, the "N days" beside the title. */
    fun studiedIn(columns: List<List<Int?>>, days: Set<Int>): Int = columns.flatten().count { it != null && it in days }

    /** The weekday of a stamp, for the week strip's letters. */
    fun dayOfWeek(stamp: Int): DayOfWeek = LocalDate.of(stamp / 10_000, (stamp / 100) % 100, stamp % 100).dayOfWeek
}

/** "5h 12m" as whole hours and minutes, dropping a leading zero hour; zero stays 0 minutes. */
fun hoursAndMinutes(left: Duration): Pair<Int, Int> {
    val minutes = left.toMinutes().coerceAtLeast(0)
    return (minutes / 60).toInt() to (minutes % 60).toInt()
}
