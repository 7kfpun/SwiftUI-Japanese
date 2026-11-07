package com.kfpun.japanesedaily.analytics

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import com.kfpun.japanesedaily.locale.AppLocale

/**
 * What [Track] needs from Firebase. [FirebaseSink] is the real one; tests install a fake.
 * Nothing outside this package may import Firebase Analytics or Crashlytics (`Track` only).
 */
interface TrackSink {
    fun logEvent(name: String, params: Map<String, Any>)

    fun setUserProperty(name: String, value: String)

    /** Analytics and Crashlytics together, as iOS `Track.setExcluded` does. */
    fun setCollectionEnabled(enabled: Boolean)

    /** A Crashlytics breadcrumb. */
    fun breadcrumb(message: String)
}

/**
 * The one seam for analytics and crash reporting, ported from iOS `Track`
 * (`nihongo/Ads/AppBootstrap.swift`, `context/08-analytics.md`).
 *
 * - Every name ships prefixed [PREFIX], the same second-generation prefix as iOS, so Android and iOS
 *   events land in the same reports.
 * - `is_premium` rides on every event, from the flag cached by [setPremium].
 * - **A no-op without Firebase**: with no `google-services.json` (CI, a fresh clone) [install] finds no
 *   Firebase app, [sink] stays null, and every call below returns quietly. A failing Firebase call is
 *   swallowed too: analytics must never crash the app.
 * - **No identifier of our own**: no `setUserId`, no advertising id, no minted install id. Firebase's
 *   own app-instance id is the accepted boundary (Data safety form, FOX-161).
 * - The per-device opt-out ([setExcluded], 7 taps on the Settings version line) persists in the
 *   `settings` prefs under iOS's key and stops collection at once.
 */
object Track {
    const val PREFIX = "nihongo_2026_"

    /** Same key as iOS `Pref.analyticsExcluded`. */
    internal const val EXCLUDED_KEY = "analyticsExcluded"

    @Volatile
    internal var sink: TrackSink? = null

    @Volatile
    private var isPremium = false

    @Volatile
    private var lastProfile: Map<String, String> = emptyMap()

    @Volatile
    private var prefs: SharedPreferences? = null

    /** Whether the build collects at all (release yes, debug no unless opted in), set by [install]. */
    @Volatile
    private var collectionAllowed = false

    @Volatile
    private var lastScreenName = ""

    /** The last screen shown, for the survey's `last_screen` (FOX-157). Recorded even when excluded. */
    val lastScreen: String get() = lastScreenName

    /**
     * Call once from `Application.onCreate`. [sink] is null when Firebase is not configured.
     * [collectionAllowed] is the build's own default (`BuildConfig.FIREBASE_COLLECTION`); the
     * opt-out can only turn collection off from there, never on past it.
     */
    fun install(context: Context, sink: TrackSink?, collectionAllowed: Boolean) =
        install(context.getSharedPreferences(AppLocale.PREFS, Context.MODE_PRIVATE), sink, collectionAllowed)

    internal fun install(prefs: SharedPreferences, sink: TrackSink?, collectionAllowed: Boolean) {
        this.prefs = prefs
        this.collectionAllowed = collectionAllowed
        this.sink = sink
        apply(isExcluded)
    }

    /** Log a custom event (prefixed). No-op until Firebase is configured, and while excluded. */
    fun event(name: String, params: Map<String, Any?> = emptyMap()) {
        val sink = sink ?: return
        if (!collectionAllowed || isExcluded) return
        val merged = TrackParams.normalise(params + ("is_premium" to isPremium))
        runCatching { sink.logEvent(PREFIX + name, merged) }
    }

    /**
     * A screen was shown: one event named `screen` with a `name` param (not a Firebase screen view). Also
     * remembered as [lastScreen], deliberately outside the opt-out: a feedback report needs its
     * context even from an excluded device.
     */
    fun screen(name: String, params: Map<String, Any?> = emptyMap()) {
        lastScreenName = name.take(SCREEN_NAME_LIMIT)
        event(SCREEN_EVENT, params + ("name" to name))
    }

