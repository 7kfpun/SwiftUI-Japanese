package com.kfpun.japanesedaily.settings

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.progress.Streak
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.launch

/**
 * When to *ask about* notifications (port of `NotificationOptIn.swift`): a soft ask in the app's own UI
 * first, and the system permission only after a yes. Android 13 shows the system dialog at most twice
 * before it turns permanent, so it is treated as a scarce resource here too.
 *
 * Two places ask: the last intro card, and the streak crossing [STREAK_THRESHOLD] (Today, FOX-155).
 * They share this policy so they cannot both fire in the same two months.
 */
object NotificationOptIn {
    /** Streak length that earns a second ask: the habit is real and worth protecting by then. */
    const val STREAK_THRESHOLD = 7

    /** How long a "not now" is respected; long on purpose. */
    val askAgainAfter: Duration = Duration.ofDays(60)

    /**
     * Whether a soft ask may be shown at all. Already getting reminders: nothing to offer. Notifications
     * blocked in system settings ([blocked]): a soft ask could only lead somewhere it cannot go. Permission
     * granted with our toggle off is a real state and *is* worth asking. [lastAskedAt] is epoch millis, 0 for never.
     */
    fun mayAsk(isOn: Boolean, blocked: Boolean, lastAskedAt: Long, now: Instant): Boolean {
        if (isOn || blocked) return false
        if (lastAskedAt <= 0L) return true
        return Duration.between(Instant.ofEpochMilli(lastAskedAt), now) >= askAgainAfter
    }

    /** The streak milestone: the *current* run has reached the threshold (not the best one). */
    fun shouldAskAfterStreak(
        streak: Streak,
        isOn: Boolean,
        blocked: Boolean,
        lastAskedAt: Long,
        now: Instant
    ): Boolean = streak.current >= STREAK_THRESHOLD && mayAsk(isOn, blocked, lastAskedAt, now)

    /** Whether the app may post right now: the 13+ runtime permission, the app-level and channel switches. */
    fun enabled(context: Context): Boolean = NotificationManagerCompat.from(context).areNotificationsEnabled()

    /** Where a learner who said no can say yes: the app's notification page in system settings. */
    fun systemSettingsIntent(context: Context): Intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}

/**
 * The explicit "remind me" action, shared by Settings and the intro's last card: ask for the 13+
 * permission, and on a yes turn the reminder on and plan it. Returns the function to call from the tap;
 * [onResult] hears whether the reminder is now on (false for a refusal, and the toggle goes back off).
 * Only ever called from an explicit opt-in, never at launch.
 */
@Composable
fun rememberReminderOptIn(onResult: (granted: Boolean) -> Unit = {}): () -> Unit {
    val context = LocalContext.current
    val container = AppContainer.from(context)
    val scope = rememberCoroutineScope()
    val result = rememberUpdatedState(onResult)

    fun finish(granted: Boolean, firstAsk: Boolean) {
        scope.launch {
            val prefs = container.prefs
            prefs.set(Pref.notificationAskedAt, System.currentTimeMillis())
            val hour = StreakReminder.resolvedHour(prefs.get(Pref.streakReminderHour))
            if (firstAsk) Track.event(TrackEvents.NOTIFICATION_PERMISSION, mapOf("granted" to granted))
            if (granted) {
                prefs.set(Pref.streakReminderOn, true)
                Reminders.engine(context).reschedule()
                Track.event(TrackEvents.STREAK_REMINDER, mapOf("on" to true, "hour" to hour))
            } else {
                // An enable that the system refused: logged as that, not as a chosen disable.
                prefs.set(Pref.streakReminderOn, false)
                Track.event(TrackEvents.STREAK_REMINDER, mapOf("on" to true, "hour" to hour, "denied" to true))
            }
            result.value(granted)
        }
    }

    // Whether the system dialog was never shown before: only that one counts as a permission event.
    val firstAsk = remember { BooleanArray(1) { true } }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        finish(granted && NotificationOptIn.enabled(context), firstAsk[0])
    }
    return {
        val needsPermission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        if (needsPermission) {
            scope.launch {
                firstAsk[0] = container.prefs.get(Pref.notificationAskedAt) == 0L
                launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        } else {
            finish(NotificationOptIn.enabled(context), firstAsk = false)
        }
    }
}

/** The hosting activity, for APIs that need one (UMP, In-App Review). */
tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is android.content.ContextWrapper -> baseContext.findActivity()
    else -> null
}
