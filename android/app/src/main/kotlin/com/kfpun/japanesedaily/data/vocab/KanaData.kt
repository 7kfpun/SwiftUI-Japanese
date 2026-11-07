package com.kfpun.japanesedaily.data.vocab

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromStream

/** A kana cell: hiragana, katakana, romaji and textbook stroke counts. Empty strings are placeholders. */
data class K(
    val hiragana: String,
    val katakana: String,
    val romaji: String,
    val hiraganaStrokes: Int = 0,
    val katakanaStrokes: Int = 0
) {
    val isEmpty: Boolean get() = romaji.isEmpty()
    val id: String get() = if (romaji.isEmpty()) "_$hiragana$katakana" else romaji
}

/**
 * The kana chart, built from the bundled `KanaChart.json` (copied verbatim from the submodule):
 * grid layout, romaji and stroke counts all come from the data file (port of `KanaData`).
 */
class KanaData(assets: AssetSource) {
    @Serializable
    private class Strokes(val hiragana: Int, val katakana: Int)

    @Serializable
    private class Entry(
        val hiragana: String,
        val katakana: String,
        val romaji: String,
        val row: Int,
        val col: Int,
        val strokes: Strokes
    )

    @Serializable
    private class Chart(val data: Map<String, List<Entry>>)

    @OptIn(ExperimentalSerializationApi::class)
    private val chart: Map<String, List<Entry>> by lazy {
        val json = Json { ignoreUnknownKeys = true }
        assets.open("KanaChart.json").use { json.decodeFromStream<Chart>(it) }.data
    }

    /** Places entries by row/col, pads gaps with placeholders, trims trailing empties (ん sits alone). */
    private fun grid(group: String, cols: Int): List<List<K>> {
        val entries = chart[group].orEmpty()
        val rowCount = (entries.maxOfOrNull { it.row } ?: -1) + 1
        val rows = List(rowCount) { MutableList(cols) { K("", "", "") } }
        for (e in entries) {
            rows[e.row][e.col] = K(e.hiragana, e.katakana, e.romaji, e.strokes.hiragana, e.strokes.katakana)
        }
        return rows.map { row -> row.dropLastWhile { it.isEmpty } }
    }

    val seion: List<List<K>> by lazy { grid("seion", 5) }
    val dakuon: List<List<K>> by lazy { grid("dakuon", 5) }
    val youon: List<List<K>> by lazy { grid("youon", 3) }

    companion object {
        /** Flat distractor pools for Lessons -> Learn's tile game (74 each), including small ゃゅょ. */
        val hiraganaPool: List<String> = (
            "あいうえおかきくけこがぎぐげごさしすせそざじずぜぞたちつてとだぢづでど" +
                "なにぬねのはひふへほばびぶべぼぱぴぷぺぽまみむめもやゆよゃゅょらりるれろわをん"
            ).map { it.toString() }
        val katakanaPool: List<String> = (
            "アイウエオカキクケコガギグゲゴサシスセソザジズゼゾタチツテトダヂヅデド" +
                "ナニヌネノハヒフヘホバビブベボパピプペポマミムメモヤユヨャュョラリルレロワヲン"
            ).map { it.toString() }
    }
}
