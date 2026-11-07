package com.kfpun.japanesedaily

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pins the FOX-146 decisions, so a refactor of the Gradle config cannot change them quietly. */
class IdentityTest {
    @Test
    fun applicationIdIsThePlayListing() {
        // Without the flavour's applicationIdSuffix (none), the id is exactly the package.
        assertEquals("com.kfpun.japanesedaily", BuildConfig.APPLICATION_ID)
    }

    @Test
    fun sdkLevelsMatchTheDecision() {
        assertEquals(26, BuildConfig.MIN_SDK)
        assertEquals(36, BuildConfig.TARGET_SDK)
    }

    @Test
    fun versionCodeIsPositive() {
        assertTrue(BuildConfig.VERSION_CODE >= 1)
    }

    @Test
    fun exampleConfigIsWiredIntoBuildConfig() {
        assertTrue(BuildConfig.DIRECTUS_URL.startsWith("https://"))
        assertTrue(BuildConfig.AD_UNIT_ID_TODAY.startsWith("ca-app-pub-"))
    }
}
