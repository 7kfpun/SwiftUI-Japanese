package com.kfpun.japanesedaily.lessons

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.kfpun.japanesedaily.audio.Pronouncer
import com.kfpun.japanesedaily.audio.Speech
import com.kfpun.japanesedaily.data.vocab.Vocab
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Plays a whole lesson end to end (port of `LessonPlayer`, the old "Read All"): each word's clip through
 * the [Pronouncer], then, per [ReadMode], its meaning, its example sentence and that sentence's meaning.
 * A run is one coroutine on [scope], so [stop] is a cancel and no stale callback can advance a dead run.
 *
 * Pause stops the sound and the run; [resume] restarts the *current* word, because half a word is worse
 * than the word again. The player loops only when asked (subscribers, see `Gating.loopsForever`).
 */
class LessonPlayer(private val pronouncer: Pronouncer, private val scope: CoroutineScope) {
    var currentIndex: Int? by mutableStateOf(null)
        private set
    var isPlaying: Boolean by mutableStateOf(false)
        private set
    var isPaused: Boolean by mutableStateOf(false)
        private set
    var mode: ReadMode by mutableStateOf(ReadMode.Japanese)
        private set

    /** Which lap of the list this is, from 1: the loop counter `read_all_loop` logs. */
    var lap: Int by mutableStateOf(1)
        private set

    /** Fires once when a non-looping run reaches the end of its list (the preview paywall hangs off it). */
    var onFinished: (() -> Unit)? = null
    var onLap: ((Int) -> Unit)? = null

    /** Playback speed multiplier; applies from the next clip. */
    var rate: Double = 1.0

    private var entries: List<Vocab> = emptyList()
    private var loops = true
    private var meaningTag = Speech.meaningLocale("en")
    private var job: Job? = null

    val count: Int get() = entries.size
    val currentWord: Vocab? get() = currentIndex?.let { entries.getOrNull(it) }

    /** Starts [list], or stops when this mode is already playing (the mode segments are toggles). */
    fun toggle(list: List<Vocab>, mode: ReadMode, language: String, loops: Boolean = true) {
        val wasPlayingSameMode = isPlaying && this.mode == mode
        if (isPlaying) stop()
        if (wasPlayingSameMode) return
        entries = list
        this.mode = mode
        this.loops = loops
        lap = 1
        meaningTag = Speech.meaningLocale(language)
        isPlaying = true
        isPaused = false
        launchFrom(0)
    }

    /** Jump to word [i]. A jump is a resume: from paused it plays on. */
    fun play(word: Int) {
        if (!isPlaying || word !in entries.indices) return
        isPaused = false
        launchFrom(word)
    }

    fun stop() {
        job?.cancel()
        job = null
        pronouncer.stop()
        isPlaying = false
        isPaused = false
        currentIndex = null
    }

    fun pause() {
        if (!isPlaying || isPaused) return
        isPaused = true
        job?.cancel()
        job = null
        pronouncer.stop()
    }

    fun resume() {
        if (!isPlaying || !isPaused) return
        isPaused = false
        launchFrom(currentIndex ?: 0)
    }

    /** Ends the run for good, for a screen leaving the composition: also drops the callbacks. */
    fun release() {
        onFinished = null
        onLap = null
        stop()
    }

    private fun launchFrom(start: Int) {
        job?.cancel()
        pronouncer.stop()
        job = scope.launch { run(start) }
    }

    private suspend fun run(start: Int) {
        var i = start
        while (true) {
            currentIndex = i
            playEntry(entries[i])
            delay(BETWEEN_WORDS_MILLIS)
            when (val step = step(i, entries.size, loops)) {
                is Step.Next -> i = step.index

                Step.Wrap -> {
                    lap += 1
                    onLap?.invoke(lap)
                    // After the callback: if it stopped playback, do not play on regardless.
                    if (!isPlaying) return
                    i = 0
                }

                Step.End -> {
                    val finished = onFinished
                    stop()
                    finished?.invoke()
                    return
                }
            }
        }
    }

    private suspend fun playEntry(v: Vocab) {
        awaitLeg { done -> pronouncer.speak(v, rate = rate.toFloat(), onDone = done) }
        if (!mode.readsBeyondTheWord) return
        // A word with no meaning in this language behaves like the Japanese-only mode.
        if (v.translation.isNotEmpty()) {
            delay(BEFORE_MEANING_MILLIS)
            awaitLeg { done -> pronouncer.speakMeaning(v.translation, meaningTag, rate.toFloat(), done) }
        }
        if (mode != ReadMode.WithExample || v.example == null) return
        delay(BEFORE_MEANING_MILLIS)
        awaitLeg { done -> pronouncer.speakExample(v, rate.toFloat(), done) }
        val sentenceMeaning = v.exampleTranslation
        if (!sentenceMeaning.isNullOrEmpty()) {
            delay(BEFORE_MEANING_MILLIS)
            awaitLeg { done -> pronouncer.speakMeaning(sentenceMeaning, meaningTag, rate.toFloat(), done) }
        }
    }

    /** Waits for one leg to report done; a leg that never starts (no voice, no focus) times out, the run moves on. */
    private suspend fun awaitLeg(start: (done: () -> Unit) -> Unit) {
        withTimeoutOrNull(LEG_TIMEOUT_MILLIS) {
            suspendCancellableCoroutine { cont -> start { if (cont.isActive) cont.resume(Unit) } }
        }
    }

    sealed interface Step {
        data class Next(val index: Int) : Step

        data object Wrap : Step

        data object End : Step
    }

    companion object {
        const val BETWEEN_WORDS_MILLIS = 1200L
        const val BEFORE_MEANING_MILLIS = 650L
        private const val LEG_TIMEOUT_MILLIS = 30_000L

        /** What follows word [i]: the next word, a wrap to the top, or the end. An empty list cannot wrap. */
        fun step(i: Int, count: Int, loops: Boolean): Step = when {
            i + 1 < count -> Step.Next(i + 1)
            loops && count > 0 -> Step.Wrap
            else -> Step.End
        }
    }
}
