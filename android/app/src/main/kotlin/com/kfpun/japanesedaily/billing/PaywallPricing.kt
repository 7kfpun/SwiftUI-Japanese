package com.kfpun.japanesedaily.billing

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/**
 * The paywall's naming and price maths (port of the bottom of `PaywallView`).
 *
 * Plan names are never taken from Play: Play's text follows the Google account's country while this
 * app has its own language picker, so a Play title could sit beside a Chinese "Best value" on one row.
 * A plan's name is built from [ProPlan.months] and the `UIStrings.json` strings. Prices are the
 * exception and stay with Play (`formattedPrice`), since currency follows where you pay, not what
 * language you read.
 */
object PaywallPricing {
    /** A saving under this many percent isn't advertised: it would be a rounding error. */
    const val MIN_SAVING_PERCENT = 5

    private const val MICROS = 1_000_000L

    /** What one month of [offer] costs, in micros of its currency; null for lifetime. */
    fun perMonthMicros(offer: PlanOffer): BigDecimal? {
        val months = offer.plan.months
        if (months <= 0) return null
        return BigDecimal(offer.priceMicros).divide(BigDecimal(months), 2, RoundingMode.HALF_EVEN)
    }

    /** The subscription offers only, cheapest first: the paywall's main list. */
    fun subscriptions(offers: List<PlanOffer>): List<PlanOffer> =
        offers.filter { it.plan.isSubscription }.sortedBy { it.priceMicros }

    fun lifetime(offers: List<PlanOffer>): PlanOffer? = offers.firstOrNull { it.plan == ProPlan.LIFETIME }

    /**
     * The plan with the lowest monthly cost among the multi-month ones: recommended on merit, so
     * the badge stays honest if the lineup or the prices change.
     */
    fun bestValue(offers: List<PlanOffer>): PlanOffer? = subscriptions(offers)
        .filter { it.plan.months > 1 }
        .minByOrNull { perMonthMicros(it) ?: BigDecimal.valueOf(Long.MAX_VALUE) }

    /** Discount against the priciest month, i.e. what the shortest plan costs. Null when too small to show. */
    fun savingsPercent(offer: PlanOffer, offers: List<PlanOffer>): Int? {
        val mine = perMonthMicros(offer) ?: return null
        if (offer.plan.months <= 1) return null
        val baseline = subscriptions(offers).mapNotNull(::perMonthMicros).maxOrNull() ?: return null
        if (baseline.signum() <= 0 || mine >= baseline) return null
        val percent = (baseline - mine).multiply(BigDecimal(100)).divide(baseline, 0, RoundingMode.HALF_UP).toInt()
        return percent.takeIf { it >= MIN_SAVING_PERCENT }
    }

    /** "$1.99" for a month of [offer], formatted for [locale] in the offer's currency; null for lifetime. */
    fun perMonthDisplay(offer: PlanOffer, locale: Locale = Locale.getDefault()): String? {
        val micros = perMonthMicros(offer) ?: return null
        val format = NumberFormat.getCurrencyInstance(locale)
        runCatching { Currency.getInstance(offer.currencyCode) }.getOrNull()?.let { format.currency = it }
        return format.format(micros.divide(BigDecimal(MICROS), 6, RoundingMode.HALF_EVEN))
    }
}
