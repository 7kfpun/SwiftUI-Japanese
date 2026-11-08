package com.kfpun.japanesedaily

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import com.kfpun.japanesedaily.ui.DarkThemeColors
import com.kfpun.japanesedaily.ui.JapaneseFace
import com.kfpun.japanesedaily.ui.KanaForm
import com.kfpun.japanesedaily.ui.LightThemeColors
import com.kfpun.japanesedaily.ui.ResolvedFace
import com.kfpun.japanesedaily.ui.ThemeColors
import com.kfpun.japanesedaily.ui.TypeScale
import com.kfpun.japanesedaily.ui.VocabForm
import com.kfpun.japanesedaily.ui.resolveFace
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ThemeTest {
    private val both = listOf(LightThemeColors, DarkThemeColors)

    @Test
    fun cardsSitLighterThanTheScreenInBothAppearances() {
        both.forEach { assertTrue(it.surface.luminance() > it.canvas.luminance()) }
    }

    @Test
    fun feedbackColoursAreNotUsedForAnythingElse() {
        both.forEach { c ->
            val others = listOf(c.accent, c.streak, c.star, c.surface, c.canvas, c.line, c.onAccent)
            others.forEach {
                assertNotEquals(c.correct, it)
                assertNotEquals(c.wrong, it)
            }
        }
    }

    @Test
    fun darkShadowIsClearAndLightShadowIsNot() {
        assertEquals(0f, DarkThemeColors.shadow.alpha, 0f)
        assertTrue(LightThemeColors.shadow.alpha > 0f)
    }

    @Test
    fun inkOnAccentHoldsContrastInBothAppearances() {
        both.forEach { assertTrue(contrast(it.accent, it.onAccent) >= 4.5f) }
    }

    @Test
    fun washIsOneOpacity() {
        assertEquals(0.10f, LightThemeColors.wash(Color.Red).alpha, 0.005f)
        assertEquals(ThemeColors.WASH_ALPHA, DarkThemeColors.wash(Color.Blue).alpha, 0.005f)
    }

    @Test
    fun typeScaleMatchesTheIosTextStylesAtDefaultSize() {
        val sizes = listOf(
            TypeScale.LARGE_TITLE, TypeScale.TITLE, TypeScale.TITLE2, TypeScale.TITLE3, TypeScale.HEADLINE,
            TypeScale.BODY, TypeScale.CALLOUT, TypeScale.SUBHEADLINE, TypeScale.FOOTNOTE, TypeScale.CAPTION,
            TypeScale.CAPTION2
        )
        assertEquals(listOf(34, 28, 22, 20, 17, 17, 16, 15, 13, 12, 11), sizes)
    }

    @Test
    fun theFaceFollowsTheContentsScript() {
        assertTrue(KanaForm.Hiragana.isJapanese)
        assertTrue(KanaForm.Katakana.isJapanese)
        assertTrue(!KanaForm.Romaji.isJapanese)
        assertTrue(VocabForm.Kana.isJapanese && VocabForm.Kanji.isJapanese)
        assertTrue(!VocabForm.Romaji.isJapanese && !VocabForm.Translation.isJapanese)
    }

    @Test
    fun latinContentNeverTakesAJapaneseFaceNorTheStrokeFont() {
        JapaneseFace.entries.forEach { assertEquals(ResolvedFace.Display, resolveFace(false, it)) }
        assertEquals(ResolvedFace.JpStrokes, resolveFace(true, JapaneseFace.Strokes))
        assertEquals(ResolvedFace.JpBold, resolveFace(true, JapaneseFace.Bold))
        assertEquals(ResolvedFace.Jp, resolveFace(true, JapaneseFace.Regular))
    }

    private fun contrast(a: Color, b: Color): Float {
        val hi = maxOf(a.luminance(), b.luminance())
        val lo = minOf(a.luminance(), b.luminance())
        return (hi + 0.05f) / (lo + 0.05f)
    }
}
