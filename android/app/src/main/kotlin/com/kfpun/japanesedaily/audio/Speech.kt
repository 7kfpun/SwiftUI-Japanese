package com.kfpun.japanesedaily.audio

import com.kfpun.japanesedaily.data.vocab.AudioVoice
import kotlin.random.Random

/**
 * One speech policy, shared by every playback path (port of the iOS `enum Speech`): the course's
 * language, the live-TTS rate and the tags a meaning is spoken in.
 */
object Speech {
    /** The course's language. */
    const val LOCALE = "ja-JP"

    /** Android TTS speech rate for Japanese. 1.0 is the engine's normal speed; iOS speaks at 0.4 of its scale. */
    const val TTS_RATE = 0.8f

    /** One of the two recorded voices, for a ladder question that wants an unpredictable voice. */
    fun randomVoice(random: Random = Random.Default): AudioVoice =
        if (random.nextBoolean()) AudioVoice.Default else AudioVoice.Alternate

    /**
     * The BCP-47 tag to speak a meaning in. `zh` is Simplified in this data set, so it must ask for
     * `zh-CN` rather than the bare code, and Filipino is `fil-PH`.
     */
    fun meaningLocale(language: String): String = when (language) {
        "zh" -> "zh-CN"
        "zh-Hant" -> "zh-TW"
        "en" -> "en-US"
        "fil" -> "fil-PH"
        else -> language
    }
}
