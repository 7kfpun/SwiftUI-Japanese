package com.kfpun.japanesedaily.settings

import android.Manifest
import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.data.prefs.Pref
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The reminder against the real AlarmManager and NotificationManager (Robolectric): the alarm is inexact,
 * it is re-planned after a reboot, an update and a time-zone change, and firing posts the localised text.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReminderPlatformTest {
    private val app: Application = ApplicationProvider.getApplicationContext()
    private val alarmManager = app.getSystemService(AlarmManager::class.java)

    private fun turnOn(hour: Int = 20, remaining: Int = 3) = runBlocking {
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val prefs = AppContainer.from(app).prefs
        prefs.set(Pref.streakReminderOn, true)
        prefs.set(Pref.streakReminderHour, hour)
        prefs.set(Pref.reminderRemaining, remaining)
    }

    /** The receivers run their work on a background scope; give it a moment. */
    private fun awaitAlarm(): Boolean {
        repeat(100) {
            if (shadowOf(alarmManager).nextScheduledAlarm != null) return true
            Thread.sleep(50)
        }
        return false
    }

    @Test
    fun theAlarmIsInexactAndCancelable() {
        val alarms = SystemReminderAlarms(app)
        val at = Instant.parse("2026-11-08T12:00:00Z")
        alarms.schedule(at)
        val scheduled = shadowOf(alarmManager).nextScheduledAlarm
        assertNotNull(scheduled)
        assertEquals(at.toEpochMilli(), scheduled!!.triggerAtMs)
        assertEquals(AlarmManager.RTC_WAKEUP, scheduled.type)
        // Inexact: no exact-alarm permission is needed, and none is declared.
        assertTrue(scheduled.allowWhileIdle)
        alarms.cancel()
        assertNull(shadowOf(alarmManager).nextScheduledAlarm)
    }

    @Test
    fun rescheduleAlwaysReplacesInsteadOfStacking() {
        val alarms = SystemReminderAlarms(app)
        alarms.schedule(Instant.parse("2026-11-08T12:00:00Z"))
        alarms.cancel()
        alarms.schedule(Instant.parse("2026-11-09T12:00:00Z"))
        assertEquals(1, shadowOf(alarmManager).scheduledAlarms.size)
    }

    @Test
    fun aRebootReplansAnAlarmThatDidNotSurviveIt() {
        turnOn()
        assertNull(shadowOf(alarmManager).nextScheduledAlarm)
        RescheduleReceiver().onReceive(app, Intent(Intent.ACTION_BOOT_COMPLETED))
        assertTrue("no alarm after BOOT_COMPLETED", awaitAlarm())
    }

    @Test
    fun aTimeZoneChangeAndAnUpdateReplanToo() {
        turnOn(remaining = 0)
        RescheduleReceiver().onReceive(app, Intent(Intent.ACTION_TIMEZONE_CHANGED))
        // reminderRemaining is 0 and a zone change must not refill it, so nothing is planned.
        Thread.sleep(500)
        assertNull(shadowOf(alarmManager).nextScheduledAlarm)
        runBlocking { AppContainer.from(app).prefs.set(Pref.reminderRemaining, 3) }
        RescheduleReceiver().onReceive(app, Intent(Intent.ACTION_TIMEZONE_CHANGED))
        assertTrue("no alarm after TIMEZONE_CHANGED", awaitAlarm())
    }

    @Test
    fun anUnrelatedBroadcastDoesNothing() {
        runBlocking { AppContainer.from(app).prefs.set(Pref.streakReminderOn, true) }
        RescheduleReceiver().onReceive(app, Intent("com.example.NOT_OURS"))
        Thread.sleep(300)
        assertNull(shadowOf(alarmManager).nextScheduledAlarm)
    }

    @Test
    fun theNotificationCarriesTheLocalisedTitleAndBody() {
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        SystemReminderNotifier(app).post()
        val manager = app.getSystemService(NotificationManager::class.java)
        val posted = shadowOf(manager).allNotifications.single()
        assertEquals("Keep your streak alive", posted.extras.getString("android.title"))
        assertEquals("You haven't studied yet today.", posted.extras.getString("android.text"))
        assertEquals(SystemReminderNotifier.CHANNEL_ID, posted.channelId)
    }
}
