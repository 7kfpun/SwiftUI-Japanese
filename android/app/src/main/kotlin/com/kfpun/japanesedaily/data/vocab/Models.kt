package com.kfpun.japanesedaily.data.vocab

import kotlinx.serialization.Serializable

/** One vocabulary row as stored in `MinnaData.json` (port of `VocabEntry`). */
@Serializable
data class VocabEntry(
    val kanji: String,
    val kana: String,
    val romaji: String,
    val dictionary: String? = null,
    val useKana: Boolean? = null,
    /** Bundled clip basename, no extension, e.g. `1-watashi`. */
    val audio: String? = null,
    val example: ExampleSentence? = null,
    /** Stable per-entry key; absent in Minna, where romaji is unique within a lesson. */
    val key: String? = null
)

/**
 * A vocabulary item with its lesson number and resolved translation: what the UI renders and
 * what search indexes (port of `Vocab`).
 */
data class Vocab(
    val lesson: Int,
    val kanji: String,
    val kana: String,
    val romaji: String,
    val dictionary: String?,
    val useKana: Boolean,
    val translation: String,
    val audio: String?,
    val key: String?,
    val example: ExampleSentence? = null,
    val exampleTranslation: String? = null
) {
    /** romaji is only unique within a lesson, so the id includes the lesson. */
    val id: String get() = "$lesson/${key ?: romaji}"

    /** Show kana instead of kanji when the source says so, or when they are identical. */
    val displaysKanji: Boolean get() = !useKana && kanji != kana
}

data class Lesson(val number: Int, val entries: List<Vocab>) {
    val id: Int get() = number
}

/** The kanji core a furigana reading sits over, with the shared prefix and suffix around it. */
data class Annotated(val prefix: String, val core: String, val suffix: String, val reading: String)

/** One example sentence, split into index-aligned phrases (port of `ExampleSentence`). */
@Serializable
data class ExampleSentence(val kanji: List<String>, val kana: List<String>, val romaji: List<String>) {
    /** What the synthesiser reads: the kana the sentences were authored in. */
    val spoken: String get() = kana.joinToString("")

    /** The furigana for phrase [i], or null when nothing needs annotating. */
    fun reading(i: Int): String? = annotated(i)?.reading

    /**
     * Phrase [i] split for furigana layout. Real furigana marks only the kanji, so the characters
     * the two strings share at either end (です。 suffixes, お〜 prefixes) are trimmed off.
     */
    fun annotated(i: Int): Annotated? {
        if (i !in kanji.indices || i !in kana.indices) return null
        val written = kanji[i].toMutableList()
        val read = kana[i].toMutableList()
        if (written == read) return null
        val prefix = StringBuilder()
        while (written.isNotEmpty() && read.isNotEmpty() && written.first() == read.first()) {
            prefix.append(written.removeAt(0))
            read.removeAt(0)
        }
        val suffix = StringBuilder()
        while (written.isNotEmpty() && read.isNotEmpty() && written.last() == read.last() &&
            (read.size > 1 || written.size > 1)
        ) {
            suffix.insert(0, written.removeAt(written.lastIndex))
            read.removeAt(read.lastIndex)
        }
        if (read.isEmpty()) return null
        return Annotated(prefix.toString(), written.joinToString(""), suffix.toString(), read.joinToString(""))
    }
}
