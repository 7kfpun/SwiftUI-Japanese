package com.kfpun.japanesedaily.rating

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.prefs.Prefs
import java.io.File
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Port of the iOS `RatingPrompt` tests: the threshold, the two-month window and the star routing. */
@OptIn(ExperimentalCoroutinesApi::class)
class RatingPromptTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val now = Instant.parse("2026-11-07T10:00:00Z")

    @Test
    fun asksOnlyAfterTheTwentyFirstPassedRung() {
        assertEquals(21, RatingPrompt.CHALLENGES_REQUIRED)
        assertFalse(RatingPrompt.shouldAsk(true, 20, 0L, now))
        assertTrue(RatingPrompt.shouldAsk(true, 21, 0L, now))
        assertTrue(RatingPrompt.shouldAsk(true, 80, 0L, now))
    }

    @Test
    fun neverAsksAfterAFailedRung() {
        assertFalse(RatingPrompt.shouldAsk(false, 40, 0L, now))
    }

    @Test
    fun theWindowIsSixtyDays() {
        val asked = now.minus(Duration.ofDays(59)).toEpochMilli()
        assertFalse(RatingPrompt.shouldAsk(true, 30, asked, now))
        val enough = now.minus(Duration.ofDays(60)).toEpochMilli()
        assertTrue(RatingPrompt.shouldAsk(true, 30, enough, now))
        assertTrue(RatingPrompt.mayAskAgain(0L, now))
    }

    @Test
    fun fourStarsAndUpGoToTheStoreAndTheRestToFeedback() {
        assertEquals(listOf(false, false, false, true, true), (1..5).map { RatingPrompt.handsOffToStore(it) })
    }

    private fun TestScope.coordinator(clock: () -> Instant): Pair<RatingCoordinator, Prefs> {
        val scope = CoroutineScope(UnconfinedTestDispatcher(testScheduler))
        val prefs = Prefs(PreferenceDataStoreFactory.create(scope = scope) { File(tmp.root, "p.preferences_pb") })
        return RatingCoordinator(prefs, scope, clock, deferMillis = 0) to prefs
    }

    @Test
    fun theCoordinatorOffersOnceThenWaitsTwoMonths() = runTest {
        var clock = now
        val (rating, prefs) = coordinator { clock }

        rating.onRungPassed(20)
        advanceUntilIdle()
        assertNull(rating.offer.value)
        assertEquals(0L, prefs.get(Pref.ratingAskedAt))

        rating.onRungPassed(21)
        advanceUntilIdle()
        assertEquals(21, rating.offer.value?.passedTotal)
        // Stamped when shown, so a dismissed row also waits.
        assertEquals(now.toEpochMilli(), prefs.get(Pref.ratingAskedAt))

        rating.consume()
        rating.onRungPassed(22)
        advanceUntilIdle()
        assertNull(rating.offer.value)

        clock = now.plus(Duration.ofDays(61))
        rating.onRungPassed(30)
        advanceUntilIdle()
        assertNotNull(rating.offer.value)
    }
}
