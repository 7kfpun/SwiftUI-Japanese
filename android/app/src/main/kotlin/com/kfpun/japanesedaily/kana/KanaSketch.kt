package com.kfpun.japanesedaily.kana

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** A point of a finger-drawn stroke, in any coordinate space: scoring normalises position and scale away. */
class SketchPoint(val x: Double, val y: Double)

/**
 * Scores a finger-drawn kana against its target glyph for Write practice: a stroke-for-stroke port of
 * iOS `KanaSketch` (nihongo/Kana/KanaSketch.swift), using symmetric **chamfer distance** (how far each ink
 * pixel is from the other shape's nearest ink, tolerant of wobble) plus a zone-density term (whether the
 * ink mass sits in the same regions). Shapes are normalised per axis, so position, size and proportions
 * do not matter.
 *
 * Everything here is pure Kotlin over boolean grids, so it runs on the JVM and is asserted against the
 * iOS output in `android/app/src/test/resources/kana/sketch-fixtures.json`
 * (`scripts/dump-kana-sketch-fixtures.py`). Only the glyph *rasteriser* is platform code
 * ([GlyphRasterizer]).
 */
object KanaSketch {
    /** Matching grid resolution. */
    const val N = 48

    /** Whitespace around the normalised glyph, as a fraction of [N]. */
    const val MARGIN = 0.12

    /** Raw glyph raster size (pre-normalisation). */
    const val BIG = 160

    /** Stroke width in grid cells. */
    private const val LINE_WIDTH = N * 0.09

    /** Digit-stripping threshold at [BIG]: stroke-order digits are at most 4x5, real ink at least 8x6. */
    const val DIGIT_MAX_DIM = 6

    private const val ZONES = 6

    /** The score at or above which Write passes (and the score row turns green). Same bar as the ladder. */
    const val PASS_SCORE = 80

    /** Below this the score row is orange, between this and [PASS_SCORE] it is orange too, above green. */
    const val WEAK_SCORE = 40

    /**
     * Rasterise strokes into an [N]x[N] grid, stretched per axis to fill the grid minus a margin. A stroke is
     * a polyline with round caps and joins, the union of capsules of width [LINE_WIDTH]; a cell is lit when its
     * centre lies within half a width of the line (CoreGraphics lights a cell at 50% coverage, the same cut).
     * Returns null for fewer than two points in total.
     */
    fun strokeGrid(strokes: List<List<SketchPoint>>): BooleanArray? {
        val pts = strokes.flatten()
        if (pts.size <= 1) return null
        val minX = pts.minOf { it.x }
        val maxX = pts.maxOf { it.x }
        val minY = pts.minOf { it.y }
        val maxY = pts.maxOf { it.y }
        val w = max(maxX - minX, 1.0)
        val h = max(maxY - minY, 1.0)
        val m = N * MARGIN
        val inner = N - 2 * m

        val grid = BooleanArray(N * N)
        val radius = LINE_WIDTH / 2
        for (stroke in strokes) {
            if (stroke.size <= 1) continue
            val mapped = stroke.map { p ->
                SketchPoint(m + (p.x - minX) / w * inner, m + (p.y - minY) / h * inner)
            }
            for (i in 1 until mapped.size) paintCapsule(grid, mapped[i - 1], mapped[i], radius)
        }
        return grid
    }

    private fun paintCapsule(grid: BooleanArray, a: SketchPoint, b: SketchPoint, r: Double) {
        val x0 = max(0, (min(a.x, b.x) - r).toInt() - 1)
        val x1 = min(N - 1, (max(a.x, b.x) + r).toInt() + 1)
        val y0 = max(0, (min(a.y, b.y) - r).toInt() - 1)
        val y1 = min(N - 1, (max(a.y, b.y) + r).toInt() + 1)
        val dx = b.x - a.x
        val dy = b.y - a.y
        val len2 = dx * dx + dy * dy
        for (y in y0..y1) {
            for (x in x0..x1) {
                val cx = x + 0.5
                val cy = y + 0.5
                val t = if (len2 == 0.0) 0.0 else (((cx - a.x) * dx + (cy - a.y) * dy) / len2).coerceIn(0.0, 1.0)
                val px = a.x + t * dx - cx
                val py = a.y + t * dy - cy
                if (sqrt(px * px + py * py) <= r) grid[y * N + x] = true
            }
        }
    }

