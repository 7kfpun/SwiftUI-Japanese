package com.kfpun.japanesedaily.progress

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.kfpun.japanesedaily.data.progress.Bookmark
import com.kfpun.japanesedaily.data.progress.ChallengeResult
import com.kfpun.japanesedaily.data.progress.KanaResult
import com.kfpun.japanesedaily.data.progress.ProgressDatabase
import com.kfpun.japanesedaily.data.progress.ProgressRepository
import com.kfpun.japanesedaily.data.progress.Streak
import com.kfpun.japanesedaily.data.progress.StudyDay
import com.kfpun.japanesedaily.data.trackStudyDay
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.KanaData
import com.kfpun.japanesedaily.data.vocab.VocabStore
import java.io.File
import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The numbers on the Progress tab, derived from stored rows (iOS `StatsView`), and the streak rules behind them. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ProgressStatsTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val resources = File("../../nihongo/Resources")
    private val vocab = VocabStore(FileAssetSource(resources))
    private lateinit var db: ProgressDatabase
    private var now = Instant.parse("2026-08-11T03:00:00Z")
    private val defaultLocale = Locale.getDefault()

    @Before
    fun setUp() {
        StudyDay.zoneProvider = { ZoneId.of("Asia/Tokyo") }
        db = Room.inMemoryDatabaseBuilder(context, ProgressDatabase::class.java).allowMainThreadQueries().build()
    }

    @After
    fun tearDown() {
        db.close()
        StudyDay.zoneProvider = { ZoneId.systemDefault() }
        Locale.setDefault(defaultLocale)
    }

    private fun repo() = ProgressRepository(db, vocab, clock = { now })

    private suspend fun stats(): ProgressStats {
        val r = repo()
        return ProgressStats.from(
            r.observeStudyDays().first(),
            r.observeChallenges().first().values,
            r.observeKana().first().values,
            r.observeBookmarks().first(),
            StudyDay.stamp(now),
            challengesTotal = 10,
            kanaTotal = 71
        )
    }

    @Test
    fun anEmptyDatabaseShowsTheEmptyStateAndNoInventedNumbers() = runTest {
        val s = stats()
        assertTrue(s.isEmpty)
        assertEquals(0, s.streak.current)
        assertEquals(0, s.challengesPassed)
        assertEquals(0, s.kanaLearned)
        assertEquals(0, s.bookmarkCount)
    }

    @Test
    fun statsMatchWhatWasStored() = runTest {
        val r = repo()
        r.recordChallenge(1, 1, 90) // passed, two stars? stars follow the score
        r.recordChallenge(1, 2, 50) // attempted, not passed
        r.recordChallenge(1, 1, 60) // a worse replay never lowers the pass
        r.recordKana("a", true)
        r.recordKana("i", false)
        r.recordKana("i", true)
        r.recordKana("u", true)
        r.recordKana("u", false) // latest wins: u is no longer learned
        r.setBookmark(2, vocab.lesson(1, "en").entries.first())

        val s = stats()
        assertFalse(s.isEmpty)
        assertEquals(1, s.daysStudied)
        assertEquals(1, s.challengesPassed)
        assertEquals(2, s.kanaLearned)
        assertEquals(1, s.bookmarkCount)
        assertEquals(1, s.streak.current)
        assertTrue(s.streak.studiedToday)
    }

    @Test
    fun duplicateRowsFromAMergeNeverInflateTheCounts() {
        val a = ChallengeResult(1, 1, bestScore = 90, stars = 2, attempts = 1, completedAt = 5)
        val b = ChallengeResult(1, 1, bestScore = 50, stars = 0, attempts = 1)
        val s = ProgressStats.from(
            studyDays = listOf(20260810, 20260810, 20260811),
            challenges = listOf(a, b),
            kana = listOf(KanaResult("a", false, 1), KanaResult("a", true, 2), KanaResult("i", true, 1)),
            bookmarks = listOf(Bookmark("w", 1, 2, 1), Bookmark("w", 1, 3, 9)),
            today = 20260811,
            challengesTotal = 4,
            kanaTotal = 6
        )
        assertEquals(2, s.daysStudied)
        assertEquals(1, s.challengesPassed)
        assertEquals(2, s.kanaLearned)
        assertEquals(1, s.bookmarkCount)
    }

    @Test
    fun totalsAreCountedFromTheBundledData() {
        val k = KanaData(FileAssetSource(resources))
        val expected = (k.seion + k.dakuon + k.youon).flatten().filter { !it.isEmpty }.map { it.romaji }.toSet().size
        assertEquals(expected, ProgressStats.kanaTotal(listOf(k.seion, k.dakuon, k.youon)))
        assertTrue(expected > 40)
    }

    @Test
    fun streakCrossesMidnightInTheUsersZone() = runTest {
        // 23:50 and 00:10 Tokyo are one run, two days, though only twenty minutes apart.
        now = Instant.parse("2026-08-11T14:50:00Z")
        repo().recordKana("a", true)
        now = Instant.parse("2026-08-11T15:10:00Z")
        repo().recordKana("i", true)
        val s = stats()
        assertEquals(2, s.daysStudied)
        assertEquals(2, s.streak.current)
        assertEquals(20260812, s.streak.today)
    }

    @Test
    fun theStreakSurvivesATimeZoneChange() = runTest {
        repo().recordKana("a", true) // 12:00 on the 11th in Tokyo
        now = Instant.parse("2026-08-12T03:00:00Z")
        repo().recordKana("i", true)
        assertEquals(2, stats().streak.current)

        // Fly to Los Angeles: stored days are untouched integers, and "today" is the new local day.
        StudyDay.zoneProvider = { ZoneId.of("America/Los_Angeles") }
        val s = stats()
        assertEquals(2, s.daysStudied)
        assertEquals(20260811, s.streak.today) // 20:00 on the 11th in LA
        assertEquals(2, s.streak.best)
        // Today (the 11th) is stored, so the run ending today is the one-day tail, and the record keeps both.
        assertTrue(s.streak.studiedToday)
    }

    @Test
    fun theStreakSurvivesABuddhistCalendarLocale() = runTest {
        Locale.setDefault(Locale.forLanguageTag("th-TH-u-ca-buddhist"))
        StudyDay.zoneProvider = { ZoneId.of("Asia/Bangkok") }
        repo().recordKana("a", true)
        now = Instant.parse("2026-08-12T03:00:00Z")
        repo().recordKana("i", true)
        val s = stats()
        // Numbered 2026, never 2569: the stored stamps and the streak are unchanged by the region.
        assertEquals(setOf(20260811, 20260812), s.streak.days)
        assertEquals(2, s.streak.current)
        assertEquals(20260812, s.streak.today)
    }

    @Test
    fun browsingNeverCreatesAStudyDay() = runTest {
        repo().setBookmark(1, vocab.lesson(1, "en").entries.first()) // a bookmark is not an answer
        repo().setBookmark(null, vocab.lesson(1, "en").entries.first())
        assertTrue(stats().isEmpty)
    }

    @Test
    fun theCalendarGridEndsOnTheCurrentWeekAndLeavesTheFutureBlank() {
        // 2026-08-12 is a Wednesday; weeks start Monday, so three days (Mon-Wed) of the last column exist.
        val columns = StudyCalendar.columns(20260812, DayOfWeek.MONDAY)
        assertEquals(StudyCalendar.WEEKS, columns.size)
        assertTrue(columns.all { it.size == 7 })
        assertEquals(20260812, columns.last()[2])
        assertEquals(listOf<Int?>(null, null, null, null), columns.last().drop(3))
        assertEquals(20260810, columns.last()[0])
        assertEquals(20260525, columns.first()[0]) // eleven weeks earlier
        // Sunday-first puts today in the third column cell of a different week alignment.
        val sunday = StudyCalendar.columns(20260812, DayOfWeek.SUNDAY)
        assertEquals(20260812, sunday.last()[3])
    }

    @Test
    fun theCalendarCountsOnlyStudiedDaysInsideTheGrid() {
        val columns = StudyCalendar.columns(20260812, DayOfWeek.MONDAY)
        val days = setOf(20260812, 20260810, 20250101)
        assertEquals(2, StudyCalendar.studiedIn(columns, days))
    }

    @Test
    fun theCalendarWalksMonthEndsAndLeapYears() {
        val columns = StudyCalendar.columns(20240301, DayOfWeek.MONDAY).flatten().filterNotNull()
        assertTrue(20240229 in columns)
        assertEquals(columns.sorted(), columns)
        assertEquals(columns.size, columns.toSet().size)
    }

    @Test
    fun theCountdownSplitsIntoHoursAndMinutes() {
        assertEquals(5 to 12, hoursAndMinutes(Duration.ofMinutes(5 * 60 + 12)))
        assertEquals(0 to 7, hoursAndMinutes(Duration.ofSeconds(7 * 60 + 59)))
        assertEquals(0 to 0, hoursAndMinutes(Duration.ofSeconds(-5)))
    }

    @Test
    fun studyDayIsLoggedWithTheStreakAndTheBest() {
        var sent: Pair<String, Map<String, Any?>>? = null
        trackStudyDay(Streak(setOf(20260810, 20260811), 20260811)) { name, params -> sent = name to params }
        assertEquals("study_day", sent?.first)
        assertEquals(mapOf<String, Any?>("streak" to 2, "best" to 2), sent?.second)
    }

    @Test
    fun theFirstAnswerOfADayReportsStudyDayOnceAndLaterAnswersDoNot() = runTest {
        val sent = mutableListOf<Streak>()
        val r = ProgressRepository(db, vocab, clock = { now }, onFirstAnswerToday = { sent += it })
        r.recordKana("a", true)
        r.recordKana("i", true)
        r.recordChallenge(1, 1, 90)
        assertEquals(1, sent.size)
        assertEquals(1, sent.single().current)
        now = Instant.parse("2026-08-12T03:00:00Z")
        r.recordKana("u", true)
        assertEquals(2, sent.size)
        assertEquals(2, sent.last().current)
    }
}
