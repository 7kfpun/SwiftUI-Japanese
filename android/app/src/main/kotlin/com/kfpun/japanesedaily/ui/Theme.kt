package com.kfpun.japanesedaily.ui

import android.content.Context
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Colours, type and shape for the whole app, the Android side of nihongo/Theme.swift and
 * context/07-ux-ui.md. **The only place fonts and colours come from**: call sites read `Theme`
 * (or `MaterialTheme`, which [JapaneseDailyTheme] fills from it) and never name a literal
 * colour or font.
 *
 * Near-monochrome plus one teal accent (Minna: Shared/Course.swift). Green and red are
 * exclusive to answer feedback; selection is an accent *border*, never a fill. Cards sit
 * lighter than the screen in both appearances.
 */
@Immutable
class ThemeColors(
    /** The course's accent: teal for Minna, brightened in dark so it keeps its pop. */
    val accent: Color,
    /** Right-answer border. Answer feedback only. */
    val correct: Color,
    /** Wrong-pick border. Answer feedback only. */
    val wrong: Color,
    /** Card and tile fill. Lighter than [canvas] in both appearances. */
    val surface: Color,
    /** The screen behind the cards, and inset panes on a card. */
    val canvas: Color,
    /** Card and tile hairline. */
    val line: Color,
    /** Card drop shadow; clear in dark, where the lighter surface and [line] do the lifting. */
    val shadow: Color,
    /** Amber for streaks and the earn-path: never green or red. */
    val streak: Color,
    /** Earned stars. */
    val star: Color,
    /** Ink on an [accent] fill. One near-black holds contrast in both appearances. */
    val onAccent: Color,
    /** Primary, secondary and tertiary label colours (iOS `.primary`/`.secondary`/`.tertiary`). */
    val ink: Color,
    val inkSecondary: Color,
    val inkTertiary: Color,
    val isDark: Boolean
) {
    /** Wash behind tinted callouts: one opacity so plates do not drift between 8% and 12%. */
    fun wash(color: Color): Color = color.copy(alpha = WASH_ALPHA)

    companion object {
        const val WASH_ALPHA = 0.10f
    }
}

// The accent pair is Minna's (Shared/Course.swift accentLight/accentDark); JLPT's orange follows
// with its flavour.
internal val LightThemeColors = ThemeColors(
    accent = Color(0xFF0FB0BF),
    correct = Color(0xFF2ECC40),
    wrong = Color(0xFFFF4036),
    surface = Color(0xFFFFFFFF),
    canvas = Color(0xFFF2F2F7),
    line = Color(0x4A3C3C43),
    shadow = Color(0x1A000000),
    streak = Color(0xFFFA8C1A),
    star = Color(0xFFEBAD1A),
    onAccent = Color(0xFF0F2126),
    ink = Color(0xFF000000),
    inkSecondary = Color(0x993C3C43),
    inkTertiary = Color(0x4D3C3C43),
    isDark = false
)

// Cards lighter than the screen: an elevated grey card on a black screen, so the two roles swap
// relative to the platform pair.
internal val DarkThemeColors = ThemeColors(
    accent = Color(0xFF40C7D6),
    correct = Color(0xFF4DC766),
    wrong = Color(0xFFFF7369),
    surface = Color(0xFF1C1C1E),
    canvas = Color(0xFF000000),
    line = Color(0x38FFFFFF),
    shadow = Color(0x00000000),
    streak = Color(0xFFFFB861),
    star = Color(0xFFFAD166),
    onAccent = Color(0xFF0F2126),
    ink = Color(0xFFFFFFFF),
    inkSecondary = Color(0x99EBEBF5),
    inkTertiary = Color(0x4DEBEBF5),
    isDark = true
)

/** The three Japanese faces. Loaded once per composition root, see [rememberFaces]. */
@Immutable
class Faces(val jp: FontFamily, val jpBold: FontFamily, val jpStrokes: FontFamily) {
    companion object {
        /** Used in previews and when an asset cannot be read: serif, so it is still a mincho-ish face. */
        val Fallback = Faces(FontFamily.Serif, FontFamily.Serif, FontFamily.Default)
    }
}

