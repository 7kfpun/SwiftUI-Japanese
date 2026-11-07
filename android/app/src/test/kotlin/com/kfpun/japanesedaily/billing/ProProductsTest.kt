package com.kfpun.japanesedaily.billing

import com.kfpun.japanesedaily.data.Course
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of `PremiumTests` (product lineup). Play product and base plan ids are permanent once created in
 * Play Console, so the list is pinned here and written into android/CLAUDE.md as the record.
 */
class ProProductsTest {
    @Test
    fun playProductIdsMatchWhatPlayConsoleMustHold() {
        assertEquals("premium.subscription", ProProducts.subscriptionId)
        assertEquals("premium.lifetime", ProProducts.lifetimeId)
        assertEquals(listOf("p1m", "p3m", "p6m", "p12m"), Course.Minna.products.basePlans)
        assertEquals(
            listOf("p1m", "p3m", "p6m", "p12m", null),
            ProPlan.entries.map { it.basePlanId }
        )
    }

    @Test
    fun theLineupIsOneToTwelveMonthsPlusLifetime() {
        assertEquals(listOf(1, 3, 6, 12, 0), ProPlan.entries.map { it.months })
        assertEquals(listOf("1m", "3m", "6m", "12m", "lifetime"), ProPlan.entries.map { it.analyticsName })
        // The tier labels are the five iOS Store.tierLabel reports, so reports read the same on both.
        assertEquals(5, ProPlan.entries.size)
    }

    @Test
    fun theSubscriptionAndLifetimeAreDistinctProducts() {
        assertEquals(setOf("premium.subscription", "premium.lifetime"), ProProducts.productIds)
        assertEquals(ProProducts.subscriptionId, ProPlan.THREE_MONTHS.productId)
        assertEquals(ProProducts.lifetimeId, ProPlan.LIFETIME.productId)
    }

    @Test
    fun basePlansResolveBackToTheirPlan() {
        ProPlan.entries.filter { it.isSubscription }.forEach {
            assertEquals(it, ProPlan.forBasePlan(it.basePlanId))
        }
        assertNull(ProPlan.forBasePlan(null))
        assertNull(ProPlan.forBasePlan("unknown"))
    }

    @Test
    fun idsFollowPlayConsoleRules() {
        // Product ids: lowercase letters, digits, underscores, periods. Base plan ids: lowercase letters,
        // digits, hyphens. Both are immutable once created.
        val productId = Regex("[a-z0-9][a-z0-9._]*")
        val basePlanId = Regex("[a-z][a-z0-9-]*")
        ProProducts.productIds.forEach { assertTrue(it, productId.matches(it)) }
        Course.Minna.products.basePlans.forEach { assertTrue(it, basePlanId.matches(it)) }
    }

    @Test
    fun onlyOurProductsGrantPro() {
        assertTrue(FakeBillingGateway.purchase("premium.subscription").isPro)
        assertTrue(FakeBillingGateway.purchase("premium.lifetime").isLifetime)
        assertFalse(FakeBillingGateway.purchase("something.else").isPro)
    }
}
