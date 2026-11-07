package com.kfpun.japanesedaily.survey

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of the iOS `SurveyTests`, with a fake Directus on a local port: tests never reach the real one.
 */
class SurveyTest {
    /** Transcribed from the Directus columns every `japanese_survey_*` collection shares (iOS test: columnContextKeys). */
    private val columnContextKeys = setOf(
        "platform", "app_version", "os", "device",
        "os_language", "app_language", "vocab_language", "region",
        "is_premium", "tier", "challenges_passed", "kana_answered",
        "sound_on", "analytics_excluded", "shown_fields",
        "text_size", "appearance", "last_screen",
        "knows_kana", "goal", "textbook_lesson",
        "debug", "v"
    )

    private val context = Survey.Context()

    private class Hit(val path: String, val method: String, val auth: String?, val type: String?, val body: String)

    private val hits = CopyOnWriteArrayList<Hit>()
    private var server: HttpServer? = null

    @After
    fun stop() {
        server?.stop(0)
    }

    private fun fakeDirectus(status: Int, reply: String = "{}"): String {
        val s = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        s.createContext("/") { ex ->
            hits += Hit(
                ex.requestURI.path,
                ex.requestMethod,
                ex.requestHeaders.getFirst("Authorization"),
                ex.requestHeaders.getFirst("Content-Type"),
                ex.requestBody.readBytes().toString(Charsets.UTF_8)
            )
            val bytes = reply.toByteArray()
            ex.sendResponseHeaders(status, bytes.size.toLong())
            ex.responseBody.use { it.write(bytes) }
        }
        s.start()
        server = s
        return "http://127.0.0.1:${s.address.port}"
    }

    @Test
    fun contextKeysMatchTheDirectusColumns() {
        assertEquals(columnContextKeys, Survey.Context.keys)
        assertEquals(columnContextKeys, context.fields.keys)
    }

    @Test
    fun introSubmissionIsExactlyTheContext() {
        val row = Survey.fields(Survey.Intro("both", 3, "travel"), context)
        assertEquals(columnContextKeys, row.keys)
        // The answers from this run win over whatever the preferences hold.
        assertEquals("both", row["knows_kana"])
        assertEquals(3, row["textbook_lesson"])
        assertEquals("travel", row["goal"])
        assertEquals("Android", context.fields["platform"])
    }

    @Test
    fun ratingSubmissionCarriesContextPlusItsStars() {
        val row = Survey.fields(Survey.Rating(4), context)
        assertEquals(columnContextKeys + "stars", row.keys)
        assertEquals(4, row["stars"])
    }

    @Test
    fun feedbackSubmissionCarriesContextPlusItsOwnFields() {
        val own = setOf("kind", "area", "message", "email", "source", "stars", "lesson", "item")
        val row = Survey.fields(Survey.Feedback("bug", "audio", "no sound", "", "settings", 3, 0, ""), context)
        assertEquals(columnContextKeys + own, row.keys)
    }

    /** The row names no identifier: nothing Android could mint or read that joins two rows. */
    @Test
    fun noRowCarriesAnIdentifier() {
        val banned = Regex("(?i)android_?id|advertis|\\bgaid\\b|install|uuid|user_?id|device_?id|session|token")
        val all = Survey.fields(Survey.Feedback("bug", "", "x", "", "settings", 0, 0, ""), context).keys
        assertTrue(all.none { banned.containsMatchIn(it) })
    }

    @Test
    fun directusCreateRequestCarriesExactlyTheRow() {
        val client = DirectusClient("https://cms.example.test/", "test-token")
        val row = Survey.fields(Survey.Rating(2), context)
        val request = client.createRequest(Survey.RATING_COLLECTION, row)!!
        assertEquals("https://cms.example.test/items/japanese_survey_rating", request.url)
        assertEquals("test-token", request.token)
        assertEquals(Survey.INTRO_COLLECTION, "japanese_survey_intro")
        assertEquals(Survey.FEEDBACK_COLLECTION, "japanese_survey_feedback")
        // Flat object, sorted keys, booleans and ints stay typed.
        assertTrue(request.body.startsWith("{\"analytics_excluded\":false,"))
        assertTrue(request.body.contains("\"is_premium\":false"))
        assertTrue(request.body.contains("\"stars\":2"))
        assertTrue(request.body.contains("\"platform\":\"Android\""))
        assertEquals(columnContextKeys.size + 1, Regex("\"[a-z_]+\":").findAll(request.body).count())
    }

