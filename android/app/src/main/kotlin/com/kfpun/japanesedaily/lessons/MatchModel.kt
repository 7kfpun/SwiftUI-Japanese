package com.kfpun.japanesedaily.lessons

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.kfpun.japanesedaily.data.vocab.Vocab
import kotlin.random.Random

/**
 * Endless pair-matching over a lesson's vocabulary (port of `MatchModel`): five words down the left,
 * their meanings shuffled down the right. Tap order is free (meanings-first is recall, the more valuable
 * direction). Matching compares vocab **ids**, never displayed text.
 *
 * The model holds feedback state no longer than it is drawn and the *view* clears it ([clearMiss],
 * [dealNext]): a model that arms its own timers cannot be tested without waiting for them.
 */
class MatchModel(val vocab: List<Vocab>, private val random: Random = Random.Default) {
    enum class Side { Left, Right }

    data class Tile(val id: String, val text: String, val isJapanese: Boolean, val cleared: Boolean = false)

    var left: List<Tile> by mutableStateOf(emptyList())
        private set
    var right: List<Tile> by mutableStateOf(emptyList())
        private set
    var pickedLeft: Int? by mutableStateOf(null)
        private set
    var pickedRight: Int? by mutableStateOf(null)
        private set

    /** True only while a wrong pair is on screen. */
    var wrong: Boolean by mutableStateOf(false)
        private set

    /** The id of the pair just cleared, for the green flash. */
    var lastMatched: String? by mutableStateOf(null)
        private set

    /** True once every pair is cleared, until the view calls [dealNext]. */
    var roundCleared: Boolean by mutableStateOf(false)
        private set
    var matched: Int by mutableStateOf(0)
        private set
    var attempts: Int by mutableStateOf(0)
        private set
    var rounds: Int by mutableStateOf(0)
        private set

    /** How the most recent pick arrived, `"tap"` or `"drag"`, carried onto `match_answer`. */
    var lastVia: String = "tap"
        private set

    private var round: List<Vocab> = emptyList()
    private var bag: MutableList<Vocab> = mutableListOf()

    init {
        deal()
    }

    fun word(id: String): Vocab? = round.firstOrNull { it.id == id }

    /** Tap a tile. Ignored while a miss is showing, on a cleared tile, and between the last match and the next deal. */
    fun pick(side: Side, index: Int, via: String = "tap") {
        if (wrong || roundCleared) return
        lastVia = via
        when (side) {
            Side.Left -> {
                if (index !in left.indices || left[index].cleared) return
                pickedLeft = index
            }

            Side.Right -> {
                if (index !in right.indices || right[index].cleared) return
                pickedRight = index
            }
        }
        resolve()
    }

    /** Dismiss a shown miss and free both columns again. */
    fun clearMiss() {
        wrong = false
        pickedLeft = null
        pickedRight = null
    }

    private fun resolve() {
        val l = pickedLeft ?: return
        val r = pickedRight ?: return
        attempts += 1
        if (left[l].id != right[r].id) {
            wrong = true
            return
        }
        left = left.mapIndexed { i, t -> if (i == l) t.copy(cleared = true) else t }
        right = right.mapIndexed { i, t -> if (i == r) t.copy(cleared = true) else t }
        lastMatched = left[l].id
        matched += 1
        pickedLeft = null
        pickedRight = null
        // `isNotEmpty`: an empty round satisfies `all` vacuously.
        if (left.isNotEmpty() && left.all { it.cleared }) roundCleared = true
    }

    /** Deal the next round, once the view has let the last match land. */
    fun dealNext() {
        if (!roundCleared) return
        deal()
    }

    /**
     * A candidate is rejected if it repeats a word already dealt *or* reads the same on either side: two
     * tiles with the same text make one pairing arbitrary (なん/なに and shared glosses).
     */
    private fun deal() {
        if (vocab.isEmpty()) {
            left = emptyList()
            right = emptyList()
            round = emptyList()
            return
        }
        rounds += 1
        lastMatched = null
        roundCleared = false
        val picks = mutableListOf<Vocab>()
        var guard = 0
        val want = minOf(PAIRS_PER_ROUND, vocab.size)
        while (picks.size < want && guard < 2000) {
            guard += 1
            val c = drawFromBag()
            if (picks.any { it.id == c.id || it.kana == c.kana || it.translation == c.translation }) continue
            picks.add(c)
        }
        round = picks
        left = picks.map { Tile(it.id, it.kana, isJapanese = true) }
        // Reversed rather than reshuffled on a collision: a round whose columns already line up is no puzzle.
        var shuffled = picks.shuffled(random)
        if (picks.size > 1 && shuffled.map { it.id } == picks.map { it.id }) shuffled = shuffled.reversed()
        right = shuffled.map { Tile(it.id, it.translation, isJapanese = false) }
        pickedLeft = null
        pickedRight = null
        wrong = false
    }

    /** The no-repeat bag: independent random draws re-deal words just seen while others never appear. */
    private fun drawFromBag(): Vocab {
        if (bag.isEmpty()) bag = vocab.shuffled(random).toMutableList()
        return bag.removeAt(bag.lastIndex)
    }

    companion object {
        /** Pairs on screen at once: the most that fits two readable columns at large type without scrolling. */
        const val PAIRS_PER_ROUND = 5
    }
}
