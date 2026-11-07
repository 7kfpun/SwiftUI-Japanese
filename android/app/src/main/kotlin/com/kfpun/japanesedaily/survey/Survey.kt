package com.kfpun.japanesedaily.survey

import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Survey submissions: the one place the app writes to a server. Port of `nihongo/Survey.swift`.
 *
 * Rows are created in Directus (`POST /items/<collection>`) with a static token whose policy grants
 * `create` on the three survey collections and nothing else. Deliberately no identifier of any kind:
 * no Android ID, no advertising id, no minted install id. Two rows from one person cannot be joined,
 * which is why every row carries the three intro answers in its context.
 */
object Survey {
    /** Bumped when a field is added or removed. Same number as iOS: the column set is shared. */
    const val SCHEMA_VERSION = 4

    const val INTRO_COLLECTION = "japanese_survey_intro"
    const val RATING_COLLECTION = "japanese_survey_rating"
    const val FEEDBACK_COLLECTION = "japanese_survey_feedback"

    /** One completed intro run. Skips and partial runs submit nothing. */
    data class Intro(val knowsKana: String, val textbookLesson: Int, val goal: String)

    /** One star tap (1..5). */
    data class Rating(val stars: Int)

    data class Feedback(
        val kind: String,
        val area: String,
        val message: String,
        val email: String,
        val source: String,
        val stars: Int,
        val lesson: Int,
        val item: String
    )

    /**
     * The diagnostic context every row carries, identically, in every collection. Device
     * characteristics only (model, OS, language, region), never a device identity. The values are
     * handed in (see [AppInfo]) so this stays a plain value a JVM test can build.
     */
    data class Context(
        val appVersion: String = "1.0.0 (1)",
        val os: String = "Android 16",
        val device: String = "Pixel",
        val osLanguage: String = "en-US",
        val appLanguage: String = "en",
        val vocabLanguage: String = "en",
        val region: String = "US",
        val isPremium: Boolean = false,
        val tier: String = "none",
        val challengesPassed: Int = 0,
        val kanaAnswered: Int = 0,
        val soundOn: Boolean = true,
        val analyticsExcluded: Boolean = false,
        val shownFields: String = "kanji,kana,romaji,translation",
        val textSize: String = "L",
        val appearance: String = "light",
        val lastScreen: String = "",
        val knowsKana: String = "unanswered",
        val goal: String = "unanswered",
        val textbookLesson: Int = -1,
        val debug: Boolean = false
    ) {
        /** The map. No timestamp: Directus stamps `date_created` itself. */
        val fields: Map<String, Any>
            get() = mapOf(
                "platform" to PLATFORM,
                "app_version" to appVersion,
                "os" to os,
                "device" to device,
                "os_language" to osLanguage,
                "app_language" to appLanguage,
                "vocab_language" to vocabLanguage,
                "region" to region,
                "is_premium" to isPremium,
                "tier" to tier,
                "challenges_passed" to challengesPassed,
                "kana_answered" to kanaAnswered,
                "sound_on" to soundOn,
                "analytics_excluded" to analyticsExcluded,
                "shown_fields" to shownFields,
                "text_size" to textSize,
                "appearance" to appearance,
                "last_screen" to lastScreen.take(MAX_SCREEN),
                "knows_kana" to knowsKana,
                "goal" to goal,
                "textbook_lesson" to textbookLesson,
                "debug" to debug,
                "v" to SCHEMA_VERSION
            )

        companion object {
            /** Unverified against the Directus `platform` column (iOS pins 'iOS'); see the PR. */
            const val PLATFORM = "Android"

            const val MAX_SCREEN = 40

            /** The full key set: the invariant the Directus columns follow and `SurveyTest` guards. */
            val keys: Set<String> = setOf(
                "platform", "app_version", "os", "device", "os_language",
                "app_language", "vocab_language", "region",
                "is_premium", "tier", "challenges_passed", "kana_answered",
                "sound_on", "analytics_excluded",
                "shown_fields", "text_size", "appearance", "last_screen",
                "knows_kana", "goal", "textbook_lesson",
                "debug", "v"
            )
        }
    }

    /** The answers from this run win over whatever the context re-read from preferences. */
    fun fields(intro: Intro, context: Context): Map<String, Any> = context.fields + mapOf(
        "knows_kana" to intro.knowsKana,
        "textbook_lesson" to intro.textbookLesson,
        "goal" to intro.goal
    )

    fun fields(rating: Rating, context: Context): Map<String, Any> = context.fields + mapOf("stars" to rating.stars)