/** Noto Serif JP (OFL, assets/licenses) is a variable font: one file, weights 200-900. */
internal const val NOTO_SERIF_JP_ASSET = "fonts/NotoSerifJP-VF.ttf"

/**
 * KanjiStrokeOrders is read in place from nihongo/Fonts (a Gradle assets input, app/build.gradle.kts),
 * not copied: it is the same file iOS bundles, and the handwriting scoring template.
 */
internal const val STROKES_ASSET = "KanjiStrokeOrders_v4.005.ttf"

/** Hiragino W3 and W6 stand-ins. The design follows Noto Serif JP, which Android lacks natively. */
internal val JpRegularWeight = FontWeight.Normal
internal val JpBoldWeight = FontWeight.Bold

internal fun loadFaces(context: Context): Faces = runCatching {
    val assets = context.assets
    fun noto(weight: FontWeight) = Font(
        path = NOTO_SERIF_JP_ASSET,
        assetManager = assets,
        weight = weight,
        variationSettings = FontVariation.Settings(FontVariation.weight(weight.weight))
    )
    Faces(
        jp = FontFamily(noto(JpRegularWeight)),
        jpBold = FontFamily(noto(JpBoldWeight)),
        jpStrokes = FontFamily(Font(path = STROKES_ASSET, assetManager = assets))
    )
}.getOrDefault(Faces.Fallback)

@Composable
fun rememberFaces(): Faces {
    val context = LocalContext.current
    return remember(context) { loadFaces(context) }
}

/**
 * The type scale in `sp`, so every size follows the user's font scale (iOS Dynamic Type). The
 * base sizes are the iOS text styles at the default text size.
 */
object TypeScale {
    const val LARGE_TITLE = 34
    const val TITLE = 28
    const val TITLE2 = 22
    const val TITLE3 = 20
    const val HEADLINE = 17
    const val BODY = 17
    const val CALLOUT = 16
    const val SUBHEADLINE = 15
    const val FOOTNOTE = 13
    const val CAPTION = 12
    const val CAPTION2 = 11
}

/** iOS text-style stand-ins. System sans: it falls back per script for the nine non-Latin languages. */
@Immutable
class ThemeText(
    val largeTitle: TextStyle,
    val title: TextStyle,
    val title2: TextStyle,
    val title3: TextStyle,
    val headline: TextStyle,
    val body: TextStyle,
    val callout: TextStyle,
    val subheadline: TextStyle,
    val footnote: TextStyle,
    val caption: TextStyle,
    val caption2: TextStyle
)

private fun style(size: Int, weight: FontWeight = FontWeight.Normal) =
    TextStyle(fontSize = size.sp, lineHeight = (size * LINE_HEIGHT_RATIO).sp, fontWeight = weight)

// 1.3 clears Thai and Devanagari stacks; Burmese is taller still but never clips (07-ux-ui.md).
private const val LINE_HEIGHT_RATIO = 1.3f

internal val BaseText = ThemeText(
    largeTitle = style(TypeScale.LARGE_TITLE),
    title = style(TypeScale.TITLE),
    title2 = style(TypeScale.TITLE2),
    title3 = style(TypeScale.TITLE3),
    headline = style(TypeScale.HEADLINE, FontWeight.SemiBold),
    body = style(TypeScale.BODY),
    callout = style(TypeScale.CALLOUT),
    subheadline = style(TypeScale.SUBHEADLINE),
    footnote = style(TypeScale.FOOTNOTE),
    caption = style(TypeScale.CAPTION),
    caption2 = style(TypeScale.CAPTION2)
)

private val LocalColors = staticCompositionLocalOf { LightThemeColors }
private val LocalFaces = staticCompositionLocalOf { Faces.Fallback }

object Theme {
    val colors: ThemeColors
        @Composable @ReadOnlyComposable
        get() = LocalColors.current

    val faces: Faces
        @Composable @ReadOnlyComposable
        get() = LocalFaces.current

    val text: ThemeText get() = BaseText

    /** Corner radii: one scale, so a chip, a panel and the deck do not each invent a number. */
    object Radius {
        val tick = 4.dp
        val inset = 10.dp
        val chip = 12.dp
        val row = 14.dp
        val card = 16.dp
        val pill = 18.dp
        val deck = 20.dp
        val hero = 22.dp
    }

