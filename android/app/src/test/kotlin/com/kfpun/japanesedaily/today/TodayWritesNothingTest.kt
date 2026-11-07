package com.kfpun.japanesedaily.today

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.kfpun.japanesedaily.data.progress.ProgressDatabase
import com.kfpun.japanesedaily.data.progress.ProgressRepository
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.VocabStore
import java.io.File
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Today is a reading surface: dealing the deck, publishing the widget's snapshot and reading it back write no
 * Practice stage, no challenge result, no Kana result, no bookmark and no streak day.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TodayWritesNothingTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val store = VocabStore(FileAssetSource(File("../../nihongo/Resources")))
    private lateinit var db: ProgressDatabase
    private lateinit var repo: ProgressRepository

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, ProgressDatabase::class.java).allowMainThreadQueries().build()
        repo = ProgressRepository(db, store)
    }

    @After
    fun tearDown() = db.close()

    private suspend fun rowCounts() = listOf(
        db.challenges().all().size,
        db.kana().all().size,
        db.studyDays().all().size,
        db.bookmarks().all().size,
        db.practice().all().size
    )

    @Test
    fun dealingAndPublishingTheDeckWritesNoProgress() = runBlocking {
        // A learner with some real progress, written the way the ladder writes it.
        repo.recordChallenge(1, 1, 90)
        repo.recordChallenge(1, 2, 100)
        val before = rowCounts()
        assertEquals(listOf(2, 0, 1, 0, 0), before)

        val results = repo.observeChallenges().first()
        val deal = TodayDeck.derive(results.values, store::wordCount, { store.lesson(it, "en").entries })
        assertEquals(3, deal.upNext)
        TodayWidgetUpdater.publish(context, TodayDeck.snapshot(deal))
        assertEquals(deal.words.size, TodayWidgetUpdater.read(context)!!.words.size)

        assertEquals(before, rowCounts())
        assertTrue(repo.streak().days.size == 1)
    }

    @Test
    fun aFreshInstallStaysEmptyAfterToday() = runBlocking {
        val results = repo.observeChallenges().first()
        TodayDeck.derive(results.values, store::wordCount, { store.lesson(it, "en").entries })
        assertEquals(listOf(0, 0, 0, 0, 0), rowCounts())
    }
}
