package com.kfpun.japanesedaily

import android.app.Application
import com.kfpun.japanesedaily.analytics.FirebaseSink
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.survey.Survey

class JapaneseDailyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Track.install(this, FirebaseSink.createOrNull(this), BuildConfig.FIREBASE_COLLECTION)
        // A rejected or failed survey write is counted (the answer itself is never lost to the opt-out).
        Survey.failureReporter = Survey.FailureReporter {
            Track.event(TrackEvents.SURVEY_FAILED, mapOf("collection" to it))
        }
    }
}
