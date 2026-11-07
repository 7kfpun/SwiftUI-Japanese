package com.kfpun.japanesedaily.billing

import android.util.Log
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.audio.PremiumStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** The app's [ProRepository], for composables that show or hide something for Pro (the ad banners). */
val LocalPro = androidx.compose.runtime.staticCompositionLocalOf<ProRepository?> { null }

/** What the user holds. Only [PRO] unlocks anything; [PENDING] waits on Play. */
enum class Entitlement { FREE, PENDING, PRO }

enum class PurchaseOutcome {
    PURCHASED,

    /** Paid with a slow method; Pro turns on when Play confirms it. */
    PENDING,

    /** The sheet was closed. */
    NOT_COMPLETED,
    FAILED
}

/** The four ways a Restore tap can end, reported as `outcome` on the `restore` event (iOS `RestoreOutcome`). */
enum class RestoreOutcome(val analyticsName: String) {
    /** Already Pro before the tap: it changed nothing, and nothing was wrong. */
    ALREADY_PREMIUM("already_premium"),
    RESTORED("restored"),

    /** Play answered and holds no purchase: the wrong Google account, or nothing was ever bought. */
    NOTHING_FOUND("nothing_found"),

    /** Play couldn't be reached. */
    FAILED("failed"),

    /** A slow payment that Play hasn't confirmed yet. */
    PENDING("pending")
}

/**
 * The one source of Pro (iOS: `Store.isPremium`), read by the gating, the audio rates and the ads.
 *
 * Pro follows Play rather than a flag set once on purchase: Play's purchase list leaves out
 * expired, refunded, revoked and on-hold subscriptions, so re-reading it on every start
 * ([refresh]) turns Pro off when any of those happen. A cancelled subscription stays listed, and
 * Pro, until its period ends; a lifetime purchase stays for good. When Play can't be reached the
 * last confirmed value is kept, so a paying user offline doesn't get ads.
 *
 * Purchases are acknowledged as soon as they are seen; Play refunds any left unacknowledged for
 * three days, so a failed acknowledgement is retried on the next [refresh].
 */
