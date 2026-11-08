package com.kfpun.japanesedaily.analytics

import android.content.Context
import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.crashlytics.FirebaseCrashlytics

/** [TrackSink] over Firebase Analytics and Crashlytics, the only file that imports them. */
internal class FirebaseSink private constructor(
    private val analytics: FirebaseAnalytics,
    private val crashlytics: FirebaseCrashlytics
) : TrackSink {
    override fun logEvent(name: String, params: Map<String, Any>) {
        val bundle = Bundle()
        for ((key, value) in params) {
            when (value) {
                is Long -> bundle.putLong(key, value)
                is Double -> bundle.putDouble(key, value)
                else -> bundle.putString(key, value.toString())
            }
        }
        analytics.logEvent(name, bundle)
    }

    override fun setUserProperty(name: String, value: String) = analytics.setUserProperty(name, value)

    override fun setCollectionEnabled(enabled: Boolean) {
        analytics.setAnalyticsCollectionEnabled(enabled)
        crashlytics.isCrashlyticsCollectionEnabled = enabled
    }

    override fun breadcrumb(message: String) = crashlytics.log(message)

    companion object {
        /**
         * The Firebase sink, or null when this build has no Firebase app: the google-services plugin
         * (applied only when `app/google-services.json` exists) is what creates it, so a CI or fresh-clone
         * build gets null and [Track] stays a no-op.
         */
        fun createOrNull(context: Context): FirebaseSink? = runCatching {
            if (FirebaseApp.getApps(context).isEmpty()) return null
            val analytics = FirebaseAnalytics.getInstance(context)
            // Non-personalized, like the ads: no ad storage, no ad user data, no personalization, and
            // Analytics itself keeps no advertising id (also set in the manifest, before first launch).
            analytics.setConsent(
                mapOf(
                    FirebaseAnalytics.ConsentType.AD_STORAGE to FirebaseAnalytics.ConsentStatus.DENIED,
                    FirebaseAnalytics.ConsentType.AD_USER_DATA to FirebaseAnalytics.ConsentStatus.DENIED,
                    FirebaseAnalytics.ConsentType.AD_PERSONALIZATION to FirebaseAnalytics.ConsentStatus.DENIED,
                    FirebaseAnalytics.ConsentType.ANALYTICS_STORAGE to FirebaseAnalytics.ConsentStatus.GRANTED
                )
            )
            FirebaseSink(analytics, FirebaseCrashlytics.getInstance())
        }.getOrNull()
    }
}
