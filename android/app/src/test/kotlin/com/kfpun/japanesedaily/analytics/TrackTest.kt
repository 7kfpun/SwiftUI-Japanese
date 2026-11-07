package com.kfpun.japanesedaily.analytics

import android.content.SharedPreferences
import java.lang.reflect.Proxy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Port of the iOS analytics tests: the seam's contract, without Firebase. */
class TrackTest {
    private class FakeSink(val failing: Boolean = false) : TrackSink {
        val events = mutableListOf<Pair<String, Map<String, Any>>>()
        val properties = mutableMapOf<String, String>()
        val breadcrumbs = mutableListOf<String>()
        var collection: Boolean? = null

        override fun logEvent(name: String, params: Map<String, Any>) {
            if (failing) error("firebase down")
            events += name to params
        }

        override fun setUserProperty(name: String, value: String) {
            if (failing) error("firebase down")
            properties[name] = value
        }

        override fun setCollectionEnabled(enabled: Boolean) {
            collection = enabled
        }

        override fun breadcrumb(message: String) {
            breadcrumbs += message
        }
    }

    /** The `settings` prefs, held in memory. */
    private fun context(store: MutableMap<String, Any> = mutableMapOf()): SharedPreferences {
        val editor = Proxy.newProxyInstance(
            javaClass.classLoader,
            arrayOf(SharedPreferences.Editor::class.java)
        ) { proxy, method, args ->
            when (method.name) {
                "putBoolean" -> proxy.also { store[args[0] as String] = args[1] as Boolean }
                "apply", "commit" -> true
                else -> proxy
            }
        } as SharedPreferences.Editor
        return Proxy.newProxyInstance(
            javaClass.classLoader,
            arrayOf(SharedPreferences::class.java)
        ) { _, method, args ->
            when (method.name) {
                "getBoolean" -> store[args[0] as String] ?: args[1]
                "edit" -> editor
                else -> null
            }
        } as SharedPreferences
    }

    @Before
    fun reset() {
        // Track is a process-wide object: put its cached state back between tests.
        Track.install(context(), null, collectionAllowed = false)
        Track.setPremium(false, "none")
        Track.setExcluded(false)
    }

    @After
    fun clean() = Track.install(context(), null, collectionAllowed = false)

    @Test
    fun noFirebaseMeansNoOpAndNoCrash() {
        Track.install(context(), null, collectionAllowed = true)
        Track.event(TrackEvents.PRACTICE_DONE, mapOf("total" to 3))
        Track.screen(TrackScreens.TODAY)
        Track.setPremium(true, "lifetime")
        Track.setProfile("en", "en", null, null, false)
        Track.audioMissing("あ")
        Track.setExcluded(true)
        Track.setExcluded(false)
        assertNull(Track.sink)
    }

    @Test
    fun eventsAreRenamedWithThePrefixAndCarryIsPremium() {
        val sink = FakeSink()
        Track.install(context(), sink, collectionAllowed = true)
        Track.event(TrackEvents.PRACTICE_ANSWER, mapOf("correct" to true, "lesson" to 4, "from" to "kanji"))
        val (name, params) = sink.events.single()
        assertEquals("nihongo_2026_practice_answer", name)
        assertEquals(mapOf("correct" to 1L, "lesson" to 4L, "from" to "kanji", "is_premium" to 0L), params)
    }

    @Test
    fun setPremiumRidesOnEveryEventAndSetsTheUserProperties() {
        val sink = FakeSink()
        Track.install(context(), sink, collectionAllowed = true)
        Track.setPremium(true, "12m")
        Track.event(TrackEvents.BOOKMARK)
        assertEquals(1L, sink.events.single().second["is_premium"])
        assertEquals("premium", sink.properties["user_type"])
        assertEquals("12m", sink.properties["premium_tier"])
        Track.setPremium(false, "none")
    }

    @Test
    fun screenIsOneEventNamedScreenAndRemembersTheLastOne() {
        val sink = FakeSink()
        Track.install(context(), sink, collectionAllowed = true)
        Track.screen(TrackScreens.CHALLENGE, mapOf("lesson" to 2, "index" to 1))
        val (name, params) = sink.events.single()
        assertEquals("nihongo_2026_screen", name)
        assertEquals("challenge", params["name"])
        assertEquals(2L, params["lesson"])
        assertEquals("challenge", Track.lastScreen)
    }