    /** How far a card lifts. Dark ignores it: `shadow` is clear there. */
    object Elevation {
        val rest = 8.dp
        val deck = 16.dp
    }

    fun rounded(radius: Dp): Shape = RoundedCornerShape(radius)

    /** Japanese display face for glyph and word slots (Hiragino Mincho W3 on iOS). Scales with font scale. */
    @Composable
    fun jp(size: TextUnit): TextStyle = TextStyle(fontFamily = faces.jp, fontSize = size, fontWeight = JpRegularWeight)

    /** [jp] at a text style's size, for Japanese sitting in running text. */
    @Composable
    fun jp(base: TextStyle): TextStyle = jp(base.fontSize).copy(lineHeight = base.lineHeight)

    /** Bold Japanese (Hiragino W6 on iOS): kana glyphs in the Kana modes. */
    @Composable
    fun jpBold(size: TextUnit): TextStyle =
        TextStyle(fontFamily = faces.jpBold, fontSize = size, fontWeight = JpBoldWeight)

    /**
     * Stroke-order face. Functional, not decorative: the Kana Write scoring template is this
     * file, so never swap it. Never used for romaji: Latin letters have no stroke order.
     */
    @Composable
    fun jpStrokes(size: TextUnit): TextStyle = TextStyle(fontFamily = faces.jpStrokes, fontSize = size)

    /** Headings: semibold system sans on a [ThemeText] style. iOS uses SF Rounded; Android has no stock one. */
    fun title(base: TextStyle, weight: FontWeight = FontWeight.SemiBold): TextStyle = base.copy(fontWeight = weight)

    /**
     * The title face at a size that does **not** follow the font scale, the Latin half of a
     * script-switchable slot (it must be the same size as the Japanese face it alternates with)
     * and the few layouts with no slack. Compensates the font scale, so it renders [size] dp-ish.
     */
    @Composable
    fun display(size: Int, weight: FontWeight = FontWeight.Bold): TextStyle {
        val scale = LocalDensity.current.fontScale
        val px = (size / scale).sp
        return TextStyle(fontSize = px, lineHeight = (px.value * LINE_HEIGHT_RATIO).sp, fontWeight = weight)
    }
}

@Composable
fun JapaneseDailyTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (darkTheme) DarkThemeColors else LightThemeColors
    val faces = rememberFaces()
    val scheme = if (darkTheme) {
        darkColorScheme(
            primary = colors.accent,
            onPrimary = colors.onAccent,
            background = colors.canvas,
            onBackground = colors.ink,
            surface = colors.surface,
            onSurface = colors.ink,
            onSurfaceVariant = colors.inkSecondary,
            surfaceContainer = colors.surface,
            outline = colors.line,
            outlineVariant = colors.line,
            error = colors.wrong
        )
    } else {
        lightColorScheme(
            primary = colors.accent,
            onPrimary = colors.onAccent,
            background = colors.canvas,
            onBackground = colors.ink,
            surface = colors.surface,
            onSurface = colors.ink,
            onSurfaceVariant = colors.inkSecondary,
            surfaceContainer = colors.surface,
            outline = colors.line,
            outlineVariant = colors.line,
            error = colors.wrong
        )
    }
    val text = BaseText
    val typography = Typography(
        displayLarge = text.largeTitle,
        displayMedium = text.largeTitle,
        displaySmall = text.title,
        headlineLarge = text.title,
        headlineMedium = Theme.title(text.title2),
        headlineSmall = Theme.title(text.title3),
        titleLarge = Theme.title(text.title2),
        titleMedium = text.headline,
        titleSmall = text.subheadline.copy(fontWeight = FontWeight.SemiBold),
        bodyLarge = text.body,
        bodyMedium = text.callout,
        bodySmall = text.footnote,
        labelLarge = text.subheadline.copy(fontWeight = FontWeight.Medium),
        labelMedium = text.caption,
        labelSmall = text.caption2
    )
    CompositionLocalProvider(LocalColors provides colors, LocalFaces provides faces) {
        MaterialTheme(colorScheme = scheme, typography = typography, content = content)
    }
}
