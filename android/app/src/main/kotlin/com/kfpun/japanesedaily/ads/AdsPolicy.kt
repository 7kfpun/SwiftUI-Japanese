package com.kfpun.japanesedaily.ads

import com.kfpun.japanesedaily.billing.Entitlement

/** The one rule for whether an ad may be requested or shown. Every ad surface asks this. */
object AdsPolicy {
    /**
     * Ads are for free users, once consent allows them. Pro hides them; so does an entitlement
     * not read yet, so a Pro user never sees an ad flash in on launch. A pending payment isn't Pro
     * yet, so it still gets ads.
     */
    fun mayShowAds(entitlement: Entitlement?, canRequestAds: Boolean): Boolean =
        canRequestAds && (entitlement == Entitlement.FREE || entitlement == Entitlement.PENDING)

    fun showBanner(entitlement: Entitlement?, canRequestAds: Boolean): Boolean = mayShowAds(entitlement, canRequestAds)

    fun showInterstitial(entitlement: Entitlement?, canRequestAds: Boolean): Boolean =
        mayShowAds(entitlement, canRequestAds)
}
