package com.kfpun.japanesedaily.data.vocab

import com.kfpun.japanesedaily.data.Course
import java.util.Locale
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromStream

/** Which synthesised voice a clip is asked for. The default voice's files carry no suffix. */
enum class AudioVoice(val suffix: String) {
    Default(""),

    /** Alternates with the default on the Challenge ladder so a listening rung is a real test. */
    Alternate("-kenzaki")
}

/** The app's one canonical language order (port of `L.languageOrder`). */
object LanguageOrder {
    val order = listOf(
        "en",
        "zh", "zh-Hant",
        "id", "ko", "vi", "th", "fil", "my",
        "hi", "bn", "ta", "te", "ne",
        "es", "fr", "it", "de", "ru"
    )

    /** Sorts [codes] into [order]; unlisted codes follow alphabetically rather than vanish. */
    fun ordered(codes: Collection<String>): List<String> {
        val rank = order.withIndex().associate { it.value to it.index }
        return codes.sortedWith(compareBy({ rank[it] ?: Int.MAX_VALUE }, { it }))
    }
}

/**
 * Loads the bundled `MinnaData.json` plus the flat audio clips (port of `VocabStore`).
 *
 * The decode happens once, lazily, on first use. Call [preload] from a background dispatcher at
 * launch so the first screen that needs a word does not pay for it on the main thread. Per-language
 * lesson lists are built lazily and cached: only the language actually shown is resolved.
 */
class VocabStore(private val assets: AssetSource, val course: Course = Course.current) {
    @Serializable
    private class LessonDto(val number: Int, val entries: List<VocabEntry>)

    @Serializable
    private class CourseData(
        val languages: List<String>,
        val lessons: List<LessonDto>,
        /** lang -> lesson number -> romaji (or key) -> text */
        val translations: Map<String, Map<String, Map<String, String>>>,
        /** Example-sentence translations, same shape; optional (JLPT has none). */
        val examples: Map<String, Map<String, Map<String, String>>>? = null
    )

    @OptIn(ExperimentalSerializationApi::class)
    private val data: CourseData by lazy {
        val json = Json { ignoreUnknownKeys = true }
        assets.open("${course.dataResource}.json").use { json.decodeFromStream<CourseData>(it) }
    }

    private val clips: Map<String, Set<String>> by lazy {
        listOf("vocab", "kana", "cheer", "examples").associateWith { assets.list("audio/$it") }
    }

    private val cache = HashMap<String, List<Lesson>>()

    /** Forces the decode now. Cheap to call repeatedly. */
    fun preload() {
        data
        clips
    }

    /** The meaning languages this course ships, in the canonical order. */
    val availableLanguages: List<String> by lazy { LanguageOrder.ordered(data.languages) }

    /** Whether this course's dataset carries example sentences at all, read off the data. */
    val hasExamples: Boolean by lazy { data.lessons.any { l -> l.entries.any { it.example != null } } }

    /**
     * First-launch default for the translation language: the device language when the data has
     * meanings for it, otherwise English. Any Chinese device defaults to Traditional.
     */
    fun deviceDefaultLanguage(locale: Locale = Locale.getDefault()): String {
        val code = when (val lang = locale.language) {
            "zh" -> "zh-Hant"

            // Older Android reports Indonesian as "in", Filipino as "tl".
            "in" -> "id"

            "tl" -> "fil"

            else -> lang
        }
        return if (code in availableLanguages) code else DEFAULT_LANGUAGE
    }

