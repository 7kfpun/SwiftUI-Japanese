package com.kfpun.japanesedaily.billing

import android.app.Activity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Sells the plans at made-up prices without Play, in memory: debug builds only
 * ([ProGraph.useDemoBilling], launched with `--ez demo_billing true`). Every purchase succeeds at
 * once and is gone on the next launch. Used for screenshots and UI checks on emulators without Play.
 */
class DemoBillingGateway : BillingGateway {
    private val updates = MutableSharedFlow<PurchasesResult>(extraBufferCapacity = 16)
    override val purchaseUpdates: Flow<PurchasesResult> = updates.asSharedFlow()

    private val purchases = mutableListOf<OwnedPurchase>()

    override suspend fun queryOffers() = OffersResult(
        BillingStatus.OK,
        listOf(
            offer(ProPlan.ONE_MONTH, 2_990_000),
            offer(ProPlan.THREE_MONTHS, 7_990_000),
            offer(ProPlan.SIX_MONTHS, 13_990_000),
            offer(ProPlan.TWELVE_MONTHS, 22_990_000),
            offer(ProPlan.LIFETIME, 39_990_000)
        )
    )

    override suspend fun queryPurchases() = PurchasesResult(
        BillingStatus.OK,
        synchronized(purchases) { purchases.toList() }
    )

    override suspend fun acknowledge(purchaseToken: String): BillingStatus {
        synchronized(purchases) {
            purchases.replaceAll { if (it.purchaseToken == purchaseToken) it.copy(isAcknowledged = true) else it }
        }
        return BillingStatus.OK
    }

    override fun launcher(activity: Activity) = PurchaseLauncher { offer, _ ->
        val purchase = OwnedPurchase(
            productIds = listOf(offer.productId),
            state = OwnedPurchase.State.PURCHASED,
            isAcknowledged = false,
            purchaseToken = "demo-${offer.plan.analyticsName}"
        )
        synchronized(purchases) {
            purchases.clear()
            purchases += purchase
        }
        updates.tryEmit(PurchasesResult(BillingStatus.OK, listOf(purchase)))
        BillingStatus.OK
    }

    private fun offer(plan: ProPlan, micros: Long) = PlanOffer(
        plan = plan,
        productId = plan.productId,
        offerToken = if (plan.isSubscription) "demo-${plan.analyticsName}" else "",
        formattedPrice = "$" + "%.2f".format(micros / MICROS),
        priceMicros = micros,
        currencyCode = "USD"
    )

    private companion object {
        const val MICROS = 1_000_000.0
    }
}
