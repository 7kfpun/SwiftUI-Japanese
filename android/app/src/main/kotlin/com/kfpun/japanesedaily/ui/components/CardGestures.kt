package com.kfpun.japanesedaily.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Pure rules of the two swipe gestures, split out so they are unit-tested (iOS `CardPager`, `CardSwipe`). */
object SwipeMath {
    /** CardPager commit distance, dp. */
    const val PAGER_THRESHOLD = 80f

    /** CardPager exit distance, dp: a forward page flings left, like a page turn. */
    const val PAGER_EXIT = 500f

    /** Degrees of tilt per dp of drag. */
    const val PAGER_DEGREES_PER_DP = 30f
    const val SWIPE_DEGREES_PER_DP = 22f

    /** Swipe-to-decide commit distances, dp: the kana swipe quiz uses 90, Flashcards and Practice 100. */
    const val DECIDE_THRESHOLD = 100f
    const val DECIDE_EXIT = 700f
    const val DECIDE_EXIT_MILLIS = 250

    /** +1 forward (swipe left), -1 back (swipe right), 0 when the drag did not pass the threshold. */
    fun pageDirection(dragX: Float, threshold: Float = PAGER_THRESHOLD): Int = when {
        abs(dragX) <= threshold -> 0
        dragX < 0 -> 1
        else -> -1
    }

    /** Where a page in [direction] flings to. */
    fun exitOffset(direction: Int): Float = if (direction > 0) -PAGER_EXIT else PAGER_EXIT

    /** Right, left or null (spring back) for a swipe-to-decide drag. */
    fun decision(dragX: Float, threshold: Float = DECIDE_THRESHOLD): Boolean? = when {
        dragX > threshold -> true
        dragX < -threshold -> false
        else -> null
    }

    /** A stamp fades in with the drag so it reaches full strength exactly where the swipe commits. */
    fun stampAlpha(dragX: Float, threshold: Float, active: Boolean, show: Boolean = true): Float =
        if (show && active) minOf(abs(dragX) / threshold, 1f) else 0f
}

/**
 * State of a [cardPager] card. Created with the screen's callbacks so [fling] can page
 * programmatically (a shuffle button) with the same animation. `page` receives +1 (forward) or -1.
 */
@Stable
class CardPagerState internal constructor(
    private val scope: CoroutineScope,
    private val density: Float,
    private val canPage: () -> Boolean,
    private val page: (Int) -> Unit
) {
    internal val drag = Animatable(0f)
    private var animating = false

    /** Horizontal offset in px, for tests and the catalog. */
    val offset: Float get() = drag.value

    /** Page programmatically. Ignored mid-animation. */
    fun fling(direction: Int) {
        scope.launch { commit(direction) }
    }

    internal fun dragBy(amount: Float) {
        if (!animating) scope.launch { drag.snapTo(drag.value + amount) }
    }

    internal fun release() {
        scope.launch {
            val direction = SwipeMath.pageDirection(drag.value / density)
            if (direction == 0) springBack() else commit(direction)
        }
    }

    private suspend fun springBack() {
        drag.animateTo(0f, spring(stiffness = Spring.StiffnessMediumLow))
    }

    private suspend fun commit(direction: Int) {
        if (animating) return
        if (!canPage()) {
            springBack()
            return
        }
        animating = true
        val out = SwipeMath.exitOffset(direction) * density
        drag.animateTo(out, tween(PAGE_OUT_MILLIS, easing = FastOutLinearInEasing))
        page(direction)
        drag.snapTo(-out) // the new card enters from the opposite side
        drag.animateTo(0f, spring(stiffness = Spring.StiffnessMediumLow))
        animating = false
    }

    private companion object {
        const val PAGE_OUT_MILLIS = 180
    }
}

