package com.kfpun.japanesedaily.audio

import android.content.Context
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.data.Course
import com.kfpun.japanesedaily.data.vocab.AudioVoice
import com.kfpun.japanesedaily.data.vocab.K
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.data.vocab.VocabStore
import com.kfpun.japanesedaily.data.vocab.cleanWord
import kotlin.random.Random

/**
 * The real [Pronouncer] (port of `AudioPronouncer`). Order for every sound: the bundled VOICEVOX
 * clip first, live TTS (ja-JP) when there is none. One sound at a time (every call stops the last),
 * under transient audio focus with ducking, released as soon as it ends.
 *
 * A device with no Japanese voice makes nothing play and calls [onNoJapaneseVoice] once per
 * process, so the app can show a single hint instead of one per tap.
 */
class AudioPronouncer(
    private val store: VocabStore,
    private val clips: ClipPlayer,
    private val tts: TtsEngine,
    private val focus: AudioFocus,
    private val course: Course = Course.current,
    private val onMissing: (String) -> Unit = Track::audioMissing,
    private val onNoJapaneseVoice: () -> Unit = {},
    private val random: Random = Random.Default
) : Pronouncer {
    private var hintShown = false

    override fun speak(vocab: Vocab, voice: AudioVoice, rate: Float, onDone: () -> Unit) {
        val path = store.audioPath(vocab, voice)
        playClip(path, rate, onDone) {
            // Only an anomaly for a course that ships clips; a clip-less course speaks by design.
            if (course.hasBundledAudio) onMissing(vocab.id)
            live(vocab.kana, rate, onDone)
        }
    }

    override fun speak(kana: K) {
        val path = store.kanaAudioPath(kana.romaji)
        playClip(path, 1f, {}) {
            onMissing("kana-${kana.romaji}")
            live(kana.hiragana, 1f, {})
        }
    }

    override fun speakText(text: String, rate: Float, onDone: () -> Unit) {
        stop()
        live(text, rate, onDone)
    }

    /** No `audioMissing` here: sixteen phrases would drown a signal calibrated for a few words in thousands. */
    override fun speakCheer(key: String, fallbackText: String) {
        playClip(store.cheerAudioPath(key, Speech.randomVoice(random)), 1f, {}) {
            live(fallbackText, 1f, {})
        }
    }

    override fun speakExample(vocab: Vocab, rate: Float, onDone: () -> Unit) {
        val path = store.exampleAudioPath(vocab)
        playClip(path, rate, onDone) {
            val spoken = vocab.example?.spoken
            if (spoken != null) live(spoken, rate, onDone)
        }
    }

    override fun speakMeaning(text: String, languageTag: String, rate: Float, onDone: () -> Unit) {
        stop()
        if (text.isBlank()) return
        if (!focus.request(onLost = ::stop)) return
        tts.speak(
            TtsRequest(text, languageTag, Speech.TTS_RATE * rate),
            // No voice for the learner's language: say nothing and move on rather than stall the run.
            onUnavailable = {
                focus.abandon()
                onDone()
            },
            onDone = {
                focus.abandon()
                onDone()
            }
        )
    }

    override fun stop() {
        clips.stop()
        tts.stop()
        focus.abandon()
    }

    /** Frees the clip player and the synthesiser (app going away). */
    fun release() {
        stop()
        clips.release()
        tts.release()
    }

    /** Plays [path] when there is one and it starts; otherwise runs [fallback] (after stopping the last sound). */
    private fun playClip(path: String?, rate: Float, onDone: () -> Unit, fallback: () -> Unit) {
        stop()
        if (path != null) {
            if (!focus.request(onLost = ::stop)) return
            val started = clips.play(path, rate) {
                focus.abandon()
                onDone()
            }
            if (started) return
            focus.abandon()
        }
        fallback()
    }

    private fun live(text: String, rate: Float, onDone: () -> Unit) {
        val spoken = cleanWord(text)
        if (spoken.isBlank()) return
        if (!focus.request(onLost = ::stop)) return
        tts.speak(
            TtsRequest(spoken, Speech.LOCALE, Speech.TTS_RATE * rate),
            onUnavailable = {
                focus.abandon()
                if (!hintShown) {
                    hintShown = true
                    onNoJapaneseVoice()
                }
            },
            onDone = {
                focus.abandon()
                onDone()
            }
        )
    }

    companion object {
        fun create(context: Context, vocab: VocabStore, onNoJapaneseVoice: () -> Unit = {}): AudioPronouncer =
            AudioPronouncer(
                store = vocab,
                clips = MediaClipPlayer(context.applicationContext.assets),
                tts = AndroidTtsEngine(context),
                focus = SystemAudioFocus(context),
                onNoJapaneseVoice = onNoJapaneseVoice
            )
    }
}
