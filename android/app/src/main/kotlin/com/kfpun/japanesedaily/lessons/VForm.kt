package com.kfpun.japanesedaily.lessons

import com.kfpun.japanesedaily.data.vocab.Vocab

/**
 * The forms a vocabulary question can show (port of `VForm`), shared by Practice and, later, the
 * Challenge ladder. [label] is the stable ASCII analytics key, never localized text.
 */
enum class VForm(val label: String) {
    Kana("kana"),
    Kanji("kanji"),
    Romaji("romaji"),
    Translation("meaning"),
    Audio("audio");

    fun value(v: Vocab): String = when (this) {
        Kana -> v.kana
        Kanji -> v.kanji
        Romaji -> v.romaji
        Translation -> v.translation
        Audio -> v.kana // never shown: the audio prompt uses a speaker
    }

    val isAudio: Boolean get() = this == Audio

    /**
     * Whether this form's value is written in Japanese script, i.e. whether a Japanese face may draw
     * it. The face follows the content's script, not the screen.
     */
    val isJapanese: Boolean get() = this != Romaji && this != Translation

    companion object {
        /**
         * Whether auto-playing the word is safe for a prompt form: fine when the prompt IS the word,
         * but a translation prompt with word options would be given away.
         */
        fun promptAudioSafe(from: VForm): Boolean = from != Translation

        /**
         * The same question asked of the whole pair: a kana or romaji *answer* is safe to auto-play only
         * when the prompt already carries that sound (an audio rung, or the reading itself).
         */
        fun promptAudioSafe(from: VForm, to: VForm): Boolean {
            if (!promptAudioSafe(from)) return false
            if (to != Kana && to != Romaji) return true
            return from == Audio || from == Kana || from == Romaji
        }
    }
}
