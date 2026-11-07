package com.kfpun.japanesedaily.audio

import androidx.compose.runtime.staticCompositionLocalOf
import com.kfpun.japanesedaily.data.vocab.AudioVoice
import com.kfpun.japanesedaily.data.vocab.K
import com.kfpun.japanesedaily.data.vocab.Vocab

/**
 * Word-pronunciation seam (port of the iOS `Pronouncer`): every "tap to hear" path goes through
 * it, so no screen knows how a word is played. [AudioPronouncer] is the real one; [SilentPronouncer]
 * is the composition default, so previews and tests make no sound.
 *
 * [rate] is a multiplier (Read along's speed dial, already clamped by [PlaybackRates.effective]);
 * [onDone] fires when playback ends, so a sequencer can advance. It does not fire after [stop].
 */
interface Pronouncer {
    /** A word: its clip in [voice] (falling back to the default voice's), else live TTS of its kana. */
    fun speak(vocab: Vocab, voice: AudioVoice = AudioVoice.Default, rate: Float = 1f, onDone: () -> Unit = {})

    /** A kana chart cell: its bundled clip, else live TTS of the hiragana. */
    fun speak(kana: K)

    /** A bare text tile (no clip exists for it): live TTS only, annotations stripped. */
    fun speakText(text: String, rate: Float = 1f, onDone: () -> Unit = {})

    /** A Challenge cheer by key (`sugoi`), in a random voice; live TTS of [fallbackText] when unbundled. */
    fun speakCheer(key: String, fallbackText: String)

    /** A word's example sentence: its clip when it has one, else live TTS of the sentence. */
    fun speakExample(vocab: Vocab, rate: Float = 1f, onDone: () -> Unit = {})

    /** A meaning in the learner's language ([languageTag] a BCP-47 tag): live TTS only, no clip exists. */
    fun speakMeaning(text: String, languageTag: String, rate: Float = 1f, onDone: () -> Unit = {})

    fun stop()
}

object SilentPronouncer : Pronouncer {
    override fun speak(vocab: Vocab, voice: AudioVoice, rate: Float, onDone: () -> Unit) = Unit

    override fun speak(kana: K) = Unit

    override fun speakText(text: String, rate: Float, onDone: () -> Unit) = Unit

    override fun speakCheer(key: String, fallbackText: String) = Unit

    override fun speakExample(vocab: Vocab, rate: Float, onDone: () -> Unit) = Unit

    override fun speakMeaning(text: String, languageTag: String, rate: Float, onDone: () -> Unit) = Unit

    override fun stop() = Unit
}

val LocalPronouncer = staticCompositionLocalOf<Pronouncer> { SilentPronouncer }
