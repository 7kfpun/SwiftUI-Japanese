package com.kfpun.japanesedaily.settings

import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.prefs.Prefs
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * The daily "your streak is still open" reminder, scheduled entirely on the device (port of
 * `StreakReminder.swift`). Deliberately not a push: what is worth saying (you have not studied
 * today) comes from `StudyDay` rows that never leave the phone, at a wall-clock time only the phone
 * knows.
 *
 * Android keeps **one pending inexact alarm**, the next fire time, instead of iOS's seven calendar
 * requests: each firing posts (unless today is already studied) and plans the next. A wake-up that
 * follows the learner's time zone needs the plan re-derived anyway, which is what the boot and
 * time-zone receivers do. The seven-day [HORIZON] still holds: a learner who stops opening the app
 * gets a week of reminders and then silence.
 */
object StreakReminder {
    /** Days of reminders after the last app open or answer, before a dead install goes quiet. */
    const val HORIZON = 7

    /** Evening: late enough that a normal day's study has happened, early enough to act on. */
    const val DEFAULT_HOUR = Pref.DEFAULT_REMINDER_HOUR

    /** The hours Settings offers; whole hours only (the reminder is "this evening", not an appointment). */
    val hours = 6..23

    /** The stored hour, clamped to a real one: 0 or garbage reads as the default, never midnight. */
    fun resolvedHour(stored: Int): Int = if (stored in 1..23) stored else DEFAULT_HOUR

    /**
     * When the next reminder fires: today at [hour] if that is still ahead **and** today is not studied,
     * else tomorrow at [hour], in [zone]. Scheduling a moment that has passed would fire at once, and
     * not re-planning after the learner studies is the most annoying thing a streak reminder can do.
     * [ZonedDateTime.of] shifts a time that does not exist (a DST gap) forward, never drops it.
     */
    fun nextFire(now: Instant, zone: ZoneId, hour: Int, studiedToday: Boolean): Instant {
        val local = now.atZone(zone)
        val today = ZonedDateTime.of(local.toLocalDate(), LocalTime.of(hour, 0), zone)
        val target = if (!studiedToday && now.isBefore(today.toInstant())) today else today.plusDays(1)
        return ZonedDateTime.of(target.toLocalDate(), LocalTime.of(hour, 0), zone).toInstant()
    }
}

/** The one pending alarm; the system implementation is `SystemReminderAlarms`. */
interface ReminderAlarms {
    /** Replaces any pending reminder alarm with one at [at]. */
    fun schedule(at: Instant)

    fun cancel()
}

/** Posts the notification. Its text is read through `AppLocale.localizedContext`. */
fun interface ReminderNotifier {
    fun post()
}

/** What a firing or a re-plan did, for tests and the `streak_reminder` events. */
enum class ReminderOutcome { Posted, SkippedStudied, SkippedDisabled, SkippedNoPermission }

/**
 * Plans and fires the reminder. Everything platform-specific is injected, so the cases that matter
 * (time zones, already studied today, the horizon, a revoked permission) run as plain JVM tests.
 */
class StreakReminderEngine(
    private val prefs: Prefs,
    private val studiedToday: suspend () -> Boolean,
    private val notificationsEnabled: () -> Boolean,
    private val alarms: ReminderAlarms,
    private val notifier: ReminderNotifier,
    private val clock: () -> Instant = { Instant.now() },
    private val zone: () -> ZoneId = { ZoneId.systemDefault() }
) {
    /**
     * Replaces the pending alarm with a fresh plan, or just cancels it when the reminder is off or
     * notifications are not allowed. Idempotent and cheap: called on every app open, every first answer
     * of a day, a reboot, a time-zone change and each settings change. [resetHorizon] (everything except
     * a boot or zone change) restarts the week, since the learner is evidently still here.
     */
    suspend fun reschedule(resetHorizon: Boolean = true) {
        alarms.cancel()
        if (!prefs.get(Pref.streakReminderOn) || !notificationsEnabled()) return
        if (resetHorizon) prefs.set(Pref.reminderRemaining, StreakReminder.HORIZON)
        if (prefs.get(Pref.reminderRemaining) <= 0) return
        plan(studiedToday())
    }

    /**
     * The alarm went off. Re-checks everything at fire time, because the plan was made hours ago: the
     * learner may have studied since, turned the reminder off or revoked the permission. Then plans the
     * next day, using up one day of the horizon.
     */
    suspend fun onAlarm(): ReminderOutcome {
        if (!prefs.get(Pref.streakReminderOn)) return ReminderOutcome.SkippedDisabled
        if (!notificationsEnabled()) return ReminderOutcome.SkippedNoPermission
        val studied = studiedToday()
        val outcome = if (studied) {
            ReminderOutcome.SkippedStudied
        } else {
            notifier.post()
            ReminderOutcome.Posted
        }
        val remaining = prefs.get(Pref.reminderRemaining) - 1
        prefs.set(Pref.reminderRemaining, remaining.coerceAtLeast(0))
        // Tomorrow, not "today again": the hour has just passed, so a not-studied plan rolls to tomorrow.
        if (remaining > 0) plan(studiedToday = false)
        return outcome
    }

    private suspend fun plan(studiedToday: Boolean) {
        val hour = StreakReminder.resolvedHour(prefs.get(Pref.streakReminderHour))
        alarms.schedule(StreakReminder.nextFire(clock(), zone(), hour, studiedToday))
    }
}