@Composable
fun rememberCardPagerState(canPage: () -> Boolean = { true }, page: (Int) -> Unit): CardPagerState {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current.density
    val latestCanPage by rememberUpdatedState(canPage)
    val latestPage by rememberUpdatedState(page)
    return remember(scope, density) { CardPagerState(scope, density, { latestCanPage() }, { latestPage(it) }) }
}

/**
 * Card paging: drag with a slight rotation, fling off-screen, the next card re-enters from the
 * opposite side. **Apply it to the card itself, never to the enclosing container**: outside the
 * card, the peek layers fling along with it and the deck slides as one slab. [draggable] false
 * keeps the fling animation but pages by button only (the intro tour).
 */
fun Modifier.cardPager(state: CardPagerState, draggable: Boolean = true): Modifier = this
    .graphicsLayer {
        translationX = state.drag.value
        rotationZ = state.drag.value / density / SwipeMath.PAGER_DEGREES_PER_DP
    }
    .pointerInput(state, draggable) {
        if (draggable) {
            detectHorizontalDragGestures(
                onDragEnd = state::release,
                onDragCancel = state::release,
                onHorizontalDrag = { _, amount -> state.dragBy(amount) }
            )
        }
    }

/**
 * State of a swipe-to-decide card (Flashcards, Practice, the kana swipe quiz): a live 2D drag the
 * caller reads to draw stamps, and a [fling] that exits the card and then runs a continuation.
 */
@Stable
class CardSwipeState internal constructor(private val scope: CoroutineScope, private val density: Float) {
    internal val drag = Animatable(Offset.Zero, Offset.VectorConverter)

    /** Live drag translation in px; read it inside a lambda so only drawing re-runs. */
    val offset: Offset get() = drag.value

    internal fun dragBy(amount: Offset) {
        scope.launch { drag.snapTo(drag.value + amount) }
    }

    internal fun springBack() {
        scope.launch { drag.animateTo(Offset.Zero, spring(stiffness = Spring.StiffnessMediumLow)) }
    }

    /**
     * Fling the card off-screen and run [then] once it has left. The exit is always 0.25 s; [delayMillis]
     * is how long the caller waits (the kana quiz stretches it so its verdict badge can read).
     */
    fun fling(toRight: Boolean, delayMillis: Int = SwipeMath.DECIDE_EXIT_MILLIS, then: () -> Unit) {
        scope.launch {
            val target =
                Offset((if (toRight) SwipeMath.DECIDE_EXIT else -SwipeMath.DECIDE_EXIT) * density, drag.value.y)
            launch { drag.animateTo(target, tween(SwipeMath.DECIDE_EXIT_MILLIS)) }
            delay(delayMillis.toLong())
            then()
        }
    }

    /** Put the card back at rest without animating, for the next card. */
    fun reset() {
        scope.launch { drag.snapTo(Offset.Zero) }
    }
}

@Composable
fun rememberCardSwipeState(): CardSwipeState {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current.density
    return remember(scope, density) { CardSwipeState(scope, density) }
}

/**
 * The drag half of swipe-to-decide. [decide] gets true for right, false for left once the drag passes
 * [thresholdDp]; otherwise the card springs back. [canDrag] gates the drag itself and [canCommit] the
 * release (an answered card refuses both and springs back).
 */
fun Modifier.cardSwipe(
    state: CardSwipeState,
    thresholdDp: Float = SwipeMath.DECIDE_THRESHOLD,
    canDrag: () -> Boolean = { true },
    canCommit: () -> Boolean = { true },
    decide: (right: Boolean) -> Unit
): Modifier = pointerInput(state, thresholdDp) {
    detectDragGestures(
        onDragEnd = {
            if (!canCommit()) {
                state.springBack()
            } else {
                val right = SwipeMath.decision(state.offset.x / density, thresholdDp)
                if (right == null) state.springBack() else decide(right)
            }
        },
        onDragCancel = state::springBack,
        onDrag = { change, amount ->
            if (canDrag()) {
                change.consume()
                state.dragBy(amount)
            }
        }
    )
}
