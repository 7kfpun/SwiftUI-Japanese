package com.kfpun.japanesedaily.billing

import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.audio.PremiumStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Where the paywall was opened from (`source`) and the lesson that triggered it, when one did. */
data class PaywallRequest(val source: String, val lesson: Int? = null)

/**
 * Whether the paywall is up. [open] is the `openPaywall(source)` hook the gated screens call; it does
 * nothing for a Pro user. `MainActivity` shows [PaywallHost] for the current [request].
 */
class PaywallController(private val premium: PremiumStatus) {
    private val current = MutableStateFlow<PaywallRequest?>(null)
    val request: StateFlow<PaywallRequest?> = current.asStateFlow()

    fun open(source: String, lesson: Int? = null) {
        if (premium.isPremium) return
        current.value = PaywallRequest(source, lesson)
    }

    fun close() {
        current.value = null
    }
}

/** What a purchase or restore tells the user, shown as one line under the plans. */
enum class PaywallMessage { PENDING, FAILED, NOTHING_FOUND }

data class PaywallState(
    val offers: List<PlanOffer> = emptyList(),
    val isLoading: Boolean = false,
    val didAttempt: Boolean = false,
    /** The plan the Continue button will buy. Choosing and paying are two steps. */
    val selected: ProPlan? = null,
    val isPurchasing: Boolean = false,
    val message: PaywallMessage? = null
) {
    val unavailable: Boolean get() = didAttempt && !isLoading && offers.isEmpty()
    val subscriptions: List<PlanOffer> get() = PaywallPricing.subscriptions(offers)
    val lifetime: PlanOffer? get() = PaywallPricing.lifetime(offers)
}

/**
 * The paywall's logic (port of `PaywallView` + `Store.purchase`/`restore`), free of Compose so it is
 * tested directly. Every event carries `source` (and `lesson` when known) so conversion groups by
 * entry point: the iOS funnel stops at `paywall_shown`, this one does not.
 */
class PaywallModel(private val pro: ProRepository, private val scope: CoroutineScope, val request: PaywallRequest) {
    private val flow = MutableStateFlow(PaywallState())
    val state: StateFlow<PaywallState> = flow.asStateFlow()

    private val params: Map<String, Any?>
        get() = buildMap {
            put("source", request.source)
            request.lesson?.let { put("lesson", it) }
        }

    fun shown() = Track.event(TrackEvents.PAYWALL_SHOWN, params)

    fun dismissed() = Track.event(TrackEvents.PAYWALL_DISMISSED, params + ("purchased" to pro.isPremium))

    fun unavailableShown() = Track.event(TrackEvents.PAYWALL_UNAVAILABLE, params)

    fun retry() {
        Track.event(TrackEvents.PAYWALL_RETRY, params)
        load()
    }

    /** Fetches the plans. Opening the paywall retries, so a user who started offline isn't stuck. */
    fun load() {
        if (flow.value.isLoading) return
        flow.update { it.copy(isLoading = true) }
        scope.launch {
            val offers = pro.queryOffers().offers
            flow.update { current ->
                current.copy(
                    offers = offers,
                    isLoading = false,
                    didAttempt = true,
                    selected = current.selected?.takeIf { plan -> offers.any { it.plan == plan } }
                        ?: (PaywallPricing.bestValue(offers) ?: offers.firstOrNull())?.plan
                )
            }
        }
    }

    fun select(plan: ProPlan) = flow.update { if (it.isPurchasing) it else it.copy(selected = plan, message = null) }

    fun purchase(launcher: PurchaseLauncher) {
        val current = flow.value
        val offer = current.offers.firstOrNull { it.plan == current.selected } ?: return
        if (current.isPurchasing) return
        flow.update { it.copy(isPurchasing = true, message = null) }
        val base = mapOf("tier" to offer.plan.analyticsName, "source" to request.source)
        Track.event(TrackEvents.PURCHASE_START, base)
        scope.launch {
            val outcome = pro.purchase(offer, launcher)
            val (event, extra) = when (outcome) {
                PurchaseOutcome.PURCHASED -> TrackEvents.PURCHASE_SUCCESS to emptyMap()
                PurchaseOutcome.NOT_COMPLETED -> TrackEvents.PURCHASE_FAILED to mapOf("reason" to "cancelled")
                PurchaseOutcome.PENDING -> TrackEvents.PURCHASE_FAILED to mapOf("reason" to "pending")
                PurchaseOutcome.FAILED -> TrackEvents.PURCHASE_FAILED to mapOf("reason" to "error")
            }
            Track.event(event, base + extra)
            flow.update {
                it.copy(
                    isPurchasing = false,
                    message = when (outcome) {
                        PurchaseOutcome.PENDING -> PaywallMessage.PENDING
                        PurchaseOutcome.FAILED -> PaywallMessage.FAILED
                        else -> null
                    }
                )
            }
        }
    }

    fun restore() {
        scope.launch {
            val outcome = pro.restore()
            Track.event(
                TrackEvents.RESTORE,
                mapOf("outcome" to outcome.analyticsName, "source" to request.source, "premium" to pro.isPremium)
            )
            flow.update {
                it.copy(
                    message = when (outcome) {
                        RestoreOutcome.NOTHING_FOUND -> PaywallMessage.NOTHING_FOUND
                        RestoreOutcome.FAILED -> PaywallMessage.FAILED
                        RestoreOutcome.PENDING -> PaywallMessage.PENDING
                        else -> null
                    }
                )
            }
        }
    }
}
