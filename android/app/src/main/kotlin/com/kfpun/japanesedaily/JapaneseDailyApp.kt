package com.kfpun.japanesedaily

import android.app.Application
import com.kfpun.japanesedaily.analytics.FirebaseSink
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.settings.Appearance
import com.kfpun.japanesedaily.settings.TextSize
import com.kfpun.japanesedaily.survey.Survey

class JapaneseDailyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Before any activity: the night mode and text size must be right on the first frame.
        Appearance.apply(this)
        TextSize.load(this)
        Track.install(this, FirebaseSink.createOrNull(this), BuildConfig.FIREBASE_COLLECTION)
        // A rejected or failed survey write is counted (the answer itself is never lost to the opt-out).
        Survey.failureReporter = Survey.FailureReporter {
            Track.event(TrackEvents.SURVEY_FAILED, mapOf("collection" to it))
        }
    }
}
