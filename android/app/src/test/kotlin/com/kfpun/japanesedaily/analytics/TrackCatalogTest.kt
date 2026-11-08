package com.kfpun.japanesedaily.analytics

import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the Android catalog to the iOS one. `ios-track-catalog.txt` is generated from the Swift source by
 * `scripts/extract-track-events.py` (CI checks it is current), so a `Track.event` added or renamed on iOS
 * fails here until it is ported to [TrackEvents] / [TrackScreens].
 */
class TrackCatalogTest {
    private val catalog: List<String> = javaClass.getResourceAsStream("/ios-track-catalog.txt")!!
        .bufferedReader().readLines().filter { it.isNotBlank() }

    private fun iOS(kind: String) = catalog.filter { it.startsWith("$kind ") }.map { it.removePrefix("$kind ") }.toSet()

    private fun constants(type: Class<*>): Set<String> = type.declaredFields
        .filter { Modifier.isStatic(it.modifiers) && it.type == String::class.java }
        .also { it.forEach { f -> f.isAccessible = true } }
        .map { it.get(null) as String }
        .toSet()

    /** iOS-only: nothing on Android to log (FOX-146: no remote push in v1; no Live Activities). */
    private val notOnAndroid = setOf(
        "push_registered",
        "push_register_failed",
        "fcm_token",
        // SKStoreReviewController was asked. Android never uses Play In-App Review (Google forbids an opinion
        // question before its card), so there is no such ask; see `store_page_opened`.
        "review_requested",
        // A Read along Live Activity was tapped (`nihongo://read`). Android has no Live Activities.
        "read_along_open"
    )

    /** Android-only: the Play listing was opened from the rating star row or Settings -> Rate the app. */
    private val androidOnly = setOf("store_page_opened")

    @Test
    fun androidEventsAreTheIosEventsLessThePushOnesPlusTheAndroidOnes() {
        assertEquals(iOS("event") - notOnAndroid + androidOnly, constants(TrackEvents::class.java))
    }

    @Test
    fun androidScreensAreTheIosScreens() {
        assertEquals(iOS("screen"), constants(TrackScreens::class.java))
    }

    @Test
    fun theCatalogIsNotEmpty() {
        assertTrue(iOS("event").size > 100)
        assertTrue(iOS("screen").size > 20)
    }

    @Test
    fun namesAndKeysAreLowerSnakeCase() {
        val snake = Regex("[a-z][a-z0-9]*(_[a-z0-9]+)*")
        (constants(TrackEvents::class.java) + constants(TrackScreens::class.java) + PaywallSource.all).forEach {
            assertTrue("$it is not lower_snake_case", snake.matches(it))
        }
    }

    @Test
    fun paywallSourcesAreTheFiveLiveOnes() {
        assertEquals(
            setOf("locked_mode", "locked_challenge", "read_all_meanings", "playback_speed", "settings"),
            PaywallSource.all
        )
    }

    /**
     * GA4 drops an event name past 40 characters. `notification_opt_in_dismissed` is 29, so the prefixed name
     * is 42 and neither platform's event ever arrives. It stays as it is for parity with iOS (renaming
     * it is an iOS change, flagged in FOX-160); any other name that grows past the cap fails here.
     */
    @Test
    fun prefixedNamesFitGa4sFortyCharacterCap() {
        val knownTooLong = setOf(TrackEvents.NOTIFICATION_OPT_IN_DISMISSED)
        val tooLong = constants(TrackEvents::class.java).filter { (Track.PREFIX + it).length > 40 }.toSet()
        assertEquals(knownTooLong, tooLong)
    }
}
