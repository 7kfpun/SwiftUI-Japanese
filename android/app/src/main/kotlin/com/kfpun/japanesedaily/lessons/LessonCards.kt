package com.kfpun.japanesedaily.lessons

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** How long a press must last to count as a hold: snappy, but clear of the tap that speaks the word. */
const val HOLD_MILLIS = 200L

private const val FLIP_MILLIS = 320
private const val HALF_TURN = 90f
private const val FULL_TURN = 180f
private const val CAMERA = 14f

/** The card's turn: an animated angle. Past 90 degrees the back face is the one drawn, mirrored upright. */
@Composable
fun rememberFlip(flipped: Boolean): State<Float> =
    animateFloatAsState(if (flipped) FULL_TURN else 0f, tween(FLIP_MILLIS), label = "flip")

/** Turns the whole card (chrome included) about its vertical axis. */
fun Modifier.flipped(angle: State<Float>): Modifier = graphicsLayer {
    rotationY = angle.value
    cameraDistance = CAMERA * density
}

/** Draws [front] before the half turn and [back] (counter-rotated so it reads the right way round) after. */
@Composable
fun FlipFaces(angle: State<Float>, front: @Composable () -> Unit, back: @Composable () -> Unit) {
    if (angle.value <= HALF_TURN) {
        front()
    } else {
        Box(Modifier.graphicsLayer { rotationY = FULL_TURN }) { back() }
    }
}

/**
 * Tap, optional double-tap and press-and-hold on one surface. A hold fires [onHold] after [HOLD_MILLIS] and
 * [onHoldEnd] on release; a tap that ends a hold is swallowed, so releasing a peek does not also speak.
 * Dragging cancels the hold (the swipe owns the movement).
 */
fun Modifier.holdGestures(
    onTap: () -> Unit,
    onHold: () -> Unit,
    onHoldEnd: () -> Unit,
    onDoubleTap: (() -> Unit)? = null
): Modifier = composed {
    val tap by rememberUpdatedState(onTap)
    val hold by rememberUpdatedState(onHold)
    val holdEnd by rememberUpdatedState(onHoldEnd)
    val double by rememberUpdatedState(onDoubleTap)
    pointerInput(Unit) {
        var held = false
        detectTapGestures(
            onDoubleTap = if (onDoubleTap != null) ({ double?.invoke() }) else null,
            onTap = { if (!held) tap() },
            onPress = {
                held = false
                coroutineScope {
                    val timer = launch {
                        delay(HOLD_MILLIS)
                        held = true
                        hold()
                    }
                    tryAwaitRelease()
                    timer.cancel()
                    if (held) holdEnd()
                }
            }
        )
    }
}

/** The prompt's face: Japanese on the Japanese face, romaji on the Latin display face, prose on the system font. */
@Composable
fun promptStyle(form: VForm, wordSize: Int, translation: TextStyle): TextStyle = when (form) {
    VForm.Kana, VForm.Kanji, VForm.Audio -> Theme.jp(wordSize.sp)
    VForm.Romaji -> Theme.display(wordSize, FontWeight.SemiBold)
    VForm.Translation -> translation.copy(fontWeight = FontWeight.SemiBold)
}

/** The big check or cross over the card for an instant after an answer. Colour plus shape, never colour alone. */
@Composable
fun AnswerBadge(correct: Boolean, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val color = if (correct) Theme.colors.correct else Theme.colors.wrong
        SymbolIcon(
            if (correct) R.drawable.ic_check_circle else R.drawable.ic_cancel,
            color,
            BADGE_SP
        )
    }
}

private const val BADGE_SP = 96

/** A small bordered pill (the Practice pair capsule, the Read along speed). */
@Composable
fun PillButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable () -> Unit
) {
    Row(
        modifier
            .heightIn(min = 44.dp)
            .background(Theme.colors.surface, CircleShape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        content = { content() }
    )
}

/** A one-line caption centred under a deck. */
@Composable
fun Hint(text: String, modifier: Modifier = Modifier) {
    Text(text, style = Theme.text.caption2, color = Theme.colors.inkTertiary, modifier = modifier.padding(top = 4.dp))
}