class ProRepository(private val gateway: BillingGateway, private val store: EntitlementStore, scope: CoroutineScope) :
    PremiumStatus {
    private val state = MutableStateFlow<Entitlement?>(null)

    /** Null until the saved value is read (ads stay hidden till then); after that, never null. */
    val entitlement: StateFlow<Entitlement?> = state.asStateFlow()

    val isPro: Flow<Boolean> = entitlement.filterNotNull().map { it == Entitlement.PRO }.distinctUntilChanged()

    override val isPremium: Boolean get() = state.value == Entitlement.PRO

    private val lock = Mutex()
    private var loaded = false

    /** The active subscription purchase, so buying another plan switches it rather than adding one. */
    private var ownedSubscriptionToken: String? = null
    private val acknowledged = mutableSetOf<String>()

    /** Updates after [handleUpdate] has applied them, for [purchase] to wait on. */
    private val appliedUpdates = MutableSharedFlow<PurchasesResult>(extraBufferCapacity = 16)

    init {
        scope.launch { lock.withLock { loadSaved() } }
        scope.launch {
            gateway.purchaseUpdates.collect { update ->
                handleUpdate(update)
                appliedUpdates.emit(update)
            }
        }
    }

    /** Re-reads Pro from Play: on every app start, and after a purchase or restore. */
    suspend fun refresh(): Entitlement? {
        val result = gateway.queryPurchases()
        lock.withLock {
            loadSaved()
            if (result.status == BillingStatus.OK) apply(result.purchases)
        }
        return state.value
    }

    suspend fun queryOffers(): OffersResult = gateway.queryOffers()

    /** Play's purchase sheet launcher for [activity]. */
    fun launcher(activity: android.app.Activity): PurchaseLauncher = gateway.launcher(activity)

    suspend fun purchase(offer: PlanOffer, launcher: PurchaseLauncher): PurchaseOutcome = coroutineScope {
        // Listen before the sheet opens, so a fast result isn't missed.
        val update = async(start = CoroutineStart.UNDISPATCHED) { appliedUpdates.first() }
        val oldToken = if (offer.plan.isSubscription) lock.withLock { ownedSubscriptionToken } else null
        val launched = launcher.launch(offer, oldToken)
        if (launched != BillingStatus.OK) {
            update.cancel()
            return@coroutineScope launchFailed(launched)
        }
        val result = update.await()
        when (result.status) {
            BillingStatus.OK -> {
                val ours = result.purchases.filter { it.isPro }
                when {
                    ours.any { it.state == OwnedPurchase.State.PURCHASED } -> PurchaseOutcome.PURCHASED
                    ours.any { it.state == OwnedPurchase.State.PENDING } -> PurchaseOutcome.PENDING
                    state.value == Entitlement.PRO -> PurchaseOutcome.PURCHASED
                    else -> PurchaseOutcome.FAILED
                }
            }

            else -> launchFailed(result.status)
        }
    }

    suspend fun restore(): RestoreOutcome {
        val was = state.value
        val result = gateway.queryPurchases()
        if (result.status != BillingStatus.OK) return RestoreOutcome.FAILED
        lock.withLock {
            loadSaved()
            apply(result.purchases)
        }
        return when {
            state.value == Entitlement.PRO && was == Entitlement.PRO -> RestoreOutcome.ALREADY_PREMIUM
            state.value == Entitlement.PRO -> RestoreOutcome.RESTORED
            state.value == Entitlement.PENDING -> RestoreOutcome.PENDING
            else -> RestoreOutcome.NOTHING_FOUND
        }
    }

    private suspend fun launchFailed(status: BillingStatus): PurchaseOutcome = when (status) {
        BillingStatus.USER_CANCELED -> PurchaseOutcome.NOT_COMPLETED

        // Bought on another device, or Play hasn't told us yet.
        BillingStatus.ITEM_ALREADY_OWNED -> when (restore()) {
            RestoreOutcome.RESTORED, RestoreOutcome.ALREADY_PREMIUM -> PurchaseOutcome.PURCHASED
            RestoreOutcome.PENDING -> PurchaseOutcome.PENDING
            else -> PurchaseOutcome.FAILED
        }

        else -> PurchaseOutcome.FAILED
    }

    /**
     * A purchase from the sheet, or a pending one completing. The update only carries that
     * purchase, so the full list is re-read; if Play can't give it, the update alone can still turn
     * Pro on, never off.
     */
    private suspend fun handleUpdate(update: PurchasesResult) {
        if (update.status != BillingStatus.OK) return
        val full = gateway.queryPurchases()
        lock.withLock {
            loadSaved()
            if (full.status == BillingStatus.OK) {
                val tokens = full.purchases.map { it.purchaseToken }.toSet()
                apply(full.purchases + update.purchases.filter { it.purchaseToken !in tokens })
            } else {
                acknowledgeNew(update.purchases)
                val fromUpdate = entitlementOf(update.purchases)
                if (fromUpdate.ordinal > (state.value ?: Entitlement.FREE).ordinal) {
                    save(fromUpdate, tierOf(update.purchases))
                }
            }
        }
    }

    /** Call with [lock] held. */
    private suspend fun apply(purchases: List<OwnedPurchase>) {
        acknowledgeNew(purchases)
        ownedSubscriptionToken = purchases
            .firstOrNull { it.isPro && !it.isLifetime && it.state == OwnedPurchase.State.PURCHASED }
            ?.purchaseToken
        save(entitlementOf(purchases), tierOf(purchases))
    }

    private suspend fun acknowledgeNew(purchases: List<OwnedPurchase>) {
        purchases
            .filter { it.isPro && it.state == OwnedPurchase.State.PURCHASED && !it.isAcknowledged }
            .filter { it.purchaseToken !in acknowledged }
            .forEach { purchase ->
                if (gateway.acknowledge(purchase.purchaseToken) == BillingStatus.OK) {
                    acknowledged += purchase.purchaseToken
                } else {
                    Log.w(TAG, "Acknowledge failed; retried on the next refresh")
                }
            }
    }

    /** Call with [lock] held. A fresh install with nothing saved starts free. */
    private suspend fun loadSaved() {
        if (loaded) return
        loaded = true
        if (state.value == null) {
            val saved = runCatching { store.read() }.getOrNull() ?: Entitlement.FREE
            state.value = saved
            tier = if (saved == Entitlement.PRO) TIER_CACHED else TIER_NONE
            Track.setPremium(saved == Entitlement.PRO, tier)
        }
    }

    /** The analytics tier of the last confirmed purchase list (`lifetime`, `subscription`, `cached`, `none`): Settings and the survey read it. */
    @Volatile
    var tier: String = TIER_NONE
        private set

    private suspend fun save(entitlement: Entitlement, tier: String) {
        this.tier = tier
        Track.setPremium(entitlement == Entitlement.PRO, tier)
        if (state.value == entitlement) return
        state.value = entitlement
        runCatching { store.write(entitlement) }.onFailure { Log.w(TAG, "Couldn't save Pro", it) }
    }

    companion object {
        private const val TAG = "JDPro"
        private const val TIER_NONE = "none"
        private const val TIER_CACHED = "cached"
        private const val TIER_SUBSCRIPTION = "subscription"

        fun entitlementOf(purchases: List<OwnedPurchase>): Entitlement {
            val ours = purchases.filter { it.isPro }
            return when {
                ours.any { it.state == OwnedPurchase.State.PURCHASED } -> Entitlement.PRO
                ours.any { it.state == OwnedPurchase.State.PENDING } -> Entitlement.PENDING
                else -> Entitlement.FREE
            }
        }

        /** The analytics tier. Lifetime outranks a subscription held beside it, as on iOS `Store.tier`. */
        fun tierOf(purchases: List<OwnedPurchase>): String {
            val owned = purchases.filter { it.isPro && it.state == OwnedPurchase.State.PURCHASED }
            return when {
                owned.isEmpty() -> TIER_NONE
                owned.any { it.isLifetime } -> ProPlan.LIFETIME.analyticsName
                else -> TIER_SUBSCRIPTION
            }
        }
    }
}
