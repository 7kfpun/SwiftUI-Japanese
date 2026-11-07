package com.kfpun.japanesedaily.audio

/** Plays one bundled clip at a time. Real: [MediaClipPlayer]; tests use a fake. */
interface ClipPlayer {
    /**
     * Starts the clip at asset [path] at [rate], replacing whatever plays. Returns false when it
     * could not start (nothing was played, [onDone] will not fire). [onDone] fires once when the
     * clip ends or fails, never after [stop].
     */
    fun play(path: String, rate: Float = 1f, onDone: () -> Unit = {}): Boolean

    fun stop()

    fun release()
}

/** One piece of text for the live synthesiser. */
data class TtsRequest(val text: String, val languageTag: String, val rate: Float = 1f)

/** The live-TTS fallback. Real: [AndroidTtsEngine]; tests use a fake. */
interface TtsEngine {
    /**
     * Speaks [request], replacing whatever is being spoken. [onDone] fires once when it finishes.
     * When the device has no voice for the language, [onUnavailable] fires instead (no crash,
     * nothing spoken).
     */
    fun speak(request: TtsRequest, onUnavailable: () -> Unit, onDone: () -> Unit = {})

    fun stop()

    /** Frees the engine. A later [speak] starts it again. */
    fun release()
}

/** Audio focus for a clip: ducks other audio while a word plays. */
interface AudioFocus {
    /** Asks for transient focus with ducking. [onLost] fires when another app takes focus. */
    fun request(onLost: () -> Unit): Boolean

    fun abandon()
}