    @Test
    fun excludedDeviceLogsNothingButStillRemembersTheScreen() {
        val sink = FakeSink()
        Track.install(context(), sink, collectionAllowed = true)
        Track.setExcluded(true)
        assertTrue(Track.isExcluded)
        assertEquals(false, sink.collection)
        Track.event(TrackEvents.BOOKMARK)
        Track.screen(TrackScreens.SETTINGS)
        Track.setProfile("en", "en", null, null, false)
        assertTrue(sink.events.isEmpty())
        assertTrue(sink.properties.isEmpty())
        assertEquals("settings", Track.lastScreen)
        Track.setExcluded(false)
        assertEquals(true, sink.collection)
        Track.event(TrackEvents.BOOKMARK)
        assertEquals(1, sink.events.size)
    }

    @Test
    fun exclusionPersistsAcrossInstalls() {
        val store = mutableMapOf<String, Any>()
        val sink = FakeSink()
        Track.install(context(store), sink, collectionAllowed = true)
        Track.setExcluded(true)
        assertEquals(true, store["analyticsExcluded"])
        // A relaunch: a new sink, the same prefs.
        val relaunched = FakeSink()
        Track.install(context(store), relaunched, collectionAllowed = true)
        assertTrue(Track.isExcluded)
        assertEquals(false, relaunched.collection)
        Track.event(TrackEvents.BOOKMARK)
        assertTrue(relaunched.events.isEmpty())
    }

    @Test
    fun aBuildThatDoesNotCollectNeverEnablesCollection() {
        val sink = FakeSink()
        Track.install(context(), sink, collectionAllowed = false)
        assertEquals(false, sink.collection)
        Track.setExcluded(false)
        assertEquals(false, sink.collection)
        Track.event(TrackEvents.BOOKMARK)
        assertTrue(sink.events.isEmpty())
    }

    @Test
    fun aFailingFirebaseNeverCrashesTheApp() {
        Track.install(context(), FakeSink(failing = true), collectionAllowed = true)
        Track.event(TrackEvents.BOOKMARK)
        Track.setPremium(true, "lifetime")
        Track.screen(TrackScreens.TODAY)
    }

    @Test
    fun audioMissingLeavesABreadcrumbAndAnEvent() {
        val sink = FakeSink()
        Track.install(context(), sink, collectionAllowed = true)
        Track.audioMissing("かばん")
        assertEquals(listOf("audio is missing: かばん"), sink.breadcrumbs)
        assertEquals("nihongo_2026_audio_missing", sink.events.single().first)
        assertEquals("かばん", sink.events.single().second["item"])
    }

    @Test
    fun profileNamesFallbacksAndTheThirtySixCharClamp() {
        assertEquals(
            mapOf(
                "ui_language" to "de",
                "meaning_language" to "en",
                "knows_kana" to "unanswered",
                "learning_goal" to "unanswered",
                "earned_first_group" to "false"
            ),
            Track.profile("de", "en", null, null, false)
        )
        val long = "x".repeat(50)
        assertEquals(36, Track.profile(long, "en", "both", "travel", true)["ui_language"]!!.length)
        assertEquals("true", Track.profile("en", "en", "both", "travel", true)["earned_first_group"])
    }

    @Test
    fun setProfileSkipsUnchangedValues() {
        val sink = FakeSink()
        Track.install(context(), sink, collectionAllowed = true)
        Track.setProfile("de", "en", "both", "jlpt", true)
        assertEquals("de", sink.properties["ui_language"])
        sink.properties.clear()
        Track.setProfile("de", "en", "both", "jlpt", true)
        assertTrue(sink.properties.isEmpty())
        Track.setProfile("fr", "en", "both", "jlpt", true)
        assertEquals("fr", sink.properties["ui_language"])
    }

    @Test
    fun paramsAreNumbersAndStringsOnly() {
        val long = "x".repeat(150)
        val out = TrackParams.normalise(
            mapOf("b" to false, "i" to 3, "f" to 1.5f, "n" to null, "s" to long, "e" to TrackEvents.TODAY_FLIP)
        )
        assertEquals(0L, out["b"])
        assertEquals(3L, out["i"])
        assertEquals(1.5, out["f"])
        assertFalse(out.containsKey("n"))
        assertEquals(100, (out["s"] as String).length)
        assertEquals("today_flip", out["e"])
    }

    @Test
    fun tapCounterNeedsSevenQuickTaps() {
        val counter = TapCounter(threshold = 7, windowMillis = 1000)
        repeat(6) { assertFalse(counter.tap(it * 300L)) }
        assertTrue(counter.tap(6 * 300L))
        // Resets after firing.
        assertFalse(counter.tap(2000))
        // A pause starts over.
        val slow = TapCounter(threshold = 3, windowMillis = 1000)
        assertFalse(slow.tap(0))
        assertFalse(slow.tap(500))
        assertFalse(slow.tap(2000))
        assertFalse(slow.tap(2400))
        assertTrue(slow.tap(2800))
    }
}
