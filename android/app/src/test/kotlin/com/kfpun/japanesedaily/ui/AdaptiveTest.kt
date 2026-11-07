package com.kfpun.japanesedaily.ui

import com.kfpun.japanesedaily.lessons.LessonRoute
import com.kfpun.japanesedaily.lessons.LessonsNav
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The shared large-screen numbers (FOX-166), the same on iOS: 600 regular, 640 readable, a third for the list. */
class AdaptiveTest {
    @Test
    fun regularWidthStartsAtSixHundred() {
        assertFalse(Adaptive.isRegularWidth(599))
        assertTrue(Adaptive.isRegularWidth(600))
        assertTrue(Adaptive.isRegularWidth(1280))
    }

    @Test
    fun readableWidthIsSixForty() {
        assertEquals(640, Adaptive.READABLE_MAX_WIDTH_DP)
    }

    @Test
    fun landscapePhonesAreShort() {
        assertTrue(Adaptive.isCompactHeight(411))
        assertFalse(Adaptive.isCompactHeight(480))
        assertFalse(Adaptive.isCompactHeight(800))
    }

    @Test
    fun listPaneIsAboutAThirdClampedTo280And400() {
        assertEquals(280f, Adaptive.listPaneWidthDp(600f), 0.001f)
        assertEquals(300f, Adaptive.listPaneWidthDp(900f), 0.001f)
        assertEquals(400f, Adaptive.listPaneWidthDp(1280f), 0.001f)
        assertEquals(400f, Adaptive.listPaneWidthDp(2000f), 0.001f)
    }

    @Test
    fun listPaneIsNeverHalfTheWindow() {
        for (width in 600..2400 step 50) {
            val list = Adaptive.listPaneWidthDp(width.toFloat())
            assertTrue("width $width", list < width / 2f)
            assertTrue("width $width", list in 280f..400f)
        }
    }

    @Test
    fun openingALessonReplacesTheRightPaneAndKeepsTheSelection() {
        val nav = LessonsNav()
        nav.openLesson(3)
        nav.push(LessonRoute.Practice(3))
        assertEquals(LessonRoute.Practice(3), nav.current)
        // Picking another lesson in the list swaps the right pane's whole stack, never stacks on it.
        nav.openLesson(7)
        assertEquals(listOf<LessonRoute>(LessonRoute.Select(7)), nav.stack.toList())
    }
}
