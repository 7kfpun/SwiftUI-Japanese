package com.kfpun.japanesedaily.kana

import androidx.annotation.StringRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.data.vocab.K
import com.kfpun.japanesedaily.data.vocab.KanaData
import com.kfpun.japanesedaily.ui.KanaForm
import kotlin.random.Random

/** The three charts of the browser (iOS `KanaTable`). The raw value is what `kana_table` logs. */
enum class KanaTable(val raw: String, @StringRes val title: Int) {
    Seion("seion", R.string.seion),
    Dakuon("dakuon", R.string.dakuon),
    Youon("youon", R.string.youon);

    fun rows(data: KanaData): List<List<K>> = when (this) {
        Seion -> data.seion
        Dakuon -> data.dakuon
        Youon -> data.youon
    }

    /** The real cells of the chart, placeholders dropped. */
    fun pool(data: KanaData): List<K> = rows(data).flatten().filter { !it.isEmpty }
}

/** The kana a tile or prompt shows in [form]. */
fun K.value(form: KanaForm): String = when (form) {
    KanaForm.Hiragana -> hiragana
    KanaForm.Katakana -> katakana
    KanaForm.Romaji -> romaji
}

/** The analytics label of a form (iOS `KForm.label`). */
val KanaForm.label: String get() = name.lowercase()

/**
 * What the browser's toolbar button rotates through. **The index is the persisted `kanaTileScript` pref**:
 * appending is safe, reordering would rewrite everyone's setting. [form] is what the tile shows big.
 */
enum class TileScript(val glyph: String, val form: KanaForm, @StringRes val name: Int) {
    Hiragana("あ", KanaForm.Hiragana, R.string.hiragana),
    Katakana("ア", KanaForm.Katakana, R.string.katakana),
    Romaji("A", KanaForm.Romaji, R.string.romaji);

    companion object {
        fun of(index: Int): TileScript = entries[index.mod(entries.size)]
        fun next(index: Int): Int = (index + 1) % entries.size
    }
}

/** Distinct romaji in a chart: じ/ぢ and ず/づ share one by design, so tiles outnumber answers. */
fun distinctRomaji(cells: Iterable<K>): Set<String> = cells.filter { !it.isEmpty }.map { it.romaji }.toSet()

/** How many of [cells]' distinct kana the learner's latest answer got right. */
fun learnedCount(cells: Iterable<K>, latest: Map<String, Boolean>): Int =
    distinctRomaji(cells).count { latest[it] == true }

/**
 * Any-form to any-form multiple choice (iOS `KanaQuizModel`), driving Classic, Listening and Swipe (2 options).
 * [swapFrom] and [swapTo] exchange the active side with the reserve form. Answers are recorded unconditionally,
 * right or wrong, through [record]: the browser tile shows the last answer, not only the successes.
 */
class KanaQuizModel(
    pool: List<K>,
    val optionCount: Int = 4,
    private val random: Random = Random.Default,
    private val record: (romaji: String, correct: Boolean) -> Unit = { _, _ -> }
) {
    val pool: List<K> = pool.filter { !it.isEmpty }

    var from by mutableStateOf(KanaForm.Hiragana)
        private set
    var to by mutableStateOf(KanaForm.Romaji)
        private set
    private var other = KanaForm.Katakana

    var options by mutableStateOf<List<K>>(emptyList())
        private set
    var answer by mutableStateOf(K("", "", ""))
        private set
    var picked by mutableStateOf<Int?>(null)
        private set
    var correct by mutableIntStateOf(0)
        private set
    var total by mutableIntStateOf(0)
        private set

    init {
        next()
    }

    /** Both swaps log the direction *after* the swap: the pair the learner asked for. */
    fun swapFrom() {
        val old = from
        from = other
        other = old
        logDirection()
    }

    fun swapTo() {
        val old = to
        to = other
        other = old
        logDirection()
    }

    private fun logDirection() =
        Track.event(TrackEvents.KANA_QUIZ_DIRECTION, mapOf("from" to from.label, "to" to to.label))

    fun next() {
        picked = null
        if (pool.isEmpty()) return
        val ans = pool.random(random)
        val opts = mutableListOf(ans)
        var guard = 0
        while (opts.size < minOf(optionCount, distinctRomaji(pool).size) && guard < GUARD) {
            guard++
            val c = pool.random(random)
            if (opts.none { it.romaji == c.romaji }) opts.add(c)
        }
        answer = ans
        options = opts.shuffled(random)
    }

    fun isCorrectOption(i: Int): Boolean = options[i].romaji == answer.romaji

    /** Locks the pick, updates the session score and records it. Ignored once answered. Returns whether it was right. */
    fun choose(i: Int): Boolean? {
        if (picked != null || i !in options.indices) return null
        picked = i
        val right = isCorrectOption(i)
        total += 1
        if (right) correct += 1
        record(answer.romaji, right)
        return right
    }

    private companion object {
        const val GUARD = 1000
    }
}

/**
 * A spaced-repetition-lite deck over any element type (iOS `FlashDeck`). Cards start shuffled. Swipe right
 * (know) retires a card, left (don't know) sends it to the back; the deck ends when every card was retired.
 */
class FlashDeck<T>(private val all: List<T>, private val random: Random = Random.Default) {
    private var queue by mutableStateOf(all.shuffled(random))
    var mastered by mutableIntStateOf(0)
        private set

    val total: Int = all.size
    val current: T? get() = queue.firstOrNull()
    val isDone: Boolean get() = queue.isEmpty()
    val remaining: Int get() = queue.size

    /** Up to [n] cards after the current one, for the decorative peek behind the top card. */
    fun peek(n: Int): List<T> = queue.drop(1).take(n)

    fun know() {
        if (queue.isEmpty()) return
        queue = queue.drop(1)
        mastered += 1
    }

    fun dontKnow() {
        if (queue.isEmpty()) return
        queue = queue.drop(1) + queue.first()
    }

    fun restart() {
        queue = all.shuffled(random)
        mastered = 0
    }
}
