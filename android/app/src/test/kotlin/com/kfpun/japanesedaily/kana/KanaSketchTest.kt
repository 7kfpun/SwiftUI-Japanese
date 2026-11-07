package com.kfpun.japanesedaily.kana

import java.io.File
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Write scoring against the iOS output. `sketch-fixtures.json` is dumped from the real `KanaSketch.swift`
 * (CoreGraphics) by `scripts/dump-kana-sketch-fixtures.py`, KanjiStrokeOrders template only.
 *
 * What must match **exactly**: everything after rasterisation, since it is the same arithmetic on the same
 * grids: the digit stripping and its erased count, the normalised glyph grid from the iOS raw raster, the
 * distance transform / chamfer / zone terms (to 1e-9) and the score and stroke penalty derived from them.
 *
 * What is **toleranced**: rasterising the user's strokes. CoreGraphics anti-aliases and Android's capsule
 * test lights a cell when its centre is within half the stroke width, so cells on the edge of a stroke can
 * differ. The test bounds that at [MAX_GRID_MISMATCH] of the cells and the end-to-end score at
 * [MAX_SCORE_DELTA] points (the chamfer term moves by at most a cell's width per edge cell).
 */
@OptIn(ExperimentalSerializationApi::class)
class KanaSketchTest {
    @Serializable
    private class GlyphFixture(val glyph: String, val raw: String, val erased: Int, val grid: String)

    @Serializable
    private class Comparison(
        val glyph: String,
        val distance: Double,
        val zoneDiff: Double,
        val score: Int,
        val scoreNoPenalty: Int
    )

    @Serializable
    private class SetFixture(
        val id: String,
        val target: String,
        val expectedStrokes: Int,
        val strokes: List<List<List<Double>>>,
        val grid: String,
        val comparisons: List<Comparison>
    )

    @Serializable
    private class Fixtures(val glyphs: List<GlyphFixture>, val sets: List<SetFixture>)

    private val fixtures: Fixtures = File("src/test/resources/kana/sketch-fixtures.json").inputStream().use {
        JSON.decodeFromStream(it)
    }

    private fun bits(s: String) = BooleanArray(s.length) { s[it] == '1' }

    private val glyphGrids = fixtures.glyphs.associate { it.glyph to bits(it.grid) }

    private fun SetFixture.points() = strokes.map { s -> s.map { SketchPoint(it[0], it[1]) } }

    @Test
    fun fixturesCoverTheContract() {
        assertTrue(fixtures.glyphs.size >= 10)
        assertTrue(fixtures.sets.size >= 8)
        assertTrue(fixtures.sets.sumOf { it.comparisons.size } >= 30)
    }

    @Test
    fun digitStrippingAndGlyphGridMatchIosExactly() {
        for (g in fixtures.glyphs) {
            val raw = bits(g.raw)
            assertEquals(KanaSketch.BIG * KanaSketch.BIG, raw.size)
            val copy = raw.copyOf()
            assertEquals("erased digits for ${g.glyph}", g.erased, KanaSketch.stripTinyComponents(copy, KanaSketch.BIG))
            val grid = checkNotNull(KanaSketch.glyphGrid(raw, isStrokeOrderFont = true))
            assertArrayEquals("grid for ${g.glyph}", bits(g.grid), grid)
        }
    }

    @Test
    fun distanceTermsAndScoresMatchIosExactly() {
        for (s in fixtures.sets) {
            val user = bits(s.grid)
            for (c in s.comparisons) {
                val template = glyphGrids.getValue(c.glyph)
                val label = "${s.id} vs ${c.glyph}"
                assertEquals(label, c.distance, KanaSketch.distance(user, template), EXACT)
                assertEquals(
                    label,
                    c.zoneDiff,
                    KanaSketch.zoneDiff(KanaSketch.zones(user), KanaSketch.zones(template)),
                    EXACT
                )
                assertEquals(label, c.scoreNoPenalty, KanaSketch.score(c.distance, s.strokes.size, null))
                assertEquals(label, c.score, KanaSketch.score(c.distance, s.strokes.size, s.expectedStrokes))
            }
        }
    }

    @Test
    fun strokeRasterisationStaysWithinTolerance() {
        for (s in fixtures.sets) {
            val ios = bits(s.grid)
            val mine = checkNotNull(KanaSketch.strokeGrid(s.points()))
            val mismatched = ios.indices.count { ios[it] != mine[it] }
            val limit = (ios.size * MAX_GRID_MISMATCH).toInt()
            assertTrue("${s.id}: $mismatched of ${ios.size} cells differ (limit $limit)", mismatched <= limit)
        }
    }

    @Test
    fun endToEndScoreStaysWithinTolerance() {
        var worst = 0
        for (s in fixtures.sets) {
            val mine = checkNotNull(KanaSketch.strokeGrid(s.points()))
            for (c in s.comparisons) {
                val d = KanaSketch.distance(mine, glyphGrids.getValue(c.glyph))
                val score = KanaSketch.score(d, s.strokes.size, s.expectedStrokes)
                val delta = kotlin.math.abs(score - c.score)
                worst = maxOf(worst, delta)
                assertTrue("${s.id} vs ${c.glyph}: android $score, ios ${c.score}", delta <= MAX_SCORE_DELTA)
            }
        }
        println("worst end-to-end score delta: $worst")
    }

    @Test
    fun theVerdictAgreesWithIosOnTheClearCases() {
        // Far from the pass mark, the pass/fail verdict must be identical, tolerance or not.
        for (s in fixtures.sets) {
            val mine = checkNotNull(KanaSketch.strokeGrid(s.points()))
            for (c in s.comparisons) {
                if (kotlin.math.abs(c.score - KanaSketch.PASS_SCORE) <= MAX_SCORE_DELTA) continue
                val score = KanaSketch.score(
                    KanaSketch.distance(mine, glyphGrids.getValue(c.glyph)),
                    s.strokes.size,
                    s.expectedStrokes
                )
                assertEquals(c.score >= KanaSketch.PASS_SCORE, score >= KanaSketch.PASS_SCORE)
            }
        }
    }

    @Test
    fun identicalGridsHaveZeroDistance() {
        for ((glyph, grid) in glyphGrids) assertEquals(glyph, 0.0, KanaSketch.distance(grid, grid), 0.0)
    }

    @Test
    fun distinctKanaAreFarApart() {
        // Port of iOS `KanaSketchTests`: a kana never matches another as well as it matches itself.
        for ((a, ga) in glyphGrids) {
            for ((b, gb) in glyphGrids) {
                if (a != b) assertTrue("$a vs $b", KanaSketch.distance(ga, gb) > 0.0)
            }
        }
    }

    @Test
    fun emptyOrSinglePointInputIsNotScored() {
        assertNull(KanaSketch.strokeGrid(emptyList()))
        assertNull(KanaSketch.strokeGrid(listOf(listOf(SketchPoint(1.0, 1.0)))))
    }

    @Test
    fun smallMarksSurviveDigitStripping() {
        // Port of iOS: a 4x5 digit is erased, an 8x6 dakuten-sized mark is not, and the count is returned.
        val size = 40
        val g = BooleanArray(size * size)
        fun block(x0: Int, y0: Int, w: Int, h: Int) {
            for (y in y0 until y0 + h) for (x in x0 until x0 + w) g[y * size + x] = true
        }
        block(2, 2, 4, 5)
        block(20, 20, 8, 6)
        assertEquals(1, KanaSketch.stripTinyComponents(g, size))
        assertTrue(g[20 * size + 20])
        assertTrue(!g[2 * size + 2])
    }

    @Test
    fun scoreCurveAndStrokePenalty() {
        assertEquals(100, KanaSketch.score(0.0, 3, 3))
        assertEquals(97, KanaSketch.score(1.0, 3, 3)) // 100 - 3.5, rounded
        assertEquals(90, KanaSketch.score(0.0, 2, 3)) // one stroke short costs 10
        assertEquals(80, KanaSketch.score(0.0, 5, 3)) // two over costs 20
        assertEquals(100, KanaSketch.score(0.0, 9, null)) // no textbook count, no penalty
        assertEquals(0, KanaSketch.score(60.0, 1, 3))
    }

    @Test
    fun matchScoreTakesTheBestTemplate() {
        val s = fixtures.sets.first { it.id == "ro-clean" }
        val ro = fixtures.glyphs.first { it.glyph == "ロ" }
        val ni = fixtures.glyphs.first { it.glyph == "に" }
        val rasterizer = object : GlyphRasterizer() {
            override val templates = listOf(TemplateFont.StrokeOrder, TemplateFont.NotoBold)
            override fun rawGlyph(glyph: String, font: TemplateFont) =
                // The non-stroke-order face is not digit-stripped by the rasteriser, so hand it a clean raster.
                if (font == TemplateFont.StrokeOrder) bits(ni.raw) else stripped(ro.raw)
        }
        // The worse template (に) is ignored: the better one (ロ) wins.
        val best = checkNotNull(KanaSketch.matchScore(s.points(), "x", rasterizer, s.expectedStrokes))
        val onlyNi = object : GlyphRasterizer() {
            override val templates = listOf(TemplateFont.StrokeOrder)
            override fun rawGlyph(glyph: String, font: TemplateFont) = bits(ni.raw)
        }
        val worse = checkNotNull(KanaSketch.matchScore(s.points(), "x", onlyNi, s.expectedStrokes))
        assertTrue(best > worse)
    }

    private fun stripped(raw: String): BooleanArray =
        bits(raw).also { KanaSketch.stripTinyComponents(it, KanaSketch.BIG) }

    private companion object {
        val JSON = Json { ignoreUnknownKeys = true }
        const val EXACT = 1e-9
        const val MAX_GRID_MISMATCH = 0.06
        const val MAX_SCORE_DELTA = 2
    }
}
