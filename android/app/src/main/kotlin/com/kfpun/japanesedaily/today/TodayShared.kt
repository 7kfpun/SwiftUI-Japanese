package com.kfpun.japanesedaily.today

import java.time.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * What the app and the home-screen widget share (port of `Shared/TodayShared.swift`): the Today deck as a plain
 * snapshot, the hourly rotation off the wall clock, and the built-in sample deck. Pure, so it is unit tested
 * against the numbers the Swift produces for fixed timestamps.
 */
object TodayShared {
    @Serializable
    data class Word(val kana: String, val kanji: String, val romaji: String, val meaning: String)

    /**
     * [challenge] is the rung these words prepare for; a cleared ladder sends its last rung as a retake.
     * Optional only so a snapshot written before the field existed still decodes.
     */
    @Serializable
    data class Snapshot(val lesson: Int, val words: List<Word>, val challenge: Int? = null)

    /** The built-in deck (`Course.minna.sampleWords`): what the widget shows before the app ever published. */
    val sampleWords: List<Word> = listOf(
        Word("わたし", "私", "watashi", "I"),
        Word("せんせい", "先生", "sensei", "teacher"),
        Word("がくせい", "学生", "gakusei", "student"),
        Word("ほん", "本", "hon", "book"),
        Word("とけい", "時計", "tokei", "watch, clock"),
        Word("でんわ", "電話", "denwa", "telephone"),
        Word("くるま", "車", "kuruma", "car")
    )

    /** The sample deck as a snapshot; it claims challenge 1, so the picker preview shows the call to action too. */
    val sampleSnapshot = Snapshot(lesson = 1, words = sampleWords, challenge = 1)

    private val json = Json { ignoreUnknownKeys = true }

    fun encode(snapshot: Snapshot): String = json.encodeToString(Snapshot.serializer(), snapshot)

    fun decode(text: String): Snapshot? = runCatching { json.decodeFromString(Snapshot.serializer(), text) }.getOrNull()

    // region Hourly rotation

    /**
     * Which word of a [count]-word deck to show at [at]. A pure function of the wall clock, and that is the whole
     * point: the widget is redrawn every time the app publishes, and an index counted forward from the redraw
     * would restart at the same word each time. Deriving it from the hour makes a redraw idempotent.
     */
    fun rotationIndex(count: Int, cursor: Int = 0, at: Instant = Instant.now()): Int {
        if (count <= 0) return 0
        return floorMod(cursor.toLong() + hourSlot(at), count)
    }

    /**
     * Whole hours since the epoch, the rotation's clock. Not a calendar component: it only has to advance by
     * exactly one every hour and be identical in the app and the widget, which a UTC-anchored count is and a
     * local-time one isn't across a DST change.
     */
    fun hourSlot(at: Instant = Instant.now()): Long = Math.floorDiv(at.epochSecond, SECONDS_PER_HOUR)

    /** The top of the next clock hour after [after], where the following rotation belongs. */
    fun nextHour(after: Instant = Instant.now()): Instant =
        Instant.ofEpochSecond((hourSlot(after) + 1) * SECONDS_PER_HOUR)

    /** Floor modulo: Kotlin's `%` keeps the dividend's sign, and a negative cursor must still be a valid index. */
    fun floorMod(value: Long, count: Int): Int = if (count <= 0) 0 else Math.floorMod(value, count.toLong()).toInt()

    // endregion

    private const val SECONDS_PER_HOUR = 3600L
}
