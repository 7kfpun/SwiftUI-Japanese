package com.kfpun.japanesedaily.lessons

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalContext
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.data.prefs.PrefKey
import com.kfpun.japanesedaily.data.progress.Bookmark
import com.kfpun.japanesedaily.data.progress.WordStage
import com.kfpun.japanesedaily.data.vocab.Lesson
import com.kfpun.japanesedaily.data.vocab.Vocab
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The data every Lessons screen reads: the container and the current meaning language. */
class LessonsEnv(val container: AppContainer, languageState: State<String>) {
    val language: String by languageState

    fun lesson(n: Int): Lesson = container.vocab.lesson(n, language)

    fun wordCount(n: Int): Int = container.vocab.wordCount(n)
}

/**
 * The [LessonsEnv], or null while the course data is still decoding off the main thread: screens draw
 * their canvas and nothing else until it is ready, so a cold start never blocks the first frame.
 */
@Composable
fun rememberLessonsEnv(): LessonsEnv? {
    val context = LocalContext.current
    val container = remember { AppContainer.from(context) }
    val fallback by produceState<String?>(null) {
        value = withContext(Dispatchers.Default) {
            container.vocab.preload()
            container.practice.load()
            container.vocab.deviceDefaultLanguage()
        }
    }
    val ready = fallback ?: return null
    val language = container.prefs.translationLanguage(ready).collectAsState(initial = ready)
    return remember(container, language) { LessonsEnv(container, language) }
}

/** A stored preference as a value and a setter, so a toggle updates the screen the moment it flips. */
class PrefValue<T : Any>(val value: T, val set: (T) -> Unit)

@Composable
fun <T : Any> rememberPref(pref: PrefKey<T>, container: AppContainer): PrefValue<T> {
    val state = remember(pref) { container.prefs.flow(pref) }.collectAsState(initial = pref.default)
    val scope = rememberCoroutineScope()
    val value = state.value
    return remember(value, pref) { PrefValue(value) { new -> scope.launch { container.prefs.set(pref, new) } } }
}

/** Bookmarked words and their tier, live: the one source the chips, the stars and the shelf all read. */
@Composable
fun rememberBookmarkTiers(container: AppContainer): State<Map<String, Int>> {
    val flow = remember(container) {
        kotlinx.coroutines.flow.flow {
            container.progress.observeBookmarks().collect { rows ->
                emit(rows.associate { it.word to Bookmark.clamp(it.stars) })
            }
        }
    }
    return flow.collectAsState(initial = emptyMap())
}

/** The three cuts of the Vocab List (design 3a): which words show, and which words Read along reads. */
enum class VocabCut(val key: String) {
    All("all"),
    NotMemorized("notMemorized"),
    Bookmarked("bookmarked");

    companion object {
        fun of(key: String): VocabCut = entries.firstOrNull { it.key == key } ?: All
    }
}

/** The words a [cut] shows. "Not memorized" reads the same stages Practice writes. */
fun cutWords(cut: VocabCut, entries: List<Vocab>, stage: (Vocab) -> WordStage, tiers: Map<String, Int>): List<Vocab> =
    when (cut) {
        VocabCut.All -> entries
        VocabCut.NotMemorized -> entries.filter { stage(it) != WordStage.Memorized }
        VocabCut.Bookmarked -> entries.filter { tiers[it.id] != null }
    }

/** Where the Lessons tab is. Routes encode to strings so the stack survives a configuration change. */
sealed interface LessonRoute {
    data class Select(val lesson: Int) : LessonRoute

    data class Practice(val lesson: Int) : LessonRoute

    data class VocabList(val lesson: Int) : LessonRoute

    data class ReadAlong(val lesson: Int, val cut: String) : LessonRoute

    data class Flashcards(val lesson: Int) : LessonRoute

    data class Match(val lesson: Int) : LessonRoute

    data class Learn(val lesson: Int) : LessonRoute

    data object Bookmarks : LessonRoute

    fun encode(): String = when (this) {
        is Select -> "select:$lesson"
        is Practice -> "practice:$lesson"
        is VocabList -> "vocab:$lesson"
        is ReadAlong -> "read:$lesson:$cut"
        is Flashcards -> "flash:$lesson"
        is Match -> "match:$lesson"
        is Learn -> "learn:$lesson"
        Bookmarks -> "bookmarks"
    }

    companion object {
        fun decode(s: String): LessonRoute? {
            val p = s.split(":")
            val n = p.getOrNull(1)?.toIntOrNull()
            return when (p[0]) {
                "select" -> n?.let { Select(it) }
                "practice" -> n?.let { Practice(it) }
                "vocab" -> n?.let { VocabList(it) }
                "read" -> n?.let { ReadAlong(it, p.getOrElse(2) { "all" }) }
                "flash" -> n?.let { Flashcards(it) }
                "match" -> n?.let { Match(it) }
                "learn" -> n?.let { Learn(it) }
                "bookmarks" -> Bookmarks
                else -> null
            }
        }
    }
}

/**
 * The Lessons tab's back stack. Hoisted into `AppScaffold` so switching tabs and coming back keeps
 * the learner where they were, as the iOS per-tab `NavigationStack` does; a widget deep link can
 * [push] a lesson from outside.
 */
class LessonsNav(initial: List<LessonRoute> = emptyList()) {
    val stack = mutableStateListOf<LessonRoute>().apply { addAll(initial) }

    val current: LessonRoute? get() = stack.lastOrNull()

    fun push(route: LessonRoute) {
        stack.add(route)
    }

    /** Pops one screen; false when already at the list. */
    fun pop(): Boolean = stack.removeLastOrNull() != null

    /** Back to the list, then straight into [lesson]'s mode picker (a deep link). */
    fun openLesson(lesson: Int) {
        stack.clear()
        stack.add(LessonRoute.Select(lesson))
    }
}

@Composable
fun rememberLessonsNav(): LessonsNav = rememberSaveable(
    saver = listSaver(
        save = { nav -> nav.stack.map { it.encode() } },
        restore = { saved -> LessonsNav(saved.mapNotNull { LessonRoute.decode(it) }) }
    )
) { LessonsNav() }
