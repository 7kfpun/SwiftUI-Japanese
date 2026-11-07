package com.kfpun.japanesedaily.data.progress

import java.time.DateTimeException
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Day stamps for the streak (port of `StudyDay`). A day is an integer `yyyymmdd`, not an instant:
 * a stamp written once never moves when the phone changes time zone.
 *
 * The numbering is **always ISO/Gregorian** ([LocalDate] is, whatever the default locale's
 * calendar) and the day boundaries are the **user's own time zone**. Never `Calendar.getInstance()`
 * or `DateFormat`, which follow the region: under a Thai Buddhist calendar today's year is 2569
 * and every stored stamp would be reinterpreted.
 */
object StudyDay {
    /** The user's time zone. Replaced in tests; always read fresh so a zone change is honoured. */
    @Volatile
    var zoneProvider: () -> ZoneId = { ZoneId.systemDefault() }

    /** `yyyymmdd` for [at] on the user's day boundaries. */
    fun stamp(at: Instant = Instant.now(), zone: ZoneId = zoneProvider()): Int {
        val d = at.atZone(zone).toLocalDate()
        return d.year * 10_000 + d.monthValue * 100 + d.dayOfMonth
    }

    /**
     * The stamp [days] after [stamp] (negative for before), walked through the calendar rather than
     * by arithmetic: 20260301 minus one is not 20260228 in a leap year.
     */
    fun offset(stamp: Int, days: Int): Int = try {
        val moved = LocalDate.of(stamp / 10_000, (stamp / 100) % 100, stamp % 100).plusDays(days.toLong())
        moved.year * 10_000 + moved.monthValue * 100 + moved.dayOfMonth
    } catch (_: DateTimeException) {
        stamp
    }
}

/**
 * The streak, computed from the set of studied days. A value over a set rather than a stored
 * counter: a counter has to be maintained at every write across merges, and gets it wrong once.
 */
class Streak(val days: Set<Int>, val today: Int = StudyDay.stamp()) {
    val studiedToday: Boolean = today in days

    /** Consecutive days ending today, or ending yesterday while today is still open. */
    val current: Int

    /** Longest run ever, including the current one. */
    val best: Int

    init {
        var run = 0
        var cursor = if (studiedToday) today else StudyDay.offset(today, -1)
        while (cursor in days) {
            run++
            cursor = StudyDay.offset(cursor, -1)
        }
        current = run

        var longest = 0
        for (day in days) {
            if (StudyDay.offset(day, -1) in days) continue
            var length = 0
            var next = day
            while (next in days) {
                length++
                next = StudyDay.offset(next, 1)
            }
            longest = maxOf(longest, length)
        }
        best = maxOf(longest, current)
    }

    /** A live streak with today still open: the only state where the number can fall by doing nothing. */
    val atRisk: Boolean get() = current > 0 && !studiedToday

    /** How many more days would beat the record, or null once the current run is the record. */
    val toBeatBest: Int? get() = if (current < best) best - current + 1 else null

    /** Time left to keep the streak (to local midnight), or null when nothing is at stake. */
    fun timeLeft(now: Instant = Instant.now(), zone: ZoneId = StudyDay.zoneProvider()): Duration? {
        if (!atRisk) return null
        val midnight = now.atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant()
        return Duration.between(now, midnight).coerceAtLeast(Duration.ZERO)
    }

    /** The last seven days, oldest first, each with whether it was studied. */
    fun lastWeek(): List<Pair<Int, Boolean>> = (6 downTo 0).map { offset ->
        val stamp = StudyDay.offset(today, -offset)
        stamp to (stamp in days)
    }

    override fun equals(other: Any?): Boolean = other is Streak && other.days == days && other.today == today

    override fun hashCode(): Int = 31 * days.hashCode() + today
}
