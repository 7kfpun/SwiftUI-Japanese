package com.kfpun.japanesedaily.intro

import android.content.Context
import java.util.Locale
import org.json.JSONObject

/** One sample word, built from lesson 1 of the bundled data, never hardcoded. */
data class IntroWord(val kanji: String, val kana: String, val romaji: String, val translation: String) {
    /** Whether the word carries a kanji form distinct from its kana. */
    val displaysKanji: Boolean get() = kanji.isNotEmpty() && kanji != kana
}

/** What the intro shows, read from `MinnaData.json` so the tour cannot drift from a data regeneration. */
class IntroSamples(val lesson1: List<IntroWord>, val languages: List<String>, val lessonCount: Int) {
    /**
     * Card 1 deliberately skips the first entry: わたし is kana-only, so a card built on it would
     * teach three fields where the card options toggle four. It takes the first entry with a
     * distinct kanji, falling back to the first.
     */
    val anatomyWord: IntroWord? get() = lesson1.firstOrNull { it.displaysKanji } ?: lesson1.firstOrNull()

    companion object {
        /** The meaning language the intro starts in: the device's when the data has it, else English. */
        fun defaultLanguage(available: List<String>, device: Locale = Locale.getDefault()): String {
            val candidates = listOf(device.toLanguageTag(), "${device.language}-${device.script}", device.language)
            return candidates.firstOrNull { it in available } ?: "en"
        }

        fun load(context: Context, language: String): IntroSamples = parse(
            context.assets.open("MinnaData.json").bufferedReader().use { it.readText() },
            language
        )

        fun parse(json: String, language: String): IntroSamples {
            val root = JSONObject(json)
            val languages = root.getJSONArray("languages").let { a -> List(a.length()) { a.getString(it) } }
            val lessons = root.getJSONArray("lessons")
            val entries = lessons.getJSONObject(0).getJSONArray("entries")
            val translations = root.getJSONObject("translations")
            val table = (translations.optJSONObject(language) ?: translations.optJSONObject("en"))
                ?.optJSONObject("1")
            val words = List(entries.length()) {
                val e = entries.getJSONObject(it)
                val romaji = e.getString("romaji")
                val kana = e.getString("kana")
                // `useKana` marks entries whose kanji form is not what the card should lead with.
                val kanji = if (e.optBoolean("useKana")) kana else e.getString("kanji")
                IntroWord(kanji, kana, romaji, table?.optString(romaji).orEmpty())
            }
            return IntroSamples(words, languages, lessons.length())
        }
    }
}
