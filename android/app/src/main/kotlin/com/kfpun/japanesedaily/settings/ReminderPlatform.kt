package com.kfpun.japanesedaily.settings

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.kfpun.japanesedaily.MainActivity
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.locale.AppLocale
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * The reminder alarm on [AlarmManager]. **Inexact on purpose**: `setAndAllowWhileIdle` needs no
 * `SCHEDULE_EXACT_ALARM` grant (which Play restricts to alarm-clock and calendar apps), and "some
 * time around eight" is all a nudge needs. It survives Doze but not a reboot, which `RescheduleReceiver`
 * answers.
 */
class SystemReminderAlarms(private val context: Context) : ReminderAlarms {
    private val alarms = context.getSystemService(AlarmManager::class.java)

    override fun schedule(at: Instant) {
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.toEpochMilli(), pending())
    }

    override fun cancel() = alarms.cancel(pending())

    private fun pending(): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_CODE,
        Intent(context, ReminderReceiver::class.java).setAction(ACTION_FIRE),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )

    companion object {
        const val ACTION_FIRE = "com.kfpun.japanesedaily.STREAK_REMINDER"
        private const val REQUEST_CODE = 4401
    }
}

/** Posts "Keep your streak alive". Text goes through [AppLocale.localizedContext]: no activity is running. */
class SystemReminderNotifier(private val context: Context) : ReminderNotifier {
    @SuppressLint("MissingPermission") // areNotificationsEnabled() is the permission check, just below
    override fun post() {
        val text = AppLocale.localizedContext(context)
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        ensureChannel(context, text.getString(R.string.reminders))
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(EXTRA_FROM_REMINDER, true),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        // Deliberately no streak number: the alarm is planned hours ahead, so a baked-in count is a guess
        // about a day that has not happened.
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_streak)
            .setContentTitle(text.getString(R.string.keep_your_streak_alive))
            .setContentText(text.getString(R.string.you_haven_t_studied_yet_today))
            .setContentIntent(open)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    companion object {
        const val CHANNEL_ID = "streak_reminder"
        const val EXTRA_FROM_REMINDER = "fromStreakReminder"
        private const val NOTIFICATION_ID = 4402

        /** Creates (or renames, for a new app language) the channel; a no-op below Android 8. */
        fun ensureChannel(context: Context, name: String) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_DEFAULT)
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}

/** Builds the engine over the real container, alarm manager and notification. */
object Reminders {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun engine(context: Context): StreakReminderEngine {
        val app = context.applicationContext
        val container = AppContainer.from(app)
        return StreakReminderEngine(
            prefs = container.prefs,
            studiedToday = { container.progress.streak().studiedToday },
            notificationsEnabled = { NotificationManagerCompat.from(app).areNotificationsEnabled() },
            alarms = SystemReminderAlarms(app),
            notifier = SystemReminderNotifier(app)
        )
    }

    /** Re-plans in the background; for call sites with no coroutine of their own (launch, first answer). */
    fun reschedule(context: Context, resetHorizon: Boolean = true) {
        val app = context.applicationContext
        scope.launch { engine(app).reschedule(resetHorizon) }
    }
}

/** The alarm fired: decide at fire time whether to post, then plan tomorrow. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != SystemReminderAlarms.ACTION_FIRE) return
        val pending: PendingResult? = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                Reminders.engine(context).onAlarm()
            } finally {
                pending?.finish()
            }
        }
    }
}

/**
 * Alarms do not survive a reboot, an app update or a clock change, and a time-zone change moves "8 pm":
 * all four re-plan from the stored hour in the zone the phone is now in. None restarts the horizon, so a
 * dead install does not get a fresh week from a reboot.
 */
class RescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACTIONS) return
        val pending: PendingResult? = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                Reminders.engine(context).reschedule(resetHorizon = false)
            } finally {
                pending?.finish()
            }
        }
    }

    companion object {
        val ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED
        )
    }
}
