package com.kfpun.japanesedaily.billing

import android.app.Activity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/** A stand-in for the Play Billing client: the test decides what Play owns and how each call answers. */
class FakeBillingGateway : BillingGateway {
    private val updates = MutableSharedFlow<PurchasesResult>(extraBufferCapacity = 16)
    override val purchaseUpdates: Flow<PurchasesResult> = updates.asSharedFlow()

    var owned: List<OwnedPurchase> = emptyList()
    var purchasesStatus = BillingStatus.OK
    var offers: List<PlanOffer> = emptyList()
    var offersStatus = BillingStatus.OK
    var acknowledgeStatus = BillingStatus.OK
    val acknowledged = mutableListOf<String>()
    val launched = mutableListOf<Pair<PlanOffer, String?>>()

    /** What the purchase sheet does when launched: a result delivered on [purchaseUpdates], or none. */
    var onLaunch: (PlanOffer) -> Pair<BillingStatus, PurchasesResult?> = { BillingStatus.USER_CANCELED to null }

    override suspend fun queryOffers() = OffersResult(offersStatus, offers)

    override suspend fun queryPurchases() = PurchasesResult(
        purchasesStatus,
        if (purchasesStatus ==
            BillingStatus.OK
        ) {
            owned
        } else {
            emptyList()
        }
    )

    override suspend fun acknowledge(purchaseToken: String): BillingStatus {
        if (acknowledgeStatus == BillingStatus.OK) acknowledged += purchaseToken
        return acknowledgeStatus
    }

    override fun launcher(activity: Activity) = PurchaseLauncher { offer, oldToken ->
        launched += offer to oldToken
        val (status, result) = onLaunch(offer)
        if (result != null) {
            owned = owned + result.purchases
            updates.tryEmit(result)
        }
        status
    }

    companion object {
        fun purchase(
            productId: String,
            token: String = "token-$productId",
            state: OwnedPurchase.State = OwnedPurchase.State.PURCHASED,
            acknowledged: Boolean = false
        ) = OwnedPurchase(listOf(productId), state, acknowledged, token)

        fun offer(plan: ProPlan, dollars: Double) = PlanOffer(
            plan = plan,
            productId = plan.productId,
            offerToken = if (plan.isSubscription) "offer-${plan.analyticsName}" else "",
            formattedPrice = "$$dollars",
            priceMicros = (dollars * 1_000_000).toLong(),
            currencyCode = "USD"
        )
    }
}
