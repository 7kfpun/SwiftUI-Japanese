package com.kfpun.japanesedaily

import com.kfpun.japanesedaily.ui.components.SwipeMath
import com.kfpun.japanesedaily.ui.components.Verdict
import com.kfpun.japanesedaily.ui.components.verdictOf
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SwipeAndOptionsTest {
    @Test
    fun pagerIgnoresDragsUnderTheThresholdAndPagesForwardOnALeftSwipe() {
        assertEquals(0, SwipeMath.pageDirection(79f))
        assertEquals(0, SwipeMath.pageDirection(-80f))
        assertEquals(1, SwipeMath.pageDirection(-81f))
        assertEquals(-1, SwipeMath.pageDirection(81f))
    }

    @Test
    fun forwardFlingsLeftAndBackFlingsRight() {
        assertEquals(-500f, SwipeMath.exitOffset(1), 0f)
        assertEquals(500f, SwipeMath.exitOffset(-1), 0f)
    }

    @Test
    fun swipeToDecideNeedsMoreThanTheThreshold() {
        assertNull(SwipeMath.decision(100f))
        assertNull(SwipeMath.decision(-100f))
        assertEquals(true, SwipeMath.decision(101f))
        assertEquals(false, SwipeMath.decision(-101f))
        assertEquals(true, SwipeMath.decision(91f, threshold = 90f))
    }

    @Test
    fun stampFadesInToFullStrengthAtTheThresholdOnItsOwnSideOnly() {
        assertEquals(0.5f, SwipeMath.stampAlpha(50f, 100f, active = true), 0.0001f)
        assertEquals(1f, SwipeMath.stampAlpha(250f, 100f, active = true), 0f)
        assertEquals(0f, SwipeMath.stampAlpha(50f, 100f, active = false), 0f)
        assertEquals(0f, SwipeMath.stampAlpha(50f, 100f, active = true, show = false), 0f)
    }

    @Test
    fun anOpenQuestionHasNoVerdictAndAnAnsweredOneMarksOnlyTheTwoThatMatter() {
        assertEquals(Verdict.Open, verdictOf(2, null, isAnswer = false))
        assertEquals(Verdict.Correct, verdictOf(0, 1, isAnswer = true))
        assertEquals(Verdict.Wrong, verdictOf(1, 1, isAnswer = false))
        assertEquals(Verdict.Dimmed, verdictOf(2, 1, isAnswer = false))
        assertEquals(Verdict.Correct, verdictOf(1, 1, isAnswer = true))
    }
}
