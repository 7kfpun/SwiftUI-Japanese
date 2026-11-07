package com.kfpun.japanesedaily.ads

import com.kfpun.japanesedaily.BuildConfig
import com.kfpun.japanesedaily.billing.Entitlement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdsTest {
    @Test
    fun adsShowOnlyForFreeUsersAfterConsent() {
        assertTrue(AdsPolicy.showBanner(Entitlement.FREE, canRequestAds = true))
        assertTrue(AdsPolicy.showInterstitial(Entitlement.FREE, canRequestAds = true))
        // A pending payment isn't Pro yet.
        assertTrue(AdsPolicy.showBanner(Entitlement.PENDING, canRequestAds = true))
    }

    @Test
    fun noAdsForProNoMatterWhat() {
        assertFalse(AdsPolicy.showBanner(Entitlement.PRO, canRequestAds = true))
        assertFalse(AdsPolicy.showInterstitial(Entitlement.PRO, canRequestAds = true))
    }

    @Test
    fun noAdsBeforeConsentOrBeforeProIsRead() {
        assertFalse(AdsPolicy.showBanner(Entitlement.FREE, canRequestAds = false))
        assertFalse(AdsPolicy.showInterstitial(Entitlement.FREE, canRequestAds = false))
        // Pro not read yet: a Pro user must never see an ad flash in on launch.
        assertFalse(AdsPolicy.showBanner(null, canRequestAds = true))
        assertFalse(AdsPolicy.showInterstitial(null, canRequestAds = true))
    }

    @Test
    fun theInterstitialIsThrottledToOnceEveryThreeMinutes() {
        var now = 1_000_000L
        val throttle = InterstitialThrottle(now = { now })
        assertEquals(180_000L, InterstitialThrottle.MIN_INTERVAL_MS)
        assertTrue(throttle.tryAcquire()) // the first one is free to show
        assertFalse(throttle.tryAcquire())
        now += 179_000
        assertFalse(throttle.isOpen())
        now += 2_000 // 181 s later
        assertTrue(throttle.tryAcquire())
        assertFalse(throttle.tryAcquire())
    }

    @Test
    fun checkingTheThrottleDoesNotStartAWindow() {
        val throttle = InterstitialThrottle(now = { 5L })
        assertTrue(throttle.isOpen())
        assertTrue(throttle.isOpen())
    }

    @Test
    fun theEightSlotsMatchTheIosNamesAndHaveUnitIds() {
        assertEquals(
            listOf("today", "progress", "kana", "lessons", "select-mode", "vocab-list", "search", "about"),
            AdSlot.entries.map { it.analyticsName }
        )
        AdSlot.entries.forEach { assertTrue(it.unitId, it.unitId.startsWith("ca-app-pub-")) }
        assertTrue(BuildConfig.AD_UNIT_ID_INTERSTITIAL.startsWith("ca-app-pub-"))
    }
}
