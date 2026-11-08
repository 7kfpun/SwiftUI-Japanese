package com.kfpun.japanesedaily.kana

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import com.kfpun.japanesedaily.ui.NOTO_SERIF_JP_ASSET
import com.kfpun.japanesedaily.ui.STROKES_ASSET
import java.util.concurrent.ConcurrentHashMap

/**
 * The template faces Write scores against. iOS compares against five (KanjiStrokeOrders, YuKyokasho,
 * Klee, Tsukushi A Round Gothic, Hiragino Sans W6); the last four are Apple system fonts that Android does
 * not have, so Android keeps the one that is the actual contract, [StrokeOrder], and stands in the bundled
 * Noto Serif JP for the print letterforms. See android/CLAUDE.md, "Kana Write scoring".
 */
enum class TemplateFont { StrokeOrder, NotoBold, NotoRegular }

/** Draws a glyph to a boolean raster. The platform half of scoring: everything after it is pure ([KanaSketch]). */
abstract class GlyphRasterizer {
    open val templates: List<TemplateFont> = TemplateFont.entries

    /** The glyph at [KanaSketch.BIG] squared, pre-normalisation, or null when it cannot be drawn. */
    abstract fun rawGlyph(glyph: String, font: TemplateFont): BooleanArray?

    private val cache = ConcurrentHashMap<Pair<String, TemplateFont>, BooleanArray>()

    /** The normalised [KanaSketch.N] squared grid for a glyph, cached: rescoring after every stroke is cheap. */
    fun glyphGrid(glyph: String, font: TemplateFont): BooleanArray? {
        val key = glyph to font
        cache[key]?.let { return it }
        val raw = rawGlyph(glyph, font) ?: return null
        val grid = KanaSketch.glyphGrid(raw, font == TemplateFont.StrokeOrder) ?: return null
        cache[key] = grid
        return grid
    }
}

/**
 * Renders glyphs with `android.graphics`. Layout follows the iOS raster: a [KanaSketch.BIG] square, text origin
 * (8, 35) up from the bottom, 110 px for one character and 64 px for a combo (びゃ) so it is not clipped.
 */
class AndroidGlyphRasterizer(context: Context) : GlyphRasterizer() {
    private val faces: Map<TemplateFont, Typeface> = run {
        val assets = context.assets
        fun load(block: () -> Typeface): Typeface? = runCatching(block).getOrNull()
        val strokes = load { Typeface.createFromAsset(assets, STROKES_ASSET) }
        fun noto(weight: Int) = load {
            Typeface.Builder(assets, NOTO_SERIF_JP_ASSET).setFontVariationSettings("'wght' $weight").build()
        }
        buildMap {
            strokes?.let { put(TemplateFont.StrokeOrder, it) }
            noto(BOLD_WEIGHT)?.let { put(TemplateFont.NotoBold, it) }
            noto(REGULAR_WEIGHT)?.let { put(TemplateFont.NotoRegular, it) }
        }
    }

    /** The stroke-order face for the on-screen template, or null if the font could not be read. */
    private val strokeFace get() = faces[TemplateFont.StrokeOrder]

    override val templates: List<TemplateFont> = TemplateFont.entries.filter { it in faces }

    private fun paint(face: Typeface, size: Float) = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
        color = Color.WHITE
        typeface = face
        textSize = size
    }

    private fun lit(bitmap: Bitmap): BooleanArray {
        val w = bitmap.width
        val h = bitmap.height
        val px = IntArray(w * h)
        bitmap.getPixels(px, 0, w, 0, 0, w, h)
        // Coverage above 50%, the same cut as iOS's gray > 127.
        return BooleanArray(px.size) { (px[it] ushr ALPHA_SHIFT) > HALF }
    }

    override fun rawGlyph(glyph: String, font: TemplateFont): BooleanArray? {
        val face = faces[font] ?: return null
        val size = KanaSketch.BIG
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val size1 = if (glyph.codePointCount(0, glyph.length) > 1) COMBO_SIZE else SINGLE_SIZE
        Canvas(bitmap).drawText(glyph, ORIGIN_X, size - ORIGIN_Y, paint(face, size1))
        return lit(bitmap).also { bitmap.recycle() }
    }

    /**
     * The on-screen trace template: the stroke-order font's shape with its numbered annotations stripped, aspect
     * preserved (unlike the per-axis-stretched scoring grid) and centred with a margin. Null if the font or the
     * glyph is unavailable.
     */
    fun templateBitmap(glyph: String, pixelSize: Int): Bitmap? {
        val face = strokeFace ?: return null
        if (glyph.isEmpty() || pixelSize <= 0) return null
        val probe = Rect()
        paint(face, PROBE_SIZE).getTextBounds(glyph, 0, glyph.length, probe)
        if (probe.width() <= 0 || probe.height() <= 0) return null
        val target = pixelSize * (1 - 2 * TEMPLATE_MARGIN)
        val fit = minOf(target / probe.width(), target / probe.height())
        val p = paint(face, PROBE_SIZE * fit)
        val bounds = Rect()
        p.getTextBounds(glyph, 0, glyph.length, bounds)
        val bitmap = Bitmap.createBitmap(pixelSize, pixelSize, Bitmap.Config.ARGB_8888)
        val x = (pixelSize - bounds.width()) / 2f - bounds.left
        val y = (pixelSize - bounds.height()) / 2f - bounds.top
        Canvas(bitmap).drawText(glyph, x, y, p)
        val mask = lit(bitmap)
        // The digit threshold is calibrated on the scoring raster, where a glyph is drawn at 110 px (64 for a
        // combo). Digits scale with the font size, so scale the threshold by this render's size relative to that,
        // not by the bitmap size: the aspect-fit glyph is several times larger than the scoring one.
        val reference = if (glyph.codePointCount(0, glyph.length) > 1) COMBO_SIZE else SINGLE_SIZE
        val maxDim = maxOf(2, kotlin.math.ceil(KanaSketch.DIGIT_MAX_DIM * (PROBE_SIZE * fit) / reference).toInt())
        KanaSketch.stripTinyComponents(mask, pixelSize, maxDim)
        val out = IntArray(mask.size) { if (mask[it]) Color.WHITE else Color.TRANSPARENT }
        bitmap.setPixels(out, 0, pixelSize, 0, 0, pixelSize, pixelSize)
        return bitmap
    }

    private companion object {
        const val SINGLE_SIZE = 110f
        const val COMBO_SIZE = 64f
        const val ORIGIN_X = 8f
        const val ORIGIN_Y = 35f
        const val PROBE_SIZE = 200f
        const val TEMPLATE_MARGIN = 0.06f
        const val BOLD_WEIGHT = 700
        const val REGULAR_WEIGHT = 400
        const val ALPHA_SHIFT = 24
        const val HALF = 127
    }
}
