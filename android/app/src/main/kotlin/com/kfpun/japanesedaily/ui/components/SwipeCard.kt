package com.kfpun.japanesedaily.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.ui.Theme

private const val STAMP_TILT = 8f
private const val STAMP_PADDING_DP = 16

/**
 * The card face every swipeable screen draws: surface, hairline, shadow, the swipe hint, the corner
 * stamps, and the tilt-and-slide that follows a drag. Callers own the *meaning* of a swipe (Practice
 * and the kana quiz pick an answer, Today just turns the page and passes no stamps).
 *
 * The peek stack ([CardStackPeek]) stays outside on purpose: it must not move with the card, and
 * paging screens move the card through [cardPager] rather than the [drag] lambda.
 *
 * @param drag live drag in px, a lambda so only the draw phase re-reads it. Leave at zero when
 * something else is moving the card.
 * @param hint the localised "Swipe"; null hides the hint (a single-card deck has nowhere to go).
 */
@Composable
fun SwipeCard(
    modifier: Modifier = Modifier,
    drag: () -> Offset = { Offset.Zero },
    thresholdDp: Float = SwipeMath.DECIDE_THRESHOLD,
    leftStamp: StampSpec? = null,
    rightStamp: StampSpec? = null,
    showsStamps: Boolean = true,
    hint: String? = null,
    content: @Composable () -> Unit
) {
    Box(
        modifier
            .graphicsLayer {
                val d = drag()
                translationX = d.x
                translationY = d.y / 10f
                rotationZ = d.x / density / SwipeMath.SWIPE_DEGREES_PER_DP
            }
            .cardChrome(Theme.Radius.deck, lifted = true)
    ) {
        Box(Modifier.align(Alignment.Center)) { content() }
        StampLayer(rightStamp, STAMP_TILT, Alignment.TopEnd, drag, thresholdDp, showsStamps) { it > 0 }
        StampLayer(leftStamp, -STAMP_TILT, Alignment.TopStart, drag, thresholdDp, showsStamps) { it < 0 }
        if (hint != null) SwipeHint(hint, Modifier.align(Alignment.BottomCenter))
    }
}

@Composable
private fun BoxScope.StampLayer(
    spec: StampSpec?,
    rotation: Float,
    alignment: Alignment,
    drag: () -> Offset,
    thresholdDp: Float,
    show: Boolean,
    active: (Float) -> Boolean
) {
    if (spec == null) return
    SwipeStamp(
        spec,
        rotation,
        Modifier
            .align(alignment)
            .padding(STAMP_PADDING_DP.dp)
            .graphicsLayer {
                val x = drag().x
                alpha = SwipeMath.stampAlpha(x / density, thresholdDp, active(x), show)
            }
    )
}

/**
 * Faded, rotated cards peeking out behind a swipeable top card, so it reads as a deck. Purely
 * decorative: it never moves, only the top card does. Rotation alone reveals the corners; no
 * vertical offset, so it stays fully behind the card.
 */
@Composable
fun CardStackPeek(count: Int = 2, modifier: Modifier = Modifier) {
    Box(modifier) {
        if (count > 1) PeekLayer(-PEEK_FAR_DEGREES, PEEK_FAR_ALPHA)
        if (count > 0) PeekLayer(PEEK_NEAR_DEGREES, PEEK_NEAR_ALPHA)
    }
}

private const val PEEK_FAR_DEGREES = 6f
private const val PEEK_FAR_ALPHA = 0.5f
private const val PEEK_NEAR_DEGREES = 3.5f
private const val PEEK_NEAR_ALPHA = 0.75f

@Composable
private fun BoxScope.PeekLayer(rotation: Float, alpha: Float) {
    Box(
        Modifier
            .matchParentSize()
            .graphicsLayer {
                rotationZ = rotation
                this.alpha = alpha
            }
            .cardChrome(Theme.Radius.deck)
    )
}
