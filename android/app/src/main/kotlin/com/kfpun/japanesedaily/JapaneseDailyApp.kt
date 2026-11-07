package com.kfpun.japanesedaily

import android.app.Application
import com.kfpun.japanesedaily.analytics.FirebaseSink
import com.kfpun.japanesedaily.analytics.Track

class JapaneseDailyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Track.install(this, FirebaseSink.createOrNull(this), BuildConfig.FIREBASE_COLLECTION)
    }
}