    /** `user_type` = premium/free and `premium_tier` = lifetime/1m/3m/6m/12m/none. */
    fun setPremium(isPremium: Boolean, tier: String) {
        this.isPremium = isPremium
        property("user_type", if (isPremium) "premium" else "free")
        property("premium_tier", tier)
    }

    /**
     * What the learner chose, which GA4 cannot work out itself (see iOS `Track.setProfile`). Idempotent:
     * unchanged values are skipped, so callers may fire it as often as is convenient.
     */
    fun setProfile(
        uiLanguage: String,
        meaningLanguage: String,
        knowsKana: String?,
        goal: String?,
        earnedFirstGroup: Boolean
    ) {
        val values = profile(uiLanguage, meaningLanguage, knowsKana, goal, earnedFirstGroup)
        if (values == lastProfile) return
        lastProfile = values
        values.forEach { (name, value) -> property(name, value) }
    }

    /**
     * The properties [setProfile] sends. Pure, so the names, the `unanswered` fallbacks and the 36-character
     * clamp (GA4 truncates silently past it) can be tested without Firebase.
     */
    fun profile(
        uiLanguage: String,
        meaningLanguage: String,
        knowsKana: String?,
        goal: String?,
        earnedFirstGroup: Boolean
    ): Map<String, String> {
        fun clamped(v: String) = v.take(USER_PROPERTY_LIMIT)
        return mapOf(
            "ui_language" to clamped(uiLanguage),
            "meaning_language" to clamped(meaningLanguage),
            // "unanswered" rather than omitting the key: a property never set is indistinguishable in
            // GA4 from one whose owner skipped the question.
            "knows_kana" to clamped(knowsKana ?: "unanswered"),
            "learning_goal" to clamped(goal ?: "unanswered"),
            "earned_first_group" to if (earnedFirstGroup) "true" else "false"
        )
    }

    /**
     * Per-device analytics opt-out. Persists and applies at once, so switching it on mid-session stops
     * collection right away.
     */
    fun setExcluded(excluded: Boolean) {
        prefs?.edit { putBoolean(EXCLUDED_KEY, excluded) }
        // Profile values set while excluded never went out; let the next setProfile resend them.
        if (!excluded) lastProfile = emptyMap()
        apply(excluded)
    }

    val isExcluded: Boolean
        get() = prefs?.getBoolean(EXCLUDED_KEY, false) ?: false

    /** A bundled clip was missing so playback fell back to TTS: an event plus a Crashlytics breadcrumb. */
    fun audioMissing(item: String) {
        sink?.let { runCatching { it.breadcrumb("audio is missing: $item") } }
        event(TrackEvents.AUDIO_MISSING, mapOf("item" to item))
    }

    private fun property(name: String, value: String) {
        val sink = sink ?: return
        if (!collectionAllowed || isExcluded) return
        runCatching { sink.setUserProperty(name, value) }
    }

    private fun apply(excluded: Boolean) {
        val sink = sink ?: return
        runCatching { sink.setCollectionEnabled(collectionAllowed && !excluded) }
    }

    private const val SCREEN_EVENT = "screen"
    private const val SCREEN_NAME_LIMIT = 40
    private const val USER_PROPERTY_LIMIT = 36
}

/** Param values as GA4 takes them: numbers and strings only. */
internal object TrackParams {
    private const val VALUE_LIMIT = 100

    /**
     * iOS sends a Bool as an NSNumber, which GA4 reads as 1 or 0; Android's Bundle would drop it, so
     * booleans become 1L/0L here and the two platforms report the same value. Integers widen to Long,
     * floats to Double, everything else to a string cut at GA4's 100-character cap. Nulls are dropped.
     */
    fun normalise(params: Map<String, Any?>): Map<String, Any> = buildMap {
        for ((key, value) in params) {
            put(
                key,
                when (value) {
                    null -> continue
                    is Boolean -> if (value) 1L else 0L
                    is Int -> value.toLong()
                    is Long -> value
                    is Short -> value.toLong()
                    is Byte -> value.toLong()
                    is Float -> value.toDouble()
                    is Double -> value
                    else -> value.toString().take(VALUE_LIMIT)
                }
            )
        }
    }
}