    /**
     * Normalise a raw [BIG]x[BIG] glyph raster into the same per-axis-stretched grid as the strokes, or null for
     * an empty glyph. When [isStrokeOrderFont] the baked-in stroke-number digits are erased first: they are
     * annotations, not ink to match. [raw] is not modified.
     */
    fun glyphGrid(raw: BooleanArray, isStrokeOrderFont: Boolean): BooleanArray? {
        val g = raw.copyOf()
        if (isStrokeOrderFont) stripTinyComponents(g, BIG)

        var minX = BIG
        var maxX = -1
        var minY = BIG
        var maxY = -1
        for (y in 0 until BIG) {
            for (x in 0 until BIG) {
                if (g[y * BIG + x]) {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        if (maxX <= minX || maxY <= minY) return null
        val bw = (maxX - minX).toDouble()
        val bh = (maxY - minY).toDouble()
        val m = N * MARGIN
        val inner = N - 2 * m

        // Nearest-neighbour resample, stretched per axis exactly like the strokes.
        val out = BooleanArray(N * N)
        for (y in 0 until N) {
            for (x in 0 until N) {
                val u = (x - m) / inner
                val v = (y - m) / inner
                if (u < 0 || u >= 1 || v < 0 || v >= 1) continue
                val sx = minX + (u * bw).toInt()
                val sy = minY + (v * bh).toInt()
                if (g[sy * BIG + sx]) out[y * N + x] = true
            }
        }
        return out
    }

    /**
     * Erase connected components (8-connected) whose bounding box is smaller than [maxDim] in both axes,
     * returning how many were erased. 6 is measured on the stroke-order font at [BIG]: digits are at most 4x5
     * while the smallest real ink (dakuten marks, short fragments) is at least 8x6. Callers rendering at another
     * raster size pass a scaled [maxDim].
     */
    fun stripTinyComponents(g: BooleanArray, size: Int, maxDim: Int = DIGIT_MAX_DIM): Int {
        var erased = 0
        val seen = BooleanArray(g.size)
        val stack = IntArray(g.size)
        val member = IntArray(g.size)
        for (start in g.indices) {
            if (!g[start] || seen[start]) continue
            var sp = 0
            var count = 0
            stack[sp++] = start
            seen[start] = true
            var minX = size
            var maxX = 0
            var minY = size
            var maxY = 0
            while (sp > 0) {
                val i = stack[--sp]
                member[count++] = i
                val x = i % size
                val y = i / size
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                for (dy in -1..1) {
                    for (dx in -1..1) {
                        val nx = x + dx
                        val ny = y + dy
                        if (nx < 0 || nx >= size || ny < 0 || ny >= size) continue
                        val j = ny * size + nx
                        if (g[j] && !seen[j]) {
                            seen[j] = true
                            stack[sp++] = j
                        }
                    }
                }
            }
            if (maxX - minX < maxDim && maxY - minY < maxDim) {
                for (k in 0 until count) g[member[k]] = false
                erased++
            }
        }
        return erased
    }

    /** City-block distance transform: distance from each cell to the nearest ink. */
    fun distanceTransform(g: BooleanArray): DoubleArray {
        val d = DoubleArray(g.size) { if (g[it]) 0.0 else FAR }
        for (y in 0 until N) {
            for (x in 0 until N) {
                val i = y * N + x
                if (x > 0) d[i] = min(d[i], d[i - 1] + 1)
                if (y > 0) d[i] = min(d[i], d[i - N] + 1)
            }
        }
        for (y in N - 1 downTo 0) {
            for (x in N - 1 downTo 0) {
                val i = y * N + x
                if (x < N - 1) d[i] = min(d[i], d[i + 1] + 1)
                if (y < N - 1) d[i] = min(d[i], d[i + N] + 1)
            }
        }
        return d
    }

    private const val FAR = 1e9

    /** Mean distance from A's ink to B's nearest ink, plus the reverse. 0 is identical; infinite if either is empty. */
    fun chamfer(a: BooleanArray, dtA: DoubleArray, b: BooleanArray, dtB: DoubleArray): Double {
        var sumAB = 0.0
        var ca = 0
        var sumBA = 0.0
        var cb = 0
        for (i in a.indices) {
            if (a[i]) {
                sumAB += dtB[i]
                ca++
            }
            if (b[i]) {
                sumBA += dtA[i]
                cb++
            }
        }
        if (ca == 0 || cb == 0) return Double.POSITIVE_INFINITY
        return sumAB / ca + sumBA / cb
    }

    /** Fraction of total ink per 6x6 region (sums to 1). */
    fun zones(g: BooleanArray): DoubleArray {
        val counts = DoubleArray(ZONES * ZONES)
        var total = 0.0
        for (y in 0 until N) {
            for (x in 0 until N) {
                if (g[y * N + x]) {
                    counts[(y * ZONES / N) * ZONES + (x * ZONES / N)] += 1.0
                    total += 1.0
                }
            }
        }
        return if (total > 0) DoubleArray(counts.size) { counts[it] / total } else counts
    }

    /** L1 difference between two zone histograms (0 is an identical mass layout, max 2). */
    fun zoneDiff(a: DoubleArray, b: DoubleArray): Double {
        var sum = 0.0
        for (i in a.indices) sum += abs(a[i] - b[i])
        return sum
    }

    /**
     * Combined shape distance: chamfer (how far apart the ink is) plus 5x a zone-density term (whether the ink
     * mass sits in the same regions: chamfer alone under-punishes a missing stroke, e.g. に matching ロ).
     */
    fun distance(a: BooleanArray, b: BooleanArray): Double =
        chamfer(a, distanceTransform(a), b, distanceTransform(b)) + 5 * zoneDiff(zones(a), zones(b))

    /**
     * 0-100 from a shape distance: `100 - distance * 3.5`, a gentle curve (a faithful trace lands in the mid-90s,
     * a correct but wobbly freehand glyph in the 70s-80s), minus 10 per stroke of difference from
     * [expectedStrokes] (shape matching alone cannot tell a one-swipe scribble from properly ordered strokes).
     */
    fun score(distance: Double, drawnStrokes: Int, expectedStrokes: Int? = null): Int {
        var s = 100 - distance * 3.5
        if (expectedStrokes != null && expectedStrokes > 0) s -= abs(drawnStrokes - expectedStrokes) * 10.0
        // Math.round is half-up where Swift rounds half away from zero; they differ only below zero, and
        // that clamps to 0 anyway.
        return Math.round(s).toInt().coerceIn(0, 100)
    }

    /**
     * 0-100 score of how closely [strokes] match [glyph], the best (lowest-distance) comparison across the
     * [templates] winning. Null when nothing was drawn or no template has ink for the glyph.
     */
    fun matchScore(
        strokes: List<List<SketchPoint>>,
        glyph: String,
        rasterizer: GlyphRasterizer,
        expectedStrokes: Int? = null
    ): Int? {
        val user = strokeGrid(strokes) ?: return null
        var best = Double.POSITIVE_INFINITY
        for (font in rasterizer.templates) {
            val template = rasterizer.glyphGrid(glyph, font) ?: continue
            best = min(best, distance(user, template))
        }
        if (!best.isFinite()) return null
        return score(best, strokes.size, expectedStrokes)
    }
}