    fun fields(feedback: Feedback, context: Context): Map<String, Any> = context.fields + mapOf(
        "kind" to feedback.kind,
        "area" to feedback.area,
        "message" to feedback.message,
        "email" to feedback.email,
        "source" to feedback.source,
        "stars" to feedback.stars,
        "lesson" to feedback.lesson,
        "item" to feedback.item
    )

    /** Called with the collection name when a write fails; wired to `Track.event("survey_failed")`. */
    fun interface FailureReporter {
        fun surveyFailed(collection: String)
    }

    @Volatile
    var failureReporter: FailureReporter = FailureReporter { }

    @Volatile
    internal var client: DirectusClient? = null

    private fun client(): DirectusClient = client ?: DirectusClient.fromBuildConfig().also { client = it }

    fun submit(intro: Intro, context: Context) = client().submit(INTRO_COLLECTION, fields(intro, context))

    fun submit(rating: Rating, context: Context) = client().submit(RATING_COLLECTION, fields(rating, context))

    fun submit(feedback: Feedback, context: Context) = client().submit(FEEDBACK_COLLECTION, fields(feedback, context))
}

/** A prepared create call. */
class DirectusRequest(val url: String, val token: String, val body: String)

/** The Directus instance survey rows are created in. */
class DirectusClient(
    private val baseUrl: String,
    token: String?,
    private val reporter: () -> Survey.FailureReporter = { Survey.failureReporter },
    private val log: (String) -> Unit = { Log.w(TAG, it) }
) {
    private val token: String? = usableToken(token)

    /** False for an empty or placeholder token: every submission is then a silent no-op. */
    val isConfigured: Boolean get() = token != null && baseUrl.isNotBlank()

    fun createRequest(collection: String, fields: Map<String, Any>): DirectusRequest? {
        val token = token ?: return null
        return DirectusRequest(
            url = baseUrl.trimEnd('/') + "/items/" + collection,
            token = token,
            body = Json.encode(fields)
        )
    }

    /** Fire and forget on a background thread; never throws, never retries. */
    fun submit(collection: String, fields: Map<String, Any>) {
        val request = createRequest(collection, fields) ?: return
        executor.execute { deliver(collection, request) }
    }

    /** The blocking write: reports and logs a failure, returns it (null on success). */
    internal fun deliver(collection: String, request: DirectusRequest): String? {
        val failure = try {
            post(request)
        } catch (e: Exception) {
            e.message ?: e.javaClass.simpleName
        }
        if (failure != null) {
            log("survey: $collection write failed — $failure")
            runCatching { reporter().surveyFailed(collection) }
        }
        return failure
    }

    private fun post(request: DirectusRequest): String? {
        val connection = URL(request.url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.doOutput = true
            connection.setRequestProperty("Authorization", "Bearer ${request.token}")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { it.write(request.body.toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            if (status in 200..299) return null
            val body = runCatching { connection.errorStream?.bufferedReader()?.readText() }.getOrNull().orEmpty()
            return describe(status, body)
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        private const val TAG = "Survey"
        private const val TIMEOUT_MS = 15_000

        private val executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "survey").apply { isDaemon = true }
        }

        fun fromBuildConfig() = DirectusClient(
            com.kfpun.japanesedaily.BuildConfig.DIRECTUS_URL,
            com.kfpun.japanesedaily.BuildConfig.DIRECTUS_TOKEN
        )

        /** Null for blank or the example file's placeholder. */
        fun usableToken(raw: String?): String? {
            val trimmed = raw?.trim().orEmpty()
            return trimmed.takeIf { it.isNotEmpty() && !it.startsWith("placeholder", ignoreCase = true) }
        }

        /** `"HTTP 403 — message"`: the status plus Directus's first error message, if any. */
        fun describe(status: Int, body: String): String {
            val message = Regex("\"message\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(body)?.groupValues?.get(1)
            return "HTTP $status" + (message?.let { " — $it" } ?: "")
        }
    }
}

/** A flat JSON object of strings, ints and booleans, keys sorted. org.json is stubbed in JVM tests. */
internal object Json {
    fun encode(fields: Map<String, Any>): String = fields.toSortedMap().entries.joinToString(",", "{", "}") {
        quote(it.key) + ":" + value(it.value)
    }

    private fun value(v: Any): String = when (v) {
        is Boolean, is Int, is Long -> v.toString()
        else -> quote(v.toString())
    }

    private fun quote(s: String): String = buildString {
        append('"')
        for (c in s) {
            when {
                c == '"' -> append("\\\"")
                c == '\\' -> append("\\\\")
                c == '\n' -> append("\\n")
                c == '\r' -> append("\\r")
                c == '\t' -> append("\\t")
                c < ' ' -> append("\\u%04x".format(c.code))
                else -> append(c)
            }
        }
        append('"')
    }
}
