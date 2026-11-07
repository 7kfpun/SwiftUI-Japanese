package com.kfpun.japanesedaily.settings

import android.app.Activity
import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** What Settings (and the survey context) need to know about Pro. */
data class ProState(
    val isPremium: Boolean = false,
    /** `"lifetime"`, a subscription length such as `"3m"`, or `"none"`; the survey's `tier`. */
    val tier: String = "none",
    /** True where UMP says the privacy-options entry point must be offered (EEA/UK). */
    val privacyOptionsRequired: Boolean = false
)

/**
 * The seam to Pro: Play Billing, the paywall and UMP (FOX-158). Settings codes against this; until
 * FOX-158 assigns `AppContainer.pro` every action is a no-op and the state is free. The paywall and the
 * entitlement are not here: they are the `LocalOpenPaywall` and `LocalPremium` seams from the Lessons ticket,
 * so Settings opens the same paywall every gate does.
 */
interface ProActions {
    val state: StateFlow<ProState>

    /** Re-reads purchases from Play. */
    fun restore(source: String)

    /** Opens Play's subscription centre for this app. */
    fun manageSubscription(context: Context)

    /** Shows the UMP privacy-options form. Only offered when [ProState.privacyOptionsRequired]. */
    fun showPrivacyOptions(activity: Activity)

    /** The free, do-nothing default. */
    object None : ProActions {
        override val state: StateFlow<ProState> = MutableStateFlow(ProState())

        override fun restore(source: String) = Unit

        override fun manageSubscription(context: Context) = Unit

        override fun showPrivacyOptions(activity: Activity) = Unit
    }
}
