package com.kfpun.japanesedaily.ads

import android.app.Activity
import android.util.Log
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import com.kfpun.japanesedaily.BuildConfig
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.billing.Entitlement
import java.lang.ref.WeakReference
import kotlinx.coroutines.flow.StateFlow

/**
 * The hooks screens call (iOS `Ads.preloadInterstitial` / `showInterstitialIfReady`). Practice calls
 * [onLeavePractice] when it closes and a Challenge run calls [onChallengeFinished] when it ends;
 * neither is ever called mid-run.
 */
interface Interstitials {
    /** Warm an interstitial up, for a screen that may show one when it closes. */
    fun preload()

    /** Leaving Practice: shows one only if something was [answered]. */
    fun onLeavePractice(answered: Boolean)

    /** A Challenge run reached its end (pass or fail). Never for a run abandoned part way. */
    fun onChallengeFinished()
}

object NoInterstitials : Interstitials {
    override fun preload() = Unit

    override fun onLeavePractice(answered: Boolean) = Unit

    override fun onChallengeFinished() = Unit
}

/**
 * At most one interstitial per [minIntervalMs] (iOS `Interstitial.minInterval = 180`). Pure, with an
 * injectable clock, so the window is tested without AdMob. [tryAcquire] both checks and starts a window.
 */
class InterstitialThrottle(
    private val minIntervalMs: Long = MIN_INTERVAL_MS,
    private val now: () -> Long = System::currentTimeMillis
) {
    private var lastShown: Long? = null

    fun isOpen(): Boolean = lastShown?.let { now() - it > minIntervalMs } ?: true

    fun tryAcquire(): Boolean {
        if (!isOpen()) return false
        lastShown = now()
        return true
    }

    companion object {
        const val MIN_INTERVAL_MS = 180_000L
    }
}

/** What the interstitials need to know: the entitlement and consent, and where to present. */
class AdMobInterstitials(
    private val entitlement: StateFlow<Entitlement?>,
    private val canRequestAds: StateFlow<Boolean>,
    private val throttle: InterstitialThrottle = InterstitialThrottle()
) : Interstitials {
    private var ad: InterstitialAd? = null
    private var loading = false
    private var host = WeakReference<Activity>(null)

    /** The foreground activity to present from; set by `MainActivity`. */
    fun attach(activity: Activity) {
        host = WeakReference(activity)
    }

    private fun allowed() = AdsPolicy.showInterstitial(entitlement.value, canRequestAds.value)

    override fun preload() {
        val activity = host.get() ?: return
        if (!allowed() || ad != null || loading) return
        loading = true
        InterstitialAd.load(
            activity.applicationContext,
            BuildConfig.AD_UNIT_ID_INTERSTITIAL,
            AdConsent.request(),
            object : InterstitialAdLoadCallback() {
                override fun onAdLoaded(loaded: InterstitialAd) {
                    loading = false
                    ad = loaded
                }

                // Deliberately logged: a unit that never fills looks exactly like a user who never
                // reached a break.
                override fun onAdFailedToLoad(error: LoadAdError) {
                    loading = false
                    Log.w(TAG, "Interstitial failed: ${error.code} ${error.message}")
                    Track.event(TrackEvents.INTERSTITIAL_FAILED, mapOf("error" to error.message))
                }
            }
        )
    }

    override fun onLeavePractice(answered: Boolean) {
        if (answered) showIfReady()
    }

    override fun onChallengeFinished() = showIfReady()

    private fun showIfReady() {
        if (!allowed() || !throttle.isOpen()) return
        val activity = host.get()
        val loaded = ad
        if (activity == null || loaded == null) {
            preload() // not ready: warm up for next time
            return
        }
        if (!throttle.tryAcquire()) return
        ad = null
        loaded.fullScreenContentCallback = object : FullScreenContentCallback() {
            override fun onAdDismissedFullScreenContent() = preload()

            override fun onAdFailedToShowFullScreenContent(error: AdError) = preload()
        }
        loaded.show(activity)
        Track.event(TrackEvents.INTERSTITIAL_SHOWN)
    }

    private companion object {
        const val TAG = "JDAds"
    }
}
