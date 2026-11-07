package com.kfpun.japanesedaily.billing

import com.kfpun.japanesedaily.data.Course

/**
 * The Play products behind Pro (port of `PremiumProduct`). iOS sells four subscriptions in one
 * group plus a lifetime unlock; Play's version of a group is one subscription with a base plan per
 * period, so a buyer holds one plan at a time and changing plan switches the same subscription.
 * The ids live on [Course.Products] and are pinned by `ProProductsTest`.
 */
object ProProducts {
    private val products get() = Course.current.products

    /** The Play subscription; its base plans are [ProPlan.basePlanId]. */
    val subscriptionId: String get() = products.subscription

    /** The one-time (non-consumable) lifetime product. */
    val lifetimeId: String get() = products.lifetime

    /** Everything that grants Pro: the entitlement scan accepts these and nothing else. */
    val productIds: Set<String> get() = setOf(subscriptionId, lifetimeId)
}

/**
 * A plan the paywall sells. [analyticsName] is the `tier` param on the purchase events, the same five
 * labels as iOS `Store.tierLabel` (`1m`, `3m`, `6m`, `12m`, `lifetime`), so reports read the same on
 * both platforms. [months] is 0 for the lifetime product.
 */
enum class ProPlan(val analyticsName: String, val months: Int) {
    ONE_MONTH("1m", 1),
    THREE_MONTHS("3m", 3),
    SIX_MONTHS("6m", 6),
    TWELVE_MONTHS("12m", 12),
    LIFETIME("lifetime", 0);

    val isSubscription: Boolean get() = this != LIFETIME

    /** The Play base plan id of a subscription plan; null for lifetime. */
    val basePlanId: String?
        get() = if (isSubscription) Course.current.products.basePlans[ordinal] else null

    /** The Play product this plan is bought as. */
    val productId: String
        get() = if (isSubscription) ProProducts.subscriptionId else ProProducts.lifetimeId

    companion object {
        fun forBasePlan(basePlanId: String?): ProPlan? =
            entries.firstOrNull { it.isSubscription && it.basePlanId == basePlanId }
    }
}
