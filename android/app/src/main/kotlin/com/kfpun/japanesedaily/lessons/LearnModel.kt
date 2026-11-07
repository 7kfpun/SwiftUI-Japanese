package com.kfpun.japanesedaily.lessons

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.kfpun.japanesedaily.data.vocab.KanaData
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.data.vocab.cleanWord
import kotlin.random.Random

enum class AnswerState { InProgress, Correct, Wrong }

data class Tile(val id: Int, val text: String)

/** Tile reconstruction (port of `LearnModel`): rebuild a word's kana reading from shuffled tiles. */
class LearnModel(val vocab: List<Vocab>, private val random: Random = Random.Default) {
    var index: Int by mutableStateOf(0)
        private set
    var tiles: List<Tile> by mutableStateOf(emptyList())
        private set
    var answer: List<String> by mutableStateOf(emptyList())
        private set
    var state: AnswerState by mutableStateOf(AnswerState.InProgress)
        private set

    /** Guarded like Practice and Match: bad data degrades to an unplayable card rather than crashing. */
    val current: Vocab
        get() = vocab.getOrNull(index)
            ?: Vocab(0, "", "", "", null, false, "", null, null)

    val target: String get() = cleanWord(current.kana)

    /**
     * Some entries are sentence-length and exceed the tile cap (one in lesson 14). An *empty* target is just
     * as unplayable as a too-long one.
     */
    val isPlayable: Boolean get() = tiles.isNotEmpty() || (target.isNotEmpty() && target.length <= MAX_TARGET)

    init {
        loadTiles()
    }

    /** Tiles: the target's characters plus `10 - length` distractors (`15 - length` if that is negative). */
    fun loadTiles() {
        answer = emptyList()
        state = AnswerState.InProgress
        val clean = target.map { it.toString() }
        val first = clean.firstOrNull()
        if (first == null) {
            tiles = emptyList()
            return
        }
        var length = 10 - clean.size
        if (length < 0) length = MAX_TARGET - clean.size
        if (length < 0) {
            tiles = emptyList() // sentence-length: no tile game
            return
        }
        val pool = if (first in KanaData.hiraganaPool) KanaData.hiraganaPool else KanaData.katakanaPool
        val distractors = pool.shuffled(random).take(length)
        tiles = (distractors + clean).shuffled(random).mapIndexed { i, t -> Tile(i, t) }
    }

    /** Append the tapped character: correct once it equals the target, wrong once it is no longer a prefix. */
    fun tap(tile: Tile) {
        if (state != AnswerState.InProgress || answer.size >= target.length) return
        answer = answer + tile.text
        val built = answer.joinToString("")
        if (built == target) {
            state = AnswerState.Correct
        } else if (!target.startsWith(built)) {
            state = AnswerState.Wrong
        }
    }

    fun clearAnswer() {
        answer = emptyList()
        state = AnswerState.InProgress
    }

    fun next() {
        if (vocab.isEmpty()) return
        index = (index + 1) % vocab.size
        loadTiles()
    }

    fun prev() {
        if (vocab.isEmpty()) return
        index = (index - 1 + vocab.size) % vocab.size
        loadTiles()
    }

    fun random() {
        if (vocab.isEmpty()) return
        index = random.nextInt(vocab.size)
        loadTiles()
    }

    companion object {
        const val MAX_TARGET = 15
    }
}
