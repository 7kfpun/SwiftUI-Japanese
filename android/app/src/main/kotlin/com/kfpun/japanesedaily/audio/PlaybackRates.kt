package com.kfpun.japanesedaily.audio

/**
 * Whether the user has Pro. FOX-158 (billing) provides the real one; until it lands the default is
 * [NotPremium], so every gated feature fails closed.
 */
interface PremiumStatus {
    val isPremium: Boolean
}

object NotPremium : PremiumStatus {
    override val isPremium: Boolean = false
}

/**
 * Read along's speed dial (port of `Gating.rate` and `ReadAlongView.rates`). 1x is free; the other
 * three are Pro. The stored preference is remembered, not honoured: a lapsed subscriber keeps 1.2x
 * in `Pref.playbackRate`, and this clamps what actually plays to normal speed.
 */
object PlaybackRates {
    const val NORMAL = 1.0

    /** The dial's stops, slowest first. */
    val choices: List<Double> = listOf(0.8, 1.0, 1.2, 1.5)

    /** The rate to play at for the [stored] preference. */
    fun effective(stored: Double, premium: PremiumStatus): Double = effective(stored, premium.isPremium)

    fun effective(stored: Double, isPremium: Boolean): Double = if (isPremium) stored else NORMAL

    /** Whether picking [rate] on the dial needs Pro (everything but 1x). */
    fun isLocked(rate: Double, premium: PremiumStatus): Boolean = !premium.isPremium && rate != NORMAL
}
