package com.kfpun.japanesedaily.settings

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.test.core.app.ApplicationProvider
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.prefs.Prefs
import com.kfpun.japanesedaily.data.progress.Streak
import java.io.File
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The notification opt-in policy, and the settings that round-trip through preferences. */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class OptInAndPrefsTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val now = Instant.parse("2026-11-07T10:00:00Z")

    private fun TestScope.prefs() = Prefs(
        PreferenceDataStoreFactory.create(scope = CoroutineScope(UnconfinedTestDispatcher(testScheduler))) {
            File(tmp.root, "p.preferences_pb")
        }
    )

    @Test
    fun aSoftAskIsOfferedOnlyWhenThereIsSomethingToOffer() {
        assertTrue(NotificationOptIn.mayAsk(isOn = false, blocked = false, lastAskedAt = 0L, now = now))
        // Already on, or blocked in system settings: nothing to offer, nowhere to lead.
        assertFalse(NotificationOptIn.mayAsk(isOn = true, blocked = false, lastAskedAt = 0L, now = now))
        assertFalse(NotificationOptIn.mayAsk(isOn = false, blocked = true, lastAskedAt = 0L, now = now))
    }

    @Test
    fun aNotNowIsRespectedForSixtyDays() {
        val fiftyNine = now.minus(Duration.ofDays(59)).toEpochMilli()
        val sixty = now.minus(Duration.ofDays(60)).toEpochMilli()
        assertFalse(NotificationOptIn.mayAsk(false, false, fiftyNine, now))
        assertTrue(NotificationOptIn.mayAsk(false, false, sixty, now))
    }

    @Test
    fun theStreakMilestoneIsTheCurrentRunNotTheBest() {
        val today = 20261107
        val week = (0 until 7).map { com.kfpun.japanesedaily.data.progress.StudyDay.offset(today, -it) }.toSet()
        assertTrue(NotificationOptIn.shouldAskAfterStreak(Streak(week, today), false, false, 0L, now))
        val six = week - com.kfpun.japanesedaily.data.progress.StudyDay.offset(today, -6)
        assertFalse(NotificationOptIn.shouldAskAfterStreak(Streak(six, today), false, false, 0L, now))
        // A long record but a broken streak has nothing at stake tonight.
        val old = (30..60).map { com.kfpun.japanesedaily.data.progress.StudyDay.offset(today, -it) }.toSet()
        assertFalse(NotificationOptIn.shouldAskAfterStreak(Streak(old, today), false, false, 0L, now))
    }

    @Test
    fun reminderAndRatingPrefsRoundTrip() = runTest {
        val p = prefs()
        assertFalse(p.get(Pref.streakReminderOn))
        assertEquals(20, p.get(Pref.streakReminderHour))
        p.set(Pref.streakReminderOn, true)
        p.set(Pref.streakReminderHour, 7)
        p.set(Pref.ratingAskedAt, 1_700_000_000_000L)
        p.set(Pref.notificationAskedAt, 1_700_000_001_000L)
        assertTrue(p.get(Pref.streakReminderOn))
        assertEquals(7, p.get(Pref.streakReminderHour))
        assertEquals(1_700_000_000_000L, p.get(Pref.ratingAskedAt))
        assertEquals(1_700_000_001_000L, p.get(Pref.notificationAskedAt))
    }

    @Test
    fun theMeaningLanguageRoundTripsAndFallsBackToTheDeviceDefault() = runTest {
        val p = prefs()
        assertEquals("de", p.translationLanguage("de").first())
        p.setTranslationLanguage("zh-Hant")
        assertEquals("zh-Hant", p.translationLanguage("de").first())
    }

    @Test
    fun appearanceRoundTripsAndUnknownMeansSystem() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        assertEquals(Appearance.System, Appearance.chosen(context))
        Appearance.set(context, Appearance.Dark)
        assertEquals(Appearance.Dark, Appearance.chosen(context))
        Appearance.set(context, Appearance.Light)
        assertEquals(Appearance.Light, Appearance.chosen(context))
        assertEquals(Appearance.System, Appearance.fromId("sepia"))
        assertEquals(Appearance.System, Appearance.fromId(null))
    }

    @Test
    fun textSizeRoundTripsAndRejectsAStrayValue() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        assertEquals(100, TextSize.percent(context))
        TextSize.set(context, 130)
        assertEquals(130, TextSize.percent(context))
        assertEquals(1.3f, TextSize.scale(context), 0.0001f)
        assertEquals(1.3f, TextSize.liveScale, 0.0001f)
        TextSize.set(context, 999)
        assertEquals(100, TextSize.percent(context))
    }
}
