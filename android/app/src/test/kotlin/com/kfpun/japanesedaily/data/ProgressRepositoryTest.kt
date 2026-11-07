package com.kfpun.japanesedaily.data

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.prefs.Prefs
import com.kfpun.japanesedaily.data.progress.ChallengeResultRow
import com.kfpun.japanesedaily.data.progress.KanaResultRow
import com.kfpun.japanesedaily.data.progress.LadderRules
import com.kfpun.japanesedaily.data.progress.PracticeProgress
import com.kfpun.japanesedaily.data.progress.ProgressDatabase
import com.kfpun.japanesedaily.data.progress.ProgressRepository
import com.kfpun.japanesedaily.data.progress.Streak
import com.kfpun.japanesedaily.data.progress.StudyDay
import com.kfpun.japanesedaily.data.progress.StudyDayRow
import com.kfpun.japanesedaily.data.progress.WordStage
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.VocabStore
import java.io.File
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Ports of `ChallengeResultTests`, the KanaResult and `PracticeProgress` tests, run against a real
 * Room database (Robolectric) so SQL, transactions and "survives a restart" are exercised for real.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@OptIn(ExperimentalCoroutinesApi::class)
class ProgressRepositoryTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val vocab = VocabStore(FileAssetSource(File("../../nihongo/Resources")))
    private lateinit var db: ProgressDatabase
    private var now = Instant.parse("2026-08-11T03:00:00Z")
    private val firstAnswers = mutableListOf<Streak>()
    private lateinit var repo: ProgressRepository

    @Before
    fun setUp() {
        StudyDay.zoneProvider = { ZoneId.of("Asia/Tokyo") }
        db = Room.inMemoryDatabaseBuilder(context, ProgressDatabase::class.java)
            .allowMainThreadQueries().build()
        repo = ProgressRepository(db, vocab, clock = { now }, onFirstAnswerToday = { firstAnswers += it })
    }

    @After
    fun tearDown() {
        db.close()
        StudyDay.zoneProvider = { ZoneId.systemDefault() }
    }

    private suspend fun rows() = db.challenges().all()

    @Test
    fun keepsBestScoreAcrossAttempts() = runTest {
        repo.recordChallenge(1, 1, 60)
        repo.recordChallenge(1, 1, 90)
        repo.recordChallenge(1, 1, 70)

        val stored = rows()
        assertEquals(1, stored.size)
        assertEquals(3, stored[0].attempts)
        assertEquals(90, stored[0].bestScore)
        assertEquals(2, stored[0].stars)
        assertNotNull(stored[0].completedAt)
    }

    @Test
    fun failingRecordsTheAttemptButDoesNotComplete() = runTest {
        val row = repo.recordChallenge(2, 1, LadderRules.PASS_SCORE - 1)
        assertEquals(1, row.attempts)
        assertFalse(row.isPassed)
        assertEquals(0, row.stars)
    }

    @Test
    fun completionTimestampIsStable() = runTest {
        val first = repo.recordChallenge(3, 1, 80)
        assertNotNull(first.completedAt)
        now = now.plusSeconds(3600)
        val again = repo.recordChallenge(3, 1, 100)
        assertEquals(first.completedAt, again.completedAt)
        assertEquals(100, again.bestScore)
    }

    @Test
    fun unlockingFollowsPasses() = runTest {
        repo.recordChallenge(4, 1, 50)
        assertEquals(0, repo.challengesByIndex(4).values.count { it.isPassed })
        repo.recordChallenge(4, 1, 80)
        assertEquals(1, repo.challengesByIndex(4).values.count { it.isPassed })
    }

    @Test
    fun previousLessonGatesTheNextLadder() = runTest {
        assertTrue(repo.previousLessonCleared(1))
        val total = LadderRules.count(vocab.wordCount(1))
        for (i in 1 until total) repo.recordChallenge(1, i, 100)
        assertFalse(repo.previousLessonCleared(2))
        // The last rung merely passed (not three-starred) opens it.
        repo.recordChallenge(1, total, LadderRules.PASS_SCORE)
        assertTrue(repo.previousLessonCleared(2))
    }

    @Test
    fun duplicateRowsCollapseToTheStrongestAndRecordUpdatesIt() = runTest {
        // A merge left two rows for lesson 9 / challenge 1.
        db.challenges().insert(
            ChallengeResultRow(
                key = "9/1",
                lesson = 9,
                idx = 1,
                bestScore = 70,
                stars = 0,
                attempts = 4,
                completedAt = null
            )
        )
        db.challenges().insert(
            ChallengeResultRow(
                key = "9/1",
                lesson = 9,
                idx = 1,
                bestScore = 90,
                stars = 2,
                attempts = 1,
                completedAt = 5
            )
        )

        assertEquals(90, repo.challengesByIndex(9).getValue(1).bestScore)
        assertEquals(1, repo.totalPassed()) // deduped by id: the weaker twin cannot inflate it

        repo.recordChallenge(9, 1, 100)
        val stored = rows()
        assertEquals(2, stored.size) // no third row, and the weaker twin is untouched
        assertEquals(100, stored.first { it.attempts == 2 }.bestScore)
        assertEquals(70, stored.first { it.attempts == 4 }.bestScore)
    }

    @Test
    fun totalPassedCountsOnlyPassedRungsOnce() = runTest {
        repo.recordChallenge(1, 1, 90)
        repo.recordChallenge(1, 1, 100)
        repo.recordChallenge(1, 2, 50)
        assertEquals(1, repo.totalPassed())
    }

    @Test
    fun earnedFirstGroupNeedsThreeStarsOnEveryFreeRung() = runTest {
        assertFalse(repo.hasEarnedFirstGroup())
        val limit = Course.current.freeLessonLimit
        var total = 0
        for (lesson in 1..limit) {
            val rungs = LadderRules.count(vocab.wordCount(lesson))
            total += rungs
            for (i in 1..rungs) repo.recordChallenge(lesson, i, 100)
        }
        assertTrue(repo.hasEarnedFirstGroup())
        assertEquals(total to total, repo.firstGroupProgress())

        // A duplicate twin with fewer stars cannot undo it.
        db.challenges().insert(
            ChallengeResultRow(
                key = "1/1",
                lesson = 1,
                idx = 1,
                bestScore = 80,
                stars = 1,
                attempts = 1,
                completedAt = 1
            )
        )
        assertTrue(repo.hasEarnedFirstGroup())
    }

    @Test
    fun oneRungShortOfThreeStarsEarnsNothing() = runTest {
        val limit = Course.current.freeLessonLimit
        for (lesson in 1..limit) {
            val rungs = LadderRules.count(vocab.wordCount(lesson))
            for (i in 1..rungs) repo.recordChallenge(lesson, i, if (lesson == limit && i == rungs) 90 else 100)
        }
        assertFalse(repo.hasEarnedFirstGroup())
    }

    @Test
    fun kanaUpsertsLatestAndCountsTowardTheStreak() = runTest {
        repo.recordKana("a", true)
        now = now.plusSeconds(60)
        repo.recordKana("a", false)

        assertEquals(1, db.kana().all().size)
        assertFalse(repo.kanaResults().getValue("a").isCorrect)
        assertTrue(repo.streak().studiedToday)
    }

    @Test
    fun kanaDuplicatesResolveByTimestamp() = runTest {
        db.kana().insert(KanaResultRow(romaji = "ka", isCorrect = true, timestamp = 10))
        db.kana().insert(KanaResultRow(romaji = "ka", isCorrect = false, timestamp = 20))
        assertFalse(repo.kanaResults().getValue("ka").isCorrect)
        repo.recordKana("ka", true)
        // The newest duplicate is the one updated.
        assertEquals(2, db.kana().all().size)
        assertTrue(repo.kanaResults().getValue("ka").isCorrect)
    }

    @Test
    fun answeringStampsTodayOnceAndCountsAnswers() = runTest {
        repo.recordChallenge(1, 1, 50)
        repo.recordKana("a", true)
        repo.recordChallenge(1, 1, 60)

        val days = db.studyDays().all()
        assertEquals(1, days.size)
        assertEquals(20260811, days[0].day) // 03:00 UTC is noon in Tokyo
        assertEquals(3, days[0].answers)
        assertEquals(1, firstAnswers.size) // the study_day hook fires on the day's first answer only
        assertEquals(1, firstAnswers[0].current)
    }

    @Test
    fun duplicateStudyDayRowsBumpTheLargestAndDoNotSum() = runTest {
        db.studyDays().insert(StudyDayRow(day = 20260811, answers = 2))
        db.studyDays().insert(StudyDayRow(day = 20260811, answers = 5))
        repo.recordKana("a", true)
        assertEquals(listOf(2, 6), db.studyDays().all().map { it.answers }.sorted())
        assertEquals(1, repo.streak().current)
        assertTrue(firstAnswers.isEmpty()) // not the day's first answer
    }

    @Test
    fun theStreakFollowsTheDayAcrossAMidnightInTheUsersZone() = runTest {
        repo.recordKana("a", true) // 12:00 Tokyo on the 11th
        now = Instant.parse("2026-08-11T15:30:00Z") // 00:30 Tokyo on the 12th
        assertEquals(1, repo.streak().current)
        assertTrue(repo.streak().atRisk)
        repo.recordKana("a", true)
        assertEquals(2, repo.streak().current)
        assertFalse(repo.streak().atRisk)
    }

    @Test
    fun bookmarksFileClearAndNeverResurrect() = runTest {
        val word = vocab.lesson(1).entries.first()
        assertNull(repo.bookmarkStars(word.id))

        repo.setBookmark(1, word)
        now = now.plusSeconds(10)
        repo.setBookmark(3, word)
        assertEquals(3, repo.bookmarkStars(word.id))
        assertEquals(1, repo.bookmarks().size)

        repo.setBookmark(null, word)
        assertNull(repo.bookmarkStars(word.id))
        assertTrue(repo.bookmarks().isEmpty())
    }

    @Test
    fun clearingABookmarkRemovesEveryDuplicateRow() = runTest {
        val word = vocab.lesson(1).entries.first()
        db.bookmarks().insert(
            com.kfpun.japanesedaily.data.progress.BookmarkRow(word = word.id, lesson = 1, stars = 1, savedAt = 1)
        )
        db.bookmarks().insert(
            com.kfpun.japanesedaily.data.progress.BookmarkRow(word = word.id, lesson = 1, stars = 2, savedAt = 2)
        )
        assertEquals(1, repo.bookmarks().size)
        repo.setBookmark(null, word)
        assertTrue(db.bookmarks().all().isEmpty())
    }

    @Test
    fun observedStreakFollowsWrites() = runTest {
        assertEquals(0, repo.observeStreak().first().current)
        repo.recordKana("a", true)
        assertEquals(1, repo.observeStreak().first().current)
    }

    @Test
    fun practiceStagesPersistAcrossReload() = runTest {
        val scope = CoroutineScope(UnconfinedTestDispatcher(testScheduler))
        val store = PracticeProgress(db.practice(), scope)
        store.set(WordStage.Recognized, "1/watashi")
        store.set(WordStage.Memorized, "1/anata")
        store.flush()

        val reloaded = PracticeProgress(db.practice(), scope).also { it.load() }
        assertEquals(WordStage.Recognized, reloaded.stage("1/watashi"))
        assertEquals(WordStage.Memorized, reloaded.stage("1/anata"))
        assertEquals(WordStage.Unseen, reloaded.stage("1/never-practiced"))
    }

    @Test
    fun unseenRemovesTheRow() = runTest {
        val scope = CoroutineScope(UnconfinedTestDispatcher(testScheduler))
        val store = PracticeProgress(db.practice(), scope)
        store.set(WordStage.Seen, "1/word")
        store.set(WordStage.Unseen, "1/word")
        store.flush()
        assertNull(store.snapshot()["1/word"])
        assertTrue(db.practice().all().isEmpty())
    }

    @Test
    fun countsFoldSeenIntoUnseen() = runTest {
        val scope = CoroutineScope(UnconfinedTestDispatcher(testScheduler))
        val store = PracticeProgress(db.practice(), scope)
        val entries = vocab.lesson(1).entries
        store.set(WordStage.Memorized, entries[0].id)
        store.set(WordStage.Recognized, entries[1].id)
        store.set(WordStage.Seen, entries[2].id)
        val counts = store.counts(entries)
        assertEquals(1, counts.memorized)
        assertEquals(1, counts.recognized)
        assertEquals(entries.size - 2, counts.unseen)
    }

    @Test
    fun progressSurvivesReopeningTheDatabaseFile() = runTest {
        // An app restart (or update) is a process death and a reopen of the same file.
        val first = Room.databaseBuilder(context, ProgressDatabase::class.java, "restart-test.db")
            .allowMainThreadQueries().build()
        val r1 = ProgressRepository(first, vocab, clock = { now })
        r1.recordChallenge(5, 2, 100)
        r1.recordKana("shi", true)
        r1.setBookmark(2, vocab.lesson(5).entries.first())
        first.close()

        val second = Room.databaseBuilder(context, ProgressDatabase::class.java, "restart-test.db")
            .allowMainThreadQueries().build()
        val r2 = ProgressRepository(second, vocab, clock = { now })
        assertEquals(100, r2.challengesByIndex(5).getValue(2).bestScore)
        assertTrue(r2.kanaResults().getValue("shi").isCorrect)
        assertEquals(1, r2.bookmarks().size)
        assertEquals(1, r2.streak().current)
        second.close()
        context.deleteDatabase("restart-test.db")
    }

    @Test
    fun prefsDefaultPersistAndSurviveAReopen() = runTest {
        val file = File(tmp.root, "prefs.preferences_pb")
        val scope = CoroutineScope(UnconfinedTestDispatcher(testScheduler))
        val prefs = Prefs(PreferenceDataStoreFactory.create(scope = scope) { file })
        assertTrue(prefs.get(Pref.soundOn))
        assertEquals(1.0, prefs.get(Pref.playbackRate), 0.0)
        assertEquals("vi", prefs.translationLanguage("vi").first()) // unset follows the device default

        prefs.set(Pref.soundOn, false)
        prefs.set(Pref.playbackRate, 1.5)
        prefs.setTranslationLanguage("de")
        prefs.markModeVisit(3, "practice")
        prefs.markModeVisit(3, "practice")
        prefs.markModeVisit(4, "match")

        assertFalse(prefs.get(Pref.soundOn))
        assertEquals("de", prefs.translationLanguage("vi").first())
        assertEquals(setOf("practice"), prefs.modeVisits(3))
        assertEquals(setOf("match"), prefs.modeVisits(4))
        assertTrue(prefs.modeVisits(5).isEmpty())
        assertTrue(file.isFile)
    }
}