    private fun build(language: String): List<Lesson> {
        // English wholesale rather than per entry: a stored preference can name a language this
        // course lacks, and blank meanings would look like broken data.
        val tr = data.translations[language] ?: data.translations[DEFAULT_LANGUAGE].orEmpty()
        // No English fallback for example translations, deliberately (see the iOS comment).
        val ex = data.examples?.get(language).orEmpty()
        return data.lessons.map { dto ->
            val byKey = tr[dto.number.toString()].orEmpty()
            val exByKey = ex[dto.number.toString()].orEmpty()
            Lesson(
                dto.number,
                dto.entries.map { e ->
                    val k = e.key ?: e.romaji
                    Vocab(
                        lesson = dto.number,
                        kanji = e.kanji,
                        kana = e.kana,
                        romaji = e.romaji,
                        dictionary = e.dictionary,
                        useKana = e.useKana ?: false,
                        translation = byKey[k].orEmpty(),
                        audio = e.audio,
                        key = e.key,
                        example = e.example,
                        exampleTranslation = exByKey[k]
                    )
                }
            )
        }
    }

    /** All lessons with translations resolved for [language] (built once, on demand). */
    @Synchronized
    fun lessons(language: String = DEFAULT_LANGUAGE): List<Lesson> = cache.getOrPut(language) { build(language) }

    fun allVocab(language: String = DEFAULT_LANGUAGE): List<Vocab> = lessons(language).flatMap { it.entries }

    fun lesson(n: Int, language: String = DEFAULT_LANGUAGE): Lesson = lessons(language)[n - 1]

    private val wordCounts: Map<Int, Int> by lazy { data.lessons.associate { it.number to it.entries.size } }

    /**
     * How many words lesson [n] holds, read off the decoded data without building a language.
     * Out of range returns 0 rather than failing, so drift degrades instead of crashing.
     */
    fun wordCount(n: Int): Int = wordCounts[n] ?: 0

    // MARK: audio. Paths are asset paths; the player opens them with AssetManager.

    private fun has(dir: String, name: String): Boolean = clips[dir].orEmpty().contains("$name.m4a")

    /** A word's clip, in [voice] when it has one, otherwise the default voice's. Null when none. */
    fun audioPath(vocab: Vocab, voice: AudioVoice = AudioVoice.Default): String? {
        val name = vocab.audio ?: return null
        return listOf(name + voice.suffix, name).firstOrNull { has("vocab", it) }?.let { "audio/vocab/$it.m4a" }
    }

    /** The recording of a word's example sentence (`ex-` prefixed), or null. Default voice only. */
    fun exampleAudioPath(vocab: Vocab): String? {
        val name = vocab.audio ?: return null
        if (vocab.example == null) return null
        return "ex-$name".takeIf { has("examples", it) }?.let { "audio/examples/$it.m4a" }
    }

    /** A cheer's clip, e.g. `sugoi` -> `cheer-sugoi.m4a`, with the same voice fallback as words. */
    fun cheerAudioPath(key: String, voice: AudioVoice = AudioVoice.Default): String? {
        if (key.isEmpty()) return null
        return listOf("cheer-$key${voice.suffix}", "cheer-$key").firstOrNull { has("cheer", it) }
            ?.let { "audio/cheer/$it.m4a" }
    }

    /** A kana's clip, e.g. `ka` -> `kana-ka.m4a`. */
    fun kanaAudioPath(romaji: String): String? {
        if (romaji.isEmpty()) return null
        return "kana-$romaji".takeIf { has("kana", it) }?.let { "audio/kana/$it.m4a" }
    }

    companion object {
        /** The fallback for callers naming no language, and for missing translation data. */
        const val DEFAULT_LANGUAGE = "en"
    }
}

private val annotationPatterns = listOf("（.*?）", "［.*?］", "「.*?」", "\\[.*]").map { Regex(it) }

/** Strips display annotations before tiling/speaking: （…）［…］「…」[…] and the ～ / 。 marks. */
fun cleanWord(text: String): String {
    var s = text
    for (pattern in annotationPatterns) s = s.replace(pattern, "")
    return s.replace("～", "").replace("。", "")
}

/** Case-insensitive `contains` across kanji, kana, romaji and translation (not fuzzy). */
fun searchVocab(query: String, all: List<Vocab>): List<Vocab> {
    val q = query.trim().lowercase()
    if (q.isEmpty()) return emptyList()
    return all.filter { v -> listOf(v.kanji, v.kana, v.romaji, v.translation).any { it.lowercase().contains(q) } }
}