    @Test
    fun jsonEscapesText() {
        assertEquals("{\"a\":\"q\\\"\\\\\\n\"}", Json.encode(mapOf("a" to "q\"\\\n")))
    }

    @Test
    fun aMissingOrPlaceholderTokenIsASilentNoOp() {
        listOf(null, "", "   ", "placeholder-directus-token").forEach {
            val client = DirectusClient("http://127.0.0.1:1", it)
            assertFalse(client.isConfigured)
            assertNull(client.createRequest("japanese_survey_intro", mapOf("a" to 1)))
            client.submit("japanese_survey_intro", mapOf("a" to 1)) // must not throw or connect
        }
        assertTrue(DirectusClient("http://x", "real-token").isConfigured)
    }

    @Test
    fun theFakeServerReceivesTheIntroRow() {
        val url = fakeDirectus(200, """{"data":{"id":1}}""")
        val failures = mutableListOf<String>()
        val client = DirectusClient(url, "fake-token", { Survey.FailureReporter { failures += it } }, { })
        val row = Survey.fields(Survey.Intro("none", 0, "culture"), context)
        val request = client.createRequest(Survey.INTRO_COLLECTION, row)!!
        assertNull(client.deliver(Survey.INTRO_COLLECTION, request))

        val hit = hits.single()
        assertEquals("POST", hit.method)
        assertEquals("/items/japanese_survey_intro", hit.path)
        assertEquals("Bearer fake-token", hit.auth)
        assertEquals("application/json", hit.type)
        assertEquals(request.body, hit.body)
        assertTrue(hit.body.contains("\"platform\":\"Android\""))
        assertTrue(hit.body.contains("\"knows_kana\":\"none\""))
        assertTrue(failures.isEmpty())
    }

    /** A rejection is a status code, not an exception: it must be reported with Directus's own message. */
    @Test
    fun aRejectionIsReportedOnceAndNotRetried() {
        val url = fakeDirectus(400, """{"errors":[{"message":"Value for field \"platform\" is invalid."}]}""")
        val failures = mutableListOf<String>()
        val logs = mutableListOf<String>()
        val client = DirectusClient(url, "fake-token", { Survey.FailureReporter { failures += it } }, { logs += it })
        val request = client.createRequest(Survey.INTRO_COLLECTION, mapOf("a" to 1))!!
        val failure = client.deliver(Survey.INTRO_COLLECTION, request)
        assertNotNull(failure)
        assertTrue(failure!!.startsWith("HTTP 400 — Value for field"))
        assertEquals(listOf("japanese_survey_intro"), failures)
        assertEquals(1, logs.size)
        assertEquals(1, hits.size)
    }

    @Test
    fun anUnreachableServerFailsQuietly() {
        val failures = mutableListOf<String>()
        val client = DirectusClient("http://127.0.0.1:1", "t", { Survey.FailureReporter { failures += it } }, { })
        val request = client.createRequest(Survey.RATING_COLLECTION, mapOf("a" to 1))!!
        assertNotNull(client.deliver(Survey.RATING_COLLECTION, request))
        assertEquals(listOf("japanese_survey_rating"), failures)
    }

    @Test
    fun directusFailureNamesTheCause() {
        assertEquals(
            "HTTP 400 — Value too long.",
            DirectusClient.describe(400, """{"errors":[{"message":"Value too long."}]}""")
        )
        assertEquals("HTTP 503", DirectusClient.describe(503, "<html>"))
    }

    @Test
    fun textSizeNamesMatchTheIosCategories() {
        assertEquals("L", AppInfo.textSize(1.0f))
        assertEquals("XL", AppInfo.textSize(1.15f))
        assertEquals("XXL", AppInfo.textSize(1.3f))
        assertEquals("AX5", AppInfo.textSize(3.0f))
    }
}
