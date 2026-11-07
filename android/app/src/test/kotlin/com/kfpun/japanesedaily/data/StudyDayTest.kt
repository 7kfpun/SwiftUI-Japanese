package com.kfpun.japanesedaily.data

import com.kfpun.japanesedaily.data.progress.Streak
import com.kfpun.japanesedaily.data.progress.StudyDay
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.chrono.ThaiBuddhistDate
import java.time.temporal.ChronoField
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Ports of the iOS streak and `StudyDay` tests, plus the Buddhist-calendar and time-zone cases. */
class StudyDayTest {
    private val savedLocale = Locale.getDefault()
    private val savedZone = StudyDay.zoneProvider

    @Before
    fun fixZone() {
        StudyDay.zoneProvider = { ZoneId.of("Asia/Tokyo") }
    }

    @After
    fun restore() {
        Locale.setDefault(savedLocale)
        StudyDay.zoneProvider = savedZone
    }

    private fun at(zone: String, y: Int, m: Int, d: Int, h: Int = 12, min: Int = 0): Instant =
        LocalDateTime.of(y, m, d, h, min).atZone(ZoneId.of(zone)).toInstant()

    @Test
    fun streakCountsBackFromTodayAndSurvivesAnOpenDay() {
        val today = 20260811
        fun back(n: Int) = StudyDay.offset(today, -n)

        assertEquals(0, Streak(emptySet(), today).current)

        val done = Streak(setOf(back(0), back(1), back(2)), today)
        assertEquals(3, done.current)
        assertTrue(done.studiedToday)

        // Today unstudied: the streak is alive (it breaks on a missed day, not an unfinished one).
        val open = Streak(setOf(back(1), back(2), back(3)), today)
        assertEquals(3, open.current)
        assertFalse(open.studiedToday)

        assertEquals(1, Streak(setOf(back(0), back(2), back(3)), today).current)

        val past = Streak(setOf(back(0), back(10), back(11), back(12), back(13)), today)
        assertEquals(1, past.current)
        assertEquals(4, past.best)
    }

    @Test
    fun streakAppliesPressureOnlyWhenSomethingIsAtRisk() {
        val today = 20260811
        fun back(n: Int) = StudyDay.offset(today, -n)

        assertFalse(Streak(emptySet(), today).atRisk)
        assertFalse(Streak(setOf(back(0), back(1)), today).atRisk)
        assertTrue(Streak(setOf(back(1), back(2)), today).atRisk)

        assertNull(Streak(setOf(back(0), back(1), back(2)), today).toBeatBest)
        val behind = Streak(setOf(back(0), back(10), back(11), back(12)), today)
        assertEquals(1, behind.current)
        assertEquals(3, behind.best)
        assertEquals(3, behind.toBeatBest)

        val week = Streak(setOf(back(0), back(3)), today).lastWeek()
        assertEquals(7, week.size)
        assertEquals(today, week.last().first)
        assertEquals(listOf(false, false, false, true, false, false, true), week.map { it.second })
    }

    @Test
    fun countdownRunsToLocalMidnightAndOnlyWhenAtRisk() {
        val zone = ZoneId.of("Asia/Tokyo")
        val now = at("Asia/Tokyo", 2026, 8, 11, 21, 30)
        val today = StudyDay.stamp(now, zone)
        fun back(n: Int) = StudyDay.offset(today, -n)

        assertNull(Streak(emptySet(), today).timeLeft(now, zone))
        assertNull(Streak(setOf(back(0)), today).timeLeft(now, zone))
        assertEquals(Duration.ofMinutes(150), Streak(setOf(back(1)), today).timeLeft(now, zone)) // 21:30 -> 00:00
    }

    @Test
    fun stampsCrossMonthAndYearBoundaries() {
        assertEquals(20260228, StudyDay.offset(20260301, -1)) // 2026 is not a leap year
        assertEquals(20240229, StudyDay.offset(20240301, -1)) // 2024 is
        assertEquals(20251231, StudyDay.offset(20260101, -1))
        assertEquals(20260101, StudyDay.offset(20251231, 1))
        assertEquals(4, Streak(setOf(20251230, 20251231, 20260101, 20260102), 20260102).current)
    }

    @Test
    fun stampsStayGregorianUnderABuddhistCalendar() {
        // A Thai device: the default locale's calendar numbers today as 2569 BE.
        Locale.setDefault(Locale.forLanguageTag("th-TH-u-ca-buddhist"))
        val instant = at("Asia/Bangkok", 2026, 8, 11)
        val bangkok = ZoneId.of("Asia/Bangkok")
        val calendar = Calendar.getInstance(TimeZone.getTimeZone(bangkok)).apply { time = Date.from(instant) }
        assertEquals(2569, calendar.get(Calendar.YEAR))
        assertEquals(2569, ThaiBuddhistDate.from(instant.atZone(bangkok)).get(ChronoField.YEAR))

        // The stamp is untouched by it.
        assertEquals(20260811, StudyDay.stamp(instant, ZoneId.of("Asia/Bangkok")))
        // Leap years still follow Gregorian numbering: the case that caught this on a simulator.
        assertEquals(20240229, StudyDay.offset(20240301, -1))
        assertEquals(20260811, StudyDay.offset(20260812, -1))
    }

    @Test
    fun theDayBoundaryFollowsTheUsersTimeZone() {
        // The same instant is a different day on either side of the date line.
        val instant = at("Asia/Tokyo", 2026, 8, 11, 7, 0) // 22:00 on the 10th in UTC, 15:00 on the 10th in LA
        assertEquals(20260811, StudyDay.stamp(instant, ZoneId.of("Asia/Tokyo")))
        assertEquals(20260810, StudyDay.stamp(instant, ZoneId.of("America/Los_Angeles")))
    }

    @Test
    fun changingTimeZoneNeverRewritesStampsAlreadyWritten() {
        // Written in Tokyo, then the phone flies to Los Angeles.
        val written = StudyDay.stamp(at("Asia/Tokyo", 2026, 8, 11, 7, 0))
        assertEquals(20260811, written)

        StudyDay.zoneProvider = { ZoneId.of("America/Los_Angeles") }
        // A stamp is an integer, so the stored day is unmoved; only new stamps use the new zone.
        assertEquals(20260811, written)
        val sameMoment = StudyDay.stamp(at("Asia/Tokyo", 2026, 8, 11, 7, 0))
        assertNotEquals(written, sameMoment)
        // Flying east to west makes the old stamp a "future" day: it is kept (the record survives in
        // `best`) rather than rewritten, and the run still ends on the new local today.
        val streak = Streak(setOf(written, sameMoment), sameMoment)
        assertEquals(2, streak.best)
        assertEquals(1, streak.current)
        // The next local day, in the new zone, then continues the run without a gap.
        val next = StudyDay.stamp(at("America/Los_Angeles", 2026, 8, 12))
        assertEquals(3, Streak(setOf(written, sameMoment, next), next).current)
    }
}
