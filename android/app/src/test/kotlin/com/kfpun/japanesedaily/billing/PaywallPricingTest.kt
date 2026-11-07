package com.kfpun.japanesedaily.billing

import com.kfpun.japanesedaily.billing.FakeBillingGateway.Companion.offer
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The paywall's price maths (port of `PaywallView`'s bestValue, savingsPercent and perMonth). */
class PaywallPricingTest {
    private val lineup = listOf(
        offer(ProPlan.TWELVE_MONTHS, 24.00),
        offer(ProPlan.ONE_MONTH, 3.00),
        offer(ProPlan.LIFETIME, 60.00),
        offer(ProPlan.SIX_MONTHS, 15.00),
        offer(ProPlan.THREE_MONTHS, 9.00)
    )

    @Test
    fun subscriptionsAreCheapestFirstAndLifetimeIsApart() {
        assertEquals(
            listOf(ProPlan.ONE_MONTH, ProPlan.THREE_MONTHS, ProPlan.SIX_MONTHS, ProPlan.TWELVE_MONTHS),
            PaywallPricing.subscriptions(lineup).map { it.plan }
        )
        assertEquals(ProPlan.LIFETIME, PaywallPricing.lifetime(lineup)?.plan)
    }

    @Test
    fun perMonthDividesThePriceByTheTerm() {
        assertEquals(2.0, PaywallPricing.perMonthMicros(lineup[0])!!.toDouble() / 1_000_000, 0.0001)
        assertEquals(2.5, PaywallPricing.perMonthMicros(lineup[3])!!.toDouble() / 1_000_000, 0.0001)
        assertNull(PaywallPricing.perMonthMicros(lineup[2]))
    }

    @Test
    fun bestValueIsTheLowestMonthlyCostOnMerit() {
        assertEquals(ProPlan.TWELVE_MONTHS, PaywallPricing.bestValue(lineup)?.plan)
        // Reprice and the badge moves: it is never hardcoded to the longest plan.
        val repriced = lineup.map { if (it.plan == ProPlan.SIX_MONTHS) offer(ProPlan.SIX_MONTHS, 6.00) else it }
        assertEquals(ProPlan.SIX_MONTHS, PaywallPricing.bestValue(repriced)?.plan)
        assertNull(PaywallPricing.bestValue(listOf(offer(ProPlan.ONE_MONTH, 3.0), offer(ProPlan.LIFETIME, 60.0))))
    }

    @Test
    fun savingsAreAgainstThePriciestMonth() {
        assertNull(PaywallPricing.savingsPercent(lineup[1], lineup)) // the 1-month plan is the baseline
        assertNull(PaywallPricing.savingsPercent(lineup[4], lineup)) // 3 months at 3.00 a month saves nothing
        assertEquals(17, PaywallPricing.savingsPercent(lineup[3], lineup)) // 2.50 vs 3.00
        assertEquals(33, PaywallPricing.savingsPercent(lineup[0], lineup)) // 2.00 vs 3.00
        assertNull(PaywallPricing.savingsPercent(lineup[2], lineup)) // lifetime never advertises one
    }

    @Test
    fun aRoundingErrorOfASavingIsNotAdvertised() {
        val flat = listOf(offer(ProPlan.ONE_MONTH, 3.00), offer(ProPlan.THREE_MONTHS, 8.80)) // 2.93 vs 3.00: 2%
        assertNull(PaywallPricing.savingsPercent(flat[1], flat))
    }

    @Test
    fun perMonthIsShownInTheOffersCurrency() {
        assertEquals("$2.50", PaywallPricing.perMonthDisplay(lineup[3], Locale.US))
        assertNull(PaywallPricing.perMonthDisplay(lineup[2], Locale.US))
    }
}
