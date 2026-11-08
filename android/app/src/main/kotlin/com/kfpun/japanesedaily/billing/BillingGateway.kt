package com.kfpun.japanesedaily.billing

import android.app.Activity
import kotlinx.coroutines.flow.Flow

/** A Play Billing response, reduced to what the app acts on. */
enum class BillingStatus {
    OK,
    USER_CANCELED,
    ITEM_ALREADY_OWNED,

    /** Play can't be reached right now (offline, no Play, service down): keep what we know. */
    UNAVAILABLE,
    ERROR
}

/** A plan as Play sells it: its own price, in the buyer's currency. */
data class PlanOffer(
    val plan: ProPlan,
    val productId: String,
    /** A subscription's offer token; empty for the one-time lifetime product. */
    val offerToken: String,
    val formattedPrice: String,
    val priceMicros: Long,
    val currencyCode: String
)

/** A purchase Play reports, for a product of ours or not. */
data class OwnedPurchase(
    val productIds: List<String>,
    val state: State,
    val isAcknowledged: Boolean,
    val purchaseToken: String
) {
    enum class State { PURCHASED, PENDING, UNSPECIFIED }

    val isPro: Boolean get() = productIds.any { it in ProProducts.productIds }

    val isLifetime: Boolean get() = ProProducts.lifetimeId in productIds
}

data class PurchasesResult(val status: BillingStatus, val purchases: List<OwnedPurchase> = emptyList())

data class OffersResult(val status: BillingStatus, val offers: List<PlanOffer> = emptyList())

/**
 * Starts Play's purchase sheet. Its result arrives later on [BillingGateway.purchaseUpdates]; the
 * returned status only says whether the sheet opened. [oldPurchaseToken] switches an existing
 * subscription plan instead of buying a second one (never set for lifetime).
 */
fun interface PurchaseLauncher {
    fun launch(offer: PlanOffer, oldPurchaseToken: String?): BillingStatus
}

/** The Play Billing calls Pro needs, behind an interface so tests use a fake. */
interface BillingGateway {
    /** Every `PurchasesUpdatedListener` call: purchases from the sheet, pending ones completing. */
    val purchaseUpdates: Flow<PurchasesResult>

    /** The sellable plans: the four base plans and lifetime, cheapest first. */
    suspend fun queryOffers(): OffersResult

    /**
     * Owned Pro products: active subscriptions and the lifetime purchase. Play leaves out expired,
     * refunded, revoked and on-hold subscriptions. [BillingStatus.OK] only when both queries answered.
     */
    suspend fun queryPurchases(): PurchasesResult

    suspend fun acknowledge(purchaseToken: String): BillingStatus

    fun launcher(activity: Activity): PurchaseLauncher
}

/** Play can't be reached: sells nothing and owns nothing. What a container built without Play gets. */
object UnavailableBillingGateway : BillingGateway {
    override val purchaseUpdates: Flow<PurchasesResult> = kotlinx.coroutines.flow.emptyFlow()

    override suspend fun queryOffers() = OffersResult(BillingStatus.UNAVAILABLE)

    override suspend fun queryPurchases() = PurchasesResult(BillingStatus.UNAVAILABLE)

    override suspend fun acknowledge(purchaseToken: String) = BillingStatus.UNAVAILABLE

    override fun launcher(activity: Activity) = PurchaseLauncher { _, _ -> BillingStatus.UNAVAILABLE }
}
