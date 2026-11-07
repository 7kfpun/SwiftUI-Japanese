package com.kfpun.japanesedaily.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.ui.Theme

/** How an answer control looks once the question is (or is not yet) settled. */
enum class Verdict { Open, Correct, Wrong, Dimmed }

/**
 * The idle/correct/wrong rules, once, instead of re-derived at each call site. [picked] is the
 * chosen index (null while the question is open), [index] this control's position.
 */
fun verdictOf(index: Int, picked: Int?, isAnswer: Boolean): Verdict = when {
    picked == null -> Verdict.Open
    isAnswer -> Verdict.Correct
    picked == index -> Verdict.Wrong
    else -> Verdict.Dimmed
}

/** Border/ink colour for a verdict: accent while open, green/red only for feedback, the hairline for the rest. */
@Composable
fun verdictColor(verdict: Verdict): Color = when (verdict) {
    Verdict.Open -> Theme.colors.accent
    Verdict.Correct -> Theme.colors.correct
    Verdict.Wrong -> Theme.colors.wrong
    Verdict.Dimmed -> Theme.colors.line
}

private const val ALSO_RAN_ALPHA = 0.45f
private const val ANSWER_FILL_ALPHA = 0.12f
private const val FADE_MILLIS = 200
private const val OPTION_MIN_HEIGHT_DP = 74
private const val CHIP_MIN_HEIGHT_DP = 96

/**
 * A quiz answer that fills the space it is given, shared by the Challenge ladder and the kana quiz
 * (iOS `QuizOptionButton`). A raised card while open: depth, not colour, says "tappable". Colour
 * appears only with the verdict, as a 2dp border plus a corner badge, so it is never colour alone.
 *
 * The text wraps instead of shrinking and the row grows (`minHeight`), because nothing here is a
 * fixed-height frame: German, Vietnamese and Burmese glosses run long.
 */
@Composable
fun QuizOptionButton(
    text: String,
    index: Int,
    picked: Int?,
    isAnswer: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    textStyle: TextStyle = Theme.text.headline
) {
    val verdict = verdictOf(index, picked, isAnswer)
    val answered = verdict != Verdict.Open
    val color by animateColorAsState(verdictColor(verdict), tween(FADE_MILLIS), label = "verdict")
    val shape = Theme.rounded(Theme.Radius.card)
    val shadow = Theme.colors.shadow
    Box(
        modifier
            .fillMaxSize()
            .alpha(if (verdict == Verdict.Dimmed) ALSO_RAN_ALPHA else 1f)
            .then(
                if (answered) {
                    Modifier
                } else {
                    Modifier.shadow(
                        Theme.Elevation.rest,
                        shape,
                        ambientColor = shadow,
                        spotColor = shadow
                    )
                }
            )
            .background(if (answered) color.copy(alpha = ANSWER_FILL_ALPHA) else Theme.colors.surface, shape)
            .then(if (answered) Modifier.border(2.dp, color, shape) else Modifier)
            .clickable(enabled = !answered, role = Role.Button, onClick = onClick)
            .padding(10.dp)
    ) {
        // Horizontal room for the corner badge, so the verdict never lands on the word.
        Text(
            text,
            style = textStyle,
            color = if (answered) color else Theme.colors.ink,
            textAlign = TextAlign.Center,
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 10.dp)
        )
        if (verdict == Verdict.Correct || verdict == Verdict.Wrong) {
            SymbolIcon(
                if (verdict == Verdict.Correct) R.drawable.ic_check_circle else R.drawable.ic_cancel,
                color,
                Theme.text.footnote.fontSize.value.toInt(),
                Modifier.align(Alignment.TopEnd)
            )
        }
    }
}

/** A 2x2 grid of quiz options (the kana classic quiz). Rows take the taller cell, never a fixed height. */
@Composable
fun OptionGrid(count: Int, modifier: Modifier = Modifier, cell: @Composable (Int) -> Unit) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for (row in 0 until 2) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .height(IntrinsicSize.Min)
                    .heightIn(min = OPTION_MIN_HEIGHT_DP.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                for (col in 0 until 2) {
                    val i = row * 2 + col
                    Box(Modifier.weight(1f).fillMaxHeight()) { if (i < count) cell(i) }
                }
            }
        }
    }
}

/**
 * One of the two candidates on a swipe-to-choose screen (iOS `SwipeOptionChip`). The chevron on the
 * chip's outer edge points the way to swipe; once answered it gives way to a check or cross.
 * [side] is 0 for the left chip, 1 for the right.
 */
@Composable
fun SwipeOptionChip(
    text: String,
    side: Int,
    picked: Int?,
    isAnswer: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    textStyle: TextStyle = Theme.text.title3.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
    hint: String? = null
) {
    val verdict = verdictOf(side, picked, isAnswer)
    val answered = verdict != Verdict.Open
    val color by animateColorAsState(verdictColor(verdict), tween(FADE_MILLIS), label = "chip")
    Column(
        modifier
            .fillMaxWidth()
            .heightIn(min = CHIP_MIN_HEIGHT_DP.dp)
            .choiceChip(color)
            .clickable(enabled = !answered, role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (side == 0) ChipMarker(side, verdict, color)
            Text(
                text,
                style = textStyle,
                color = if (answered) color else Theme.colors.ink,
                textAlign = TextAlign.Center,
                maxLines = CHIP_MAX_LINES,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false)
            )
            if (side == 1) ChipMarker(side, verdict, color)
        }
        // Hidden once answered: the verdict is the message then.
        if (hint != null && !answered) {
            Text(hint, style = Theme.text.caption2, color = Theme.colors.inkTertiary)
        }
    }
}

private const val CHIP_MAX_LINES = 4
private const val PLACEHOLDER_ALPHA = 0.25f

@Composable
private fun ChipMarker(side: Int, verdict: Verdict, color: Color) {
    val size = Theme.text.subheadline.fontSize.value.toInt()
    when (verdict) {
        Verdict.Open -> SymbolIcon(
            if (side == 0) R.drawable.ic_chevron_left else R.drawable.ic_chevron_right,
            color,
            size
        )

        Verdict.Correct -> SymbolIcon(R.drawable.ic_check_circle, color, size)

        Verdict.Wrong -> SymbolIcon(R.drawable.ic_cancel, color, size)

        // Faint placeholder so the row does not shift when the icons appear.
        Verdict.Dimmed -> SymbolIcon(R.drawable.ic_circle_outline, color.copy(alpha = PLACEHOLDER_ALPHA), size)
    }
}
