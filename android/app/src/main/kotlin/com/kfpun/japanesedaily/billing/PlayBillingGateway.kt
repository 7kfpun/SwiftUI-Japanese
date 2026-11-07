package com.kfpun.japanesedaily.billing

import android.app.Activity
import android.content.Context
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClient.BillingResponseCode
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * [BillingGateway] over the Play Billing Library: the subscription's base plans and the lifetime
 * in-app product. Verification is on the device (Play's signed purchase list), as on iOS.
 */
class PlayBillingGateway(context: Context) : BillingGateway {
    private val updates = MutableSharedFlow<PurchasesResult>(extraBufferCapacity = 16)
    override val purchaseUpdates: Flow<PurchasesResult> = updates.asSharedFlow()

    private val client: BillingClient = BillingClient.newBuilder(context.applicationContext)
        .setListener { result, purchases ->
            updates.tryEmit(PurchasesResult(result.status(), purchases.orEmpty().map { it.toOwned() }))
        }
        // Required by the library; also what lets lifetime be paid with a slow method.
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    private val connectLock = Mutex()

    /** From the last [queryOffers]; the purchase sheet needs Play's own object. */
    private val productDetails = ConcurrentHashMap<String, ProductDetails>()

    private suspend fun connect(): BillingStatus = connectLock.withLock {
        if (client.isReady) return BillingStatus.OK
        suspendCancellableCoroutine { continuation ->
            val resumed = AtomicBoolean(false)
            client.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(result: BillingResult) {
                    if (resumed.compareAndSet(false, true)) continuation.resume(result.status())
                }

                override fun onBillingServiceDisconnected() {
                    if (resumed.compareAndSet(false, true)) continuation.resume(BillingStatus.UNAVAILABLE)
                }
            })
        }
    }

    private suspend fun details(type: String, id: String): Pair<BillingStatus, List<ProductDetails>> {
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder().setProductId(id).setProductType(type).build()
                )
            )
            .build()
        return suspendCancellableCoroutine { continuation ->
            client.queryProductDetailsAsync(params) { result, details ->
                continuation.resume(result.status() to details.productDetailsList)
            }
        }
    }

    override suspend fun queryOffers(): OffersResult {
        val connected = connect()
        if (connected != BillingStatus.OK) return OffersResult(connected)
        val (subStatus, subs) = details(BillingClient.ProductType.SUBS, ProProducts.subscriptionId)
        val (inAppStatus, inApp) = details(BillingClient.ProductType.INAPP, ProProducts.lifetimeId)
        // One side answering is enough to show something; both failing is "unavailable".
        if (subStatus != BillingStatus.OK && inAppStatus != BillingStatus.OK) return OffersResult(subStatus)
        (subs + inApp).forEach { productDetails[it.productId] = it }
        val subscriptionOffers = subs.flatMap { product ->
            product.subscriptionOfferDetails.orEmpty()
                // The base plan's own offer: no trial or intro price, as on iOS.
                .filter { it.offerId == null }
                .mapNotNull { offer ->
                    val plan = ProPlan.forBasePlan(offer.basePlanId) ?: return@mapNotNull null
                    val price = offer.pricingPhases.pricingPhaseList.lastOrNull() ?: return@mapNotNull null
                    PlanOffer(
                        plan = plan,
                        productId = product.productId,
                        offerToken = offer.offerToken,
                        formattedPrice = price.formattedPrice,
                        priceMicros = price.priceAmountMicros,
                        currencyCode = price.priceCurrencyCode
                    )
                }
        }
        val lifetimeOffers = inApp.mapNotNull { product ->
            val price = product.oneTimePurchaseOfferDetails ?: return@mapNotNull null
            PlanOffer(
                plan = ProPlan.LIFETIME,
                productId = product.productId,
                offerToken = "",
                formattedPrice = price.formattedPrice,
                priceMicros = price.priceAmountMicros,
                currencyCode = price.priceCurrencyCode
            )
        }
        return OffersResult(BillingStatus.OK, (subscriptionOffers + lifetimeOffers).sortedBy { it.plan.ordinal })
    }

    override suspend fun queryPurchases(): PurchasesResult {
        val connected = connect()
        if (connected != BillingStatus.OK) return PurchasesResult(connected)
        val subs = purchases(BillingClient.ProductType.SUBS)
        val inApp = purchases(BillingClient.ProductType.INAPP)
        // A partial answer must not turn Pro off, so anything short of both is a failure.
        val failed = listOf(subs, inApp).firstOrNull { it.status != BillingStatus.OK }
        return failed ?: PurchasesResult(BillingStatus.OK, subs.purchases + inApp.purchases)
    }

    private suspend fun purchases(type: String): PurchasesResult {
        val params = QueryPurchasesParams.newBuilder().setProductType(type).build()
        return suspendCancellableCoroutine { continuation ->
            client.queryPurchasesAsync(params) { result, purchases ->
                continuation.resume(PurchasesResult(result.status(), purchases.map { it.toOwned() }))
            }
        }
    }

    override suspend fun acknowledge(purchaseToken: String): BillingStatus {
        val connected = connect()
        if (connected != BillingStatus.OK) return connected
        val params = AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchaseToken).build()
        return suspendCancellableCoroutine { continuation ->
            client.acknowledgePurchase(params) { result -> continuation.resume(result.status()) }
        }
    }

    override fun launcher(activity: Activity): PurchaseLauncher = PurchaseLauncher { offer, oldPurchaseToken ->
        val details = productDetails[offer.productId]
        if (details == null || !client.isReady) return@PurchaseLauncher BillingStatus.UNAVAILABLE
        val product = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details)
        if (offer.offerToken.isNotEmpty()) product.setOfferToken(offer.offerToken)
        val params = BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(product.build()))
        if (oldPurchaseToken != null && offer.plan.isSubscription) {
            // Changing plan: the new one starts now, with the unused time credited.
            @Suppress("DEPRECATION")
            params.setSubscriptionUpdateParams(
                BillingFlowParams.SubscriptionUpdateParams.newBuilder()
                    .setOldPurchaseToken(oldPurchaseToken)
                    .setSubscriptionReplacementMode(
                        BillingFlowParams.SubscriptionUpdateParams.ReplacementMode.WITH_TIME_PRORATION
                    )
                    .build()
            )
        }
        client.launchBillingFlow(activity, params.build()).status()
    }

    private fun BillingResult.status(): BillingStatus {
        val status = when (responseCode) {
            BillingResponseCode.OK -> BillingStatus.OK

            BillingResponseCode.USER_CANCELED -> BillingStatus.USER_CANCELED

            BillingResponseCode.ITEM_ALREADY_OWNED -> BillingStatus.ITEM_ALREADY_OWNED

            BillingResponseCode.BILLING_UNAVAILABLE,
            BillingResponseCode.SERVICE_UNAVAILABLE,
            BillingResponseCode.SERVICE_DISCONNECTED,
            BillingResponseCode.NETWORK_ERROR -> BillingStatus.UNAVAILABLE

            else -> BillingStatus.ERROR
        }
        if (status != BillingStatus.OK && status != BillingStatus.USER_CANCELED) {
            Log.w(TAG, "Play Billing $responseCode: $debugMessage")
        }
        return status
    }

    private fun Purchase.toOwned() = OwnedPurchase(
        productIds = products,
        state = when (purchaseState) {
            Purchase.PurchaseState.PURCHASED -> OwnedPurchase.State.PURCHASED
            Purchase.PurchaseState.PENDING -> OwnedPurchase.State.PENDING
            else -> OwnedPurchase.State.UNSPECIFIED
        },
        isAcknowledged = isAcknowledged,
        purchaseToken = purchaseToken
    )

    private companion object {
        const val TAG = "JDBilling"
    }
}
