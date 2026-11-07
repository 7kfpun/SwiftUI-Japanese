package com.kfpun.japanesedaily.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * The shared large-screen rules (FOX-166), the same numbers as the iOS ticket: the width class comes from the
 * *window*, never the device, so a folded phone, a split-screen tablet and a resized freeform window all follow.
 */
object Adaptive {
    /** Regular width starts here (dp); below it the phone layout is kept exactly. */
    const val REGULAR_MIN_WIDTH_DP = 600

    /** Every tab's content and every pushed screen is capped at this width and centred. */
    const val READABLE_MAX_WIDTH_DP = 640

    /** The two-pane list column: about a third of the width, never narrower or wider than this. */
    const val LIST_PANE_MIN_DP = 280
    const val LIST_PANE_MAX_DP = 400

    /** Below this window height (a phone in landscape) screens scroll instead of squeezing a card. */
    const val COMPACT_HEIGHT_DP = 480

    /** A card never grows taller than this, so on a tablet it is a card and not a full-screen slab. */
    const val CARD_MAX_HEIGHT_DP = 560

    /** A card screen keeps at least this much height; a shorter window scrolls it instead. */
    const val SHORT_CONTENT_MIN_DP = 560

    fun isRegularWidth(widthDp: Int): Boolean = widthDp >= REGULAR_MIN_WIDTH_DP

    fun isCompactHeight(heightDp: Int): Boolean = heightDp < COMPACT_HEIGHT_DP

    /** Width of the left (list) pane for a window [totalDp] wide: one third, clamped to 280..400. Never 50/50. */
    fun listPaneWidthDp(totalDp: Float): Float =
        (totalDp / 3f).coerceIn(LIST_PANE_MIN_DP.toFloat(), LIST_PANE_MAX_DP.toFloat())
}

/** What the current window allows. Provided once by `AppScaffold`; read anywhere below it. */
data class WindowLayout(val regularWidth: Boolean = false, val compactHeight: Boolean = false)

val LocalWindowLayout = compositionLocalOf { WindowLayout() }

/** Reads the window size class (dp of the window, not the screen) and provides it to [content]. */
@Composable
fun ProvideWindowLayout(content: @Composable () -> Unit) {
    val size = currentWindowAdaptiveInfo().windowSizeClass
    val layout = WindowLayout(
        regularWidth = Adaptive.isRegularWidth(size.minWidthDp),
        compactHeight = Adaptive.isCompactHeight(size.minHeightDp)
    )
    CompositionLocalProvider(LocalWindowLayout provides layout, content = content)
}

@Composable
@ReadOnlyComposable
fun isRegularWidth(): Boolean = LocalWindowLayout.current.regularWidth

@Composable
@ReadOnlyComposable
fun isCompactHeight(): Boolean = LocalWindowLayout.current.compactHeight

/**
 * Caps [content] at the readable width and centres it. Applied once at the screen level (each tab, each pane), not
 * per call site; whatever sits behind it (the canvas) stays full-bleed.
 */
@Composable
fun ReadableWidth(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Box(Modifier.widthIn(max = Adaptive.READABLE_MAX_WIDTH_DP.dp).fillMaxWidth().fillMaxHeight()) { content() }
    }
}

/**
 * For the screens built around one weighted card (Practice, Flashcards, Match, Challenge, Today): in a short window
 * (a phone in landscape) the content keeps a floor height and the screen scrolls, so the card is never squeezed to a
 * sliver and the answer buttons below it stay reachable. In a tall window it changes nothing. The tree is the same
 * either way (only modifiers differ), so rotating or folding mid-round keeps the round's state.
 */
@Composable
fun ScrollIfShort(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val short = maxHeight < Adaptive.SHORT_CONTENT_MIN_DP.dp
        val scroll = rememberScrollState()
        Box(Modifier.fillMaxSize().then(if (short) Modifier.verticalScroll(scroll) else Modifier)) {
            Box(
                Modifier.fillMaxWidth().then(
                    if (short) Modifier.height(Adaptive.SHORT_CONTENT_MIN_DP.dp) else Modifier.fillMaxHeight()
                )
            ) { content() }
        }
    }
}
