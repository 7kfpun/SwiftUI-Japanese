package com.kfpun.japanesedaily.today

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.content.edit
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.updateAll
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequest
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.kfpun.japanesedaily.locale.AppLocale
import java.time.Duration
import java.time.Instant

/**
 * Keeps the Today widget in step with the app (iOS `publishWidget` + `WidgetCenter`): the app publishes the deck as a
 * [TodayShared.Snapshot] (a small JSON string in private preferences, the App Group's counterpart), the widget reads
 * it, and [TodayWidgetWorker] redraws it on the hour.
 */
object TodayWidgetUpdater {
    private const val TAG = "TodayWidget"
    private const val PREFS = "today_widget"
    private const val KEY_SNAPSHOT = "today.snapshot"
    private const val KEY_DRAWN_LANGUAGE = "drawn_language"

    /** The published deck, or null before the app ever published one (the widget then shows the sample deck). */
    fun read(context: Context): TodayShared.Snapshot? =
        prefs(context).getString(KEY_SNAPSHOT, null)?.let(TodayShared::decode)?.takeIf { it.words.isNotEmpty() }

    /** Stores the deck and redraws the widget when it changed. Not progress: the Room tables are never touched. */
    suspend fun publish(context: Context, snapshot: TodayShared.Snapshot) {
        val app = context.applicationContext
        val encoded = TodayShared.encode(snapshot)
        val prefs = prefs(app)
        if (prefs.getString(KEY_SNAPSHOT, null) == encoded) return
        prefs.edit { putString(KEY_SNAPSHOT, encoded) }
        redrawAll(app)
    }

    suspend fun redrawAll(context: Context) {
        runCatching { TodayWidget().updateAll(context.applicationContext) }
            .onFailure { Log.w(TAG, "Couldn't redraw the widget", it) }
    }

    /**
     * At app start: Android 13+ lets Settings change the app's language while the app isn't running, so nothing told
     * the widget. Redraws when the language differs from the one it was last drawn in, and keeps the hourly redraw
     * scheduled while a widget is placed.
     */
    suspend fun onAppStart(context: Context) {
        val app = context.applicationContext
        val tag = AppLocale.locale(app).toLanguageTag()
        val prefs = prefs(app)
        if (prefs.getString(KEY_DRAWN_LANGUAGE, null) != tag) {
            prefs.edit { putString(KEY_DRAWN_LANGUAGE, tag) }
            redrawAll(app)
        }
        syncSchedule(app)
        // The picker preview (generated previews, Android 15+); older versions use previewLayout from the XML.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            runCatching { GlanceAppWidgetManager(app).setWidgetPreviews(TodayWidgetReceiver::class) }
        }
    }

    /** Whether any Today widget is on a home screen. */
    suspend fun isPlaced(context: Context): Boolean = runCatching {
        GlanceAppWidgetManager(context).getGlanceIds(TodayWidget::class.java).isNotEmpty()
    }.getOrDefault(false)

    /** Starts the hourly redraw while a widget is placed and stops it when none is. */
    suspend fun syncSchedule(context: Context) {
        val work = WorkManager.getInstance(context)
        if (TodayWidgetSchedule.shouldSchedule(isPlaced(context))) {
            work.enqueueUniquePeriodicWork(
                TodayWidgetSchedule.PERIODIC_WORK,
                ExistingPeriodicWorkPolicy.KEEP,
                TodayWidgetSchedule.periodicRequest()
            )
            work.enqueueUniqueWork(
                TodayWidgetSchedule.HOURLY_WORK,
                ExistingWorkPolicy.KEEP,
                TodayWidgetSchedule.nextHourRequest(Instant.now())
            )
        } else {
            work.cancelUniqueWork(TodayWidgetSchedule.PERIODIC_WORK)
            work.cancelUniqueWork(TodayWidgetSchedule.HOURLY_WORK)
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/**
 * When the widget redraws. No network and no data to fetch (the words are already on the device), so the only cost is
 * waking once an hour: a one-shot aimed at the next clock hour keeps the rotation on the clock, re-armed by each run,
 * and a 1-hour periodic request is the safety net that re-arms it if the chain is ever broken. Both wait for the
 * battery not to be low, so a phone saving power keeps the word it has instead of waking for a new one.
 */
object TodayWidgetSchedule {
    const val PERIODIC_WORK = "today-widget-periodic"
    const val HOURLY_WORK = "today-widget-hourly"

    /** A little past the boundary, so the redraw lands in the new hour even when the job starts a moment early. */
    val boundarySlack: Duration = Duration.ofSeconds(5)
    val safetyInterval: Duration = Duration.ofHours(1)
    val safetyFlex: Duration = Duration.ofMinutes(15)

    private val constraints: Constraints = Constraints.Builder().setRequiresBatteryNotLow(true).build()

    fun shouldSchedule(placed: Boolean): Boolean = placed

    /** The delay from [now] to just after the next top of the hour. Always positive and at most an hour. */
    fun delayToNextHour(now: Instant): Duration = Duration.between(now, TodayShared.nextHour(now)).plus(boundarySlack)

    fun nextHourRequest(now: Instant): OneTimeWorkRequest = OneTimeWorkRequestBuilder<TodayWidgetWorker>()
        .setInitialDelay(delayToNextHour(now))
        .setConstraints(constraints)
        .build()

    fun periodicRequest(): PeriodicWorkRequest =
        PeriodicWorkRequestBuilder<TodayWidgetWorker>(safetyInterval, safetyFlex)
            .setConstraints(constraints)
            .build()
}

/** Redraws the widget (its word follows the clock) and arms the next hour while a widget is placed. */
class TodayWidgetWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        if (!TodayWidgetUpdater.isPlaced(context)) {
            TodayWidgetUpdater.syncSchedule(context)
            return Result.success()
        }
        TodayWidgetUpdater.redrawAll(context)
        WorkManager.getInstance(context).enqueueUniqueWork(
            TodayWidgetSchedule.HOURLY_WORK,
            // Appended, never REPLACE: this run *is* the unique work, and replacing it would cancel itself.
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            TodayWidgetSchedule.nextHourRequest(Instant.now())
        )
        return Result.success()
    }
}
