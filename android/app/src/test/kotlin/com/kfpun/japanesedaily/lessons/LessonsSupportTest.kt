package com.kfpun.japanesedaily.lessons

import com.kfpun.japanesedaily.data.progress.WordStage
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.VocabStore
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LessonsSupportTest {
    private val store = VocabStore(FileAssetSource(File("../../nihongo/Resources")))

    @Test
    fun routesSurviveTheSavedStateRoundTrip() {
        val routes = listOf(
            LessonRoute.Select(7),
            LessonRoute.Practice(1),
            LessonRoute.VocabList(50),
            LessonRoute.ReadAlong(3, "notMemorized"),
            LessonRoute.Flashcards(2),
            LessonRoute.Match(4),
            LessonRoute.Learn(5),
            LessonRoute.Bookmarks
        )
        for (r in routes) assertEquals(r, LessonRoute.decode(r.encode()))
        assertNull(LessonRoute.decode("nonsense"))
        assertNull(LessonRoute.decode("select:x"))
    }

    @Test
    fun navPushesPopsAndDeepLinks() {
        val nav = LessonsNav()
        assertNull(nav.current)
        nav.push(LessonRoute.Select(2))
        nav.push(LessonRoute.Practice(2))
        assertEquals(LessonRoute.Practice(2), nav.current)
        assertEquals(true, nav.pop())
        nav.openLesson(9)
        assertEquals(listOf<LessonRoute>(LessonRoute.Select(9)), nav.stack.toList())
        nav.pop()
        assertEquals(false, nav.pop())
    }

    @Test
    fun cutsFilterByStageAndBookmark() {
        val entries = store.lesson(1).entries
        val stages = mapOf(entries[0].id to WordStage.Memorized, entries[1].id to WordStage.Seen)
        val stage = { v: com.kfpun.japanesedaily.data.vocab.Vocab -> stages[v.id] ?: WordStage.Unseen }
        val tiers = mapOf(entries[1].id to 2)
        assertEquals(entries.size, cutWords(VocabCut.All, entries, stage, tiers).size)
        assertEquals(entries.size - 1, cutWords(VocabCut.NotMemorized, entries, stage, tiers).size)
        assertEquals(listOf(entries[1]), cutWords(VocabCut.Bookmarked, entries, stage, tiers))
        assertEquals(VocabCut.All, VocabCut.of("bogus"))
    }

    @Test
    fun rateLabelsDropWholeDecimals() {
        assertEquals("1×", rateLabel(1.0))
        assertEquals("0.8×", rateLabel(0.8))
        assertEquals("1.5×", rateLabel(1.5))
    }
}
