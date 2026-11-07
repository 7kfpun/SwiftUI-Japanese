package com.kfpun.japanesedaily.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import com.kfpun.japanesedaily.ads.AdConsent
import com.kfpun.japanesedaily.ads.AdMobInterstitials
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.audio.PremiumStatus
import com.kfpun.japanesedaily.billing.BillingGateway
import com.kfpun.japanesedaily.billing.DataStoreEntitlementStore
import com.kfpun.japanesedaily.billing.DemoBillingGateway
import com.kfpun.japanesedaily.billing.InMemoryEntitlementStore
import com.kfpun.japanesedaily.billing.PaywallController
import com.kfpun.japanesedaily.billing.PlayBillingGateway
import com.kfpun.japanesedaily.billing.ProRepository
import com.kfpun.japanesedaily.billing.UnavailableBillingGateway
import com.kfpun.japanesedaily.data.prefs.Prefs
import com.kfpun.japanesedaily.data.progress.PracticeProgress
import com.kfpun.japanesedaily.data.progress.ProgressDatabase
import com.kfpun.japanesedaily.data.progress.ProgressRepository
import com.kfpun.japanesedaily.data.progress.Streak
import com.kfpun.japanesedaily.data.vocab.AndroidAssetSource
import com.kfpun.japanesedaily.data.vocab.AssetSource
import com.kfpun.japanesedaily.data.vocab.KanaData
import com.kfpun.japanesedaily.data.vocab.VocabStore
import com.kfpun.japanesedaily.rating.RatingCoordinator
import com.kfpun.japanesedaily.settings.Reminders
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * The one entry point other features inject from: bundled content ([vocab], [kana]), progress
 * ([progress], [practice]) and preferences ([prefs]). Get it with [from]; tests build one directly
 * with an in-memory database and a file-backed [AssetSource].
 *
 * Everything lives on the device: the database and the preferences file are excluded from every
 * backup (`data_extraction_rules.xml`) and `allowBackup` is false.
 */
class AppContainer(
    assets: AssetSource,
    database: ProgressDatabase,
    preferences: DataStore<Preferences>,
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    val course: Course = Course.current,
    onFirstAnswerToday: (Streak) -> Unit = ::trackStudyDay,
    billing: BillingGateway = UnavailableBillingGateway,
    entitlements: com.kfpun.japanesedaily.billing.EntitlementStore = InMemoryEntitlementStore()
) {
    val vocab = VocabStore(assets, course)
    val kana = KanaData(assets)
    val progress = ProgressRepository(database, vocab, course, onFirstAnswerToday = onFirstAnswerToday)
    val practice = PracticeProgress(database.practice(), scope)
    val prefs = Prefs(preferences)

    /** The one source of Pro (FOX-158): Play Billing, re-read on every start, cached on the device. */
    val pro = ProRepository(billing, entitlements, scope)

    /** Gating and the audio rates read this; it is [pro]. */
    val premium: PremiumStatus get() = pro

    val paywall = PaywallController(pro)

    /** The ad hooks: the interstitial for `onLeavePractice` / `onChallengeFinished`, shown for free users only. */
    val interstitials = AdMobInterstitials(pro.entitlement, AdConsent.canRequestAds)

    /** The hook gated screens call to sell Pro. [source] is a `PaywallSource` key. A no-op for Pro users. */
    fun openPaywall(source: String, lesson: Int? = null) = paywall.open(source, lesson)

    /** Leaving Practice. Shows an interstitial (at most one per 3 minutes) only if [answered] anything. */
    fun onLeavePractice(answered: Boolean) = interstitials.onLeavePractice(answered)

    /** A Challenge run finished. Never call it mid-run. */
    fun onChallengeFinished() = interstitials.onChallengeFinished()

    /** The rating prompt. The ladder calls `rating.onRungPassed(totalPassed)` after every passed rung. */
    val rating = RatingCoordinator(prefs, scope)

    /** Decodes the course data and loads Practice stages off the main thread, at launch. */
    fun preload() {
        scope.launch {
            vocab.preload()
            practice.load()
        }
        // Pro is re-read from Play on every start.
        scope.launch { pro.refresh() }
    }

    companion object {
        @Volatile
        private var instance: AppContainer? = null

        @Volatile
        private var demoBilling = false

        /** Debug builds only (`--ez demo_billing true`): sell made-up plans without Play. Before the first [from]. */
        fun useDemoBilling() {
            if (com.kfpun.japanesedaily.BuildConfig.DEBUG && instance == null) demoBilling = true
        }

        fun from(context: Context): AppContainer = instance ?: synchronized(this) {
            instance ?: create(context.applicationContext).also { instance = it }
        }

        private fun create(context: Context): AppContainer = AppContainer(
            assets = AndroidAssetSource(context.assets),
            database = ProgressDatabase.open(context),
            preferences = PreferenceDataStoreFactory.create {
                context.filesDir.resolve("datastore/prefs.preferences_pb")
            },
            billing = if (demoBilling) DemoBillingGateway() else PlayBillingGateway(context),
            entitlements = DataStoreEntitlementStore(context),
            // Studying today cancels today's reminder: the plan is re-derived from the new streak.
            onFirstAnswerToday = { streak ->
                // study_day (FOX-156), then today's reminder is no longer a nag (FOX-159).
                trackStudyDay(streak)
                Reminders.reschedule(context)
            }
        )
    }
}

/**
 * iOS logs `study_day` when the first answer of a day creates a `StudyDay`: one event per studied day,
 * carrying how long the run is (`streak`) and the record (`best`). Behavioural counts, never an identifier.
 */
internal fun trackStudyDay(streak: Streak, track: (String, Map<String, Any?>) -> Unit = Track::event) =
    track(TrackEvents.STUDY_DAY, mapOf("streak" to streak.current, "best" to streak.best))
