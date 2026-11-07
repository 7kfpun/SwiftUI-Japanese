package com.kfpun.japanesedaily.settings

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.prefs.Prefs
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Port of the iOS reminder planning tests, reshaped for one pending alarm instead of seven requests. */
@OptIn(ExperimentalCoroutinesApi::class)
class StreakReminderTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val taipei = ZoneId.of("Asia/Taipei")
    private val newYork = ZoneId.of("America/New_York")
    private val berlin = ZoneId.of("Europe/Berlin")

    private fun at(zone: ZoneId, y: Int, m: Int, d: Int, h: Int, min: Int = 0): Instant =
        ZonedDateTime.of(y, m, d, h, min, 0, 0, zone).toInstant()

    private fun local(instant: Instant, zone: ZoneId) = instant.atZone(zone)

    // region Planning (pure)

    @Test
    fun todayIsPlannedWhenItIsStillWinnable() {
        val fire = StreakReminder.nextFire(at(taipei, 2026, 11, 7, 9), taipei, 20, studiedToday = false)
        assertEquals(at(taipei, 2026, 11, 7, 20), fire)
    }

    @Test
    fun todayIsSkippedOnceStudied() {
        val fire = StreakReminder.nextFire(at(taipei, 2026, 11, 7, 9), taipei, 20, studiedToday = true)
        assertEquals(at(taipei, 2026, 11, 8, 20), fire)
    }

    @Test
    fun todayIsSkippedWhenTheHourHasPassed() {
        // A moment in the past would fire at once: roll to tomorrow instead.
        val fire = StreakReminder.nextFire(at(taipei, 2026, 11, 7, 21), taipei, 20, studiedToday = false)
        assertEquals(at(taipei, 2026, 11, 8, 20), fire)
    }

    @Test
    fun theHourItselfIsAlreadyPast() {
        val fire = StreakReminder.nextFire(at(taipei, 2026, 11, 7, 20), taipei, 20, studiedToday = false)
        assertEquals(at(taipei, 2026, 11, 8, 20), fire)
    }

    @Test
    fun theSameInstantIsAnotherLocalHourInAnotherZone() {
        // 08:00 in Taipei is 19:00 the previous evening in New York: there the day is nearly over.
        val now = at(taipei, 2026, 11, 7, 8)
        val taipeiFire = StreakReminder.nextFire(now, taipei, 20, false)
        val newYorkFire = StreakReminder.nextFire(now, newYork, 20, false)
        assertEquals(20, local(taipeiFire, taipei).hour)
        assertEquals(20, local(newYorkFire, newYork).hour)
        assertEquals(7, local(taipeiFire, taipei).dayOfMonth)
        // 19:00 on 6 Nov in New York (EST): today's 20:00 is still ahead.
        assertEquals(6, local(newYorkFire, newYork).dayOfMonth)
        assertTrue(newYorkFire.isBefore(taipeiFire))
    }

    @Test
    fun travellingMovesTheWallClockTime() {
        // Same stored hour, new zone: the reminder follows the learner to 20:00 where they are.
        val now = at(berlin, 2026, 11, 7, 12)
        assertEquals(at(berlin, 2026, 11, 7, 20), StreakReminder.nextFire(now, berlin, 20, false))
        assertEquals(at(taipei, 2026, 11, 7, 20), StreakReminder.nextFire(now, taipei, 20, false))
    }

    @Test
    fun theDayIsTheUsersOwnNotUtc() {
        // 00:30 Taipei on the 8th is still the 7th in UTC: planning must use the local date.
        val now = at(taipei, 2026, 11, 8, 0, 30)
        val fire = StreakReminder.nextFire(now, taipei, 20, studiedToday = false)
        assertEquals(at(taipei, 2026, 11, 8, 20), fire)
    }

    @Test
    fun aDstGapShiftsForwardInsteadOfDropping() {
        // 2026-03-08 02:30 does not exist in New York; a 02:00 reminder lands on the 3rd, not nowhere.
        val now = at(newYork, 2026, 3, 7, 23)
        val fire = StreakReminder.nextFire(now, newYork, 2, studiedToday = false)
        assertEquals(3, local(fire, newYork).hour)
        assertEquals(8, local(fire, newYork).dayOfMonth)
    }

    @Test
    fun aDstFallBackDayStillFiresAtTheChosenWallClockHour() {
        val now = at(newYork, 2026, 11, 1, 12)
        val fire = StreakReminder.nextFire(now, newYork, 20, studiedToday = true)
        assertEquals(at(newYork, 2026, 11, 2, 20), fire)
        assertEquals(20, local(fire, newYork).hour)
    }

    @Test
    fun theStoredHourIsClamped() {
        assertEquals(20, StreakReminder.resolvedHour(0))
        assertEquals(20, StreakReminder.resolvedHour(24))
        assertEquals(20, StreakReminder.resolvedHour(-3))
        assertEquals(1, StreakReminder.resolvedHour(1))
        assertEquals(23, StreakReminder.resolvedHour(23))
        assertEquals(StreakReminder.hours.toList(), (6..23).toList())
    }

    // endregion

    // region Engine (fakes for the alarm and the notification)

    private class FakeAlarms : ReminderAlarms {
        var scheduled: Instant? = null
        var cancels = 0

        override fun schedule(at: Instant) {
            scheduled = at
        }

        override fun cancel() {
            cancels++
            scheduled = null
        }
    }

    private class Rig(
        val prefs: Prefs,
        val alarms: FakeAlarms = FakeAlarms(),
        var studied: Boolean = false,
        var enabled: Boolean = true,
        var now: Instant,
        var zone: ZoneId,
        var posted: Int = 0
    ) {
        val engine = StreakReminderEngine(
            prefs = prefs,
            studiedToday = { studied },
            notificationsEnabled = { enabled },
            alarms = alarms,
            notifier = { posted++ },
            clock = { now },
            zone = { zone }
        )
    }

    private fun TestScope.rig(now: Instant, zone: ZoneId = taipei) = Rig(
        Prefs(
            PreferenceDataStoreFactory.create(scope = CoroutineScope(UnconfinedTestDispatcher(testScheduler))) {
                File(tmp.root, "prefs.preferences_pb")
            }
        ),
        now = now,
        zone = zone
    )

    private suspend fun Rig.turnOn(hour: Int = 20) {
        prefs.set(Pref.streakReminderOn, true)
        prefs.set(Pref.streakReminderHour, hour)
    }

    @Test
    fun offPlansNothingAndClearsWhatWasThere() = runTest {
        val r = rig(at(taipei, 2026, 11, 7, 9))
        r.engine.reschedule()
        assertNull(r.alarms.scheduled)
        assertEquals(1, r.alarms.cancels)
    }

    @Test
    fun onPlansTodayThenTomorrowOnceStudied() = runTest {
        val r = rig(at(taipei, 2026, 11, 7, 9))
        r.turnOn()
        r.engine.reschedule()
        assertEquals(at(taipei, 2026, 11, 7, 20), r.alarms.scheduled)

        // The first answer of the day re-plans: today's reminder is gone, not merely ignored.
        r.studied = true
        r.engine.reschedule()
        assertEquals(at(taipei, 2026, 11, 8, 20), r.alarms.scheduled)
    }

    @Test
    fun withoutNotificationPermissionNothingIsPlanned() = runTest {
        val r = rig(at(taipei, 2026, 11, 7, 9))
        r.turnOn()
        r.enabled = false
        r.engine.reschedule()
        assertNull(r.alarms.scheduled)
    }

    @Test
    fun anUnsetOrBrokenHourPlansTheDefault() = runTest {
        val r = rig(at(taipei, 2026, 11, 7, 9))
        r.prefs.set(Pref.streakReminderOn, true)
        r.engine.reschedule()
        assertEquals(at(taipei, 2026, 11, 7, 20), r.alarms.scheduled)
        r.prefs.set(Pref.streakReminderHour, 0)
        r.engine.reschedule()
        assertEquals(at(taipei, 2026, 11, 7, 20), r.alarms.scheduled)
    }

    @Test
    fun aTimeZoneChangeReplansInTheNewZone() = runTest {
        val r = rig(at(taipei, 2026, 11, 7, 9))
        r.turnOn()
        r.engine.reschedule()
        assertEquals(at(taipei, 2026, 11, 7, 20), r.alarms.scheduled)
        r.zone = berlin
        r.engine.reschedule(resetHorizon = false)
        assertEquals(at(berlin, 2026, 11, 7, 20), r.alarms.scheduled)
    }

    @Test
    fun theAlarmPostsWhenNotStudiedAndPlansTomorrow() = runTest {
        val r = rig(at(taipei, 2026, 11, 7, 9))
        r.turnOn()
        r.engine.reschedule()
        r.now = at(taipei, 2026, 11, 7, 20, 5)
        assertEquals(ReminderOutcome.Posted, r.engine.onAlarm())
        assertEquals(1, r.posted)
        assertEquals(at(taipei, 2026, 11, 8, 20), r.alarms.scheduled)
    }

    @Test
    fun theAlarmStaysQuietWhenStudiedSinceItWasPlanned() = runTest {
        val r = rig(at(taipei, 2026, 11, 7, 9))
        r.turnOn()
        r.engine.reschedule()
        r.studied = true
        r.now = at(taipei, 2026, 11, 7, 20, 5)
        assertEquals(ReminderOutcome.SkippedStudied, r.engine.onAlarm())
        assertEquals(0, r.posted)
        // Still plans tomorrow: a quiet day does not end the reminder.
        assertEquals(at(taipei, 2026, 11, 8, 20), r.alarms.scheduled)
    }

    @Test
    fun theAlarmRechecksTheToggleAndThePermission() = runTest {
        val r = rig(at(taipei, 2026, 11, 7, 20, 5))
        r.turnOn()
        r.engine.reschedule()
        r.enabled = false
        assertEquals(ReminderOutcome.SkippedNoPermission, r.engine.onAlarm())
        r.enabled = true
        r.prefs.set(Pref.streakReminderOn, false)
        assertEquals(ReminderOutcome.SkippedDisabled, r.engine.onAlarm())
        assertEquals(0, r.posted)
    }

    @Test
    fun aWeekWithoutOpeningTheAppEndsTheReminders() = runTest {
        val r = rig(at(taipei, 2026, 11, 7, 9))
        r.turnOn()
        r.engine.reschedule()
        repeat(StreakReminder.HORIZON) { day ->
            r.now = at(taipei, 2026, 11, 7 + day, 20, 5)
            r.alarms.scheduled = null // an alarm that has fired is gone
            assertEquals(ReminderOutcome.Posted, r.engine.onAlarm())
        }
        assertEquals(StreakReminder.HORIZON, r.posted)
        // The seventh firing used up the horizon, so no eighth is planned.
        assertNull(r.alarms.scheduled)
        // Opening the app refills it.
        r.now = at(taipei, 2026, 11, 15, 9)
        r.engine.reschedule()
        assertEquals(at(taipei, 2026, 11, 15, 20), r.alarms.scheduled)
    }

    @Test
    fun aRebootDoesNotRestartTheWeek() = runTest {
        val r = rig(at(taipei, 2026, 11, 7, 9))
        r.turnOn()
        r.prefs.set(Pref.reminderRemaining, 0)
        r.engine.reschedule(resetHorizon = false)
        assertNull(r.alarms.scheduled)
        r.engine.reschedule(resetHorizon = true)
        assertEquals(at(taipei, 2026, 11, 7, 20), r.alarms.scheduled)
    }

    // endregion
}
