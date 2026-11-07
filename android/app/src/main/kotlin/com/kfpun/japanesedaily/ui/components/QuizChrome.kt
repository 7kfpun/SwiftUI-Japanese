package com.kfpun.japanesedaily.ui.components

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.ui.Theme

/**
 * The shared quiz chrome (iOS `Components.swift`): the status capsule, sound toggle, tap-to-hear panel, mode
 * rows and the segmented picker. Kana uses it first; Lessons' quiz screens reuse it.
 */

/** A navigation-bar stand-in: back arrow, a centred [center] slot and trailing [actions]. */
@Composable
fun ScreenBar(
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    leading: @Composable () -> Unit = {},
    center: @Composable () -> Unit = {},
    actions: @Composable RowScope.() -> Unit = {}
) {
    Row(
        modifier.fillMaxWidth().heightIn(min = BAR_MIN_DP.dp).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
            if (onBack != null) BarIconButton(R.drawable.ic_arrow_back, stringResource(R.string.back), onBack)
            leading()
        }
        center()
        Row(
            Modifier.weight(1f),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
            content = actions
        )
    }
}

private const val BAR_MIN_DP = 56

/** A toolbar icon: 48dp touch target, accent tint like iOS toolbar buttons. */
@Composable
fun BarIconButton(
    @DrawableRes icon: Int,
    description: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    tint: Color = Theme.colors.accent
) {
    Box(
        modifier
            .heightIn(min = TARGET_DP.dp)
            .widthIn(min = TARGET_DP.dp)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center
    ) {
        SymbolIcon(icon, if (enabled) tint else Theme.colors.inkTertiary, ICON_SP)
    }
}

private const val TARGET_DP = 48
private const val ICON_SP = 22

/** The speaker button every quiz carries: sound on or off, a single global preference. */
@Composable
fun SoundToggle(on: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    BarIconButton(
        if (on) R.drawable.ic_volume_up else R.drawable.ic_volume_off,
        stringResource(if (on) R.string.turn_sound_off else R.string.turn_sound_on),
        onToggle,
        modifier
    )
}

/** The capsule that holds a run's numbers in the middle of the bar, with an optional [caption] under it. */
@Composable
fun ToolbarStatus(caption: String? = null, content: @Composable RowScope.() -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Row(
            Modifier
                .background(Theme.colors.wash(Theme.colors.inkSecondary), Theme.rounded(Theme.Radius.pill))
                .padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content
        )
        if (caption != null) Text(caption, style = Theme.text.caption2, color = Theme.colors.inkSecondary)
    }
}

/** A tinted icon and number, the atom of the status capsule. */
@Composable
fun IconCount(@DrawableRes icon: Int, count: Int, color: Color, style: TextStyle = Theme.text.subheadline) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        SymbolIcon(icon, color, style.fontSize.value.toInt())
        Text(count.toString(), style = style.copy(fontWeight = FontWeight.SemiBold), color = color)
    }
}

/** Right, wrong and total for a run. Wordless, so there is nothing to translate. */
@Composable
fun ScoreBadge(correct: Int, total: Int, caption: String? = null) {
    ToolbarStatus(caption) {
        IconCount(R.drawable.ic_check, correct, Theme.colors.correct, Theme.text.footnote)
        IconCount(R.drawable.ic_close, total - correct, Theme.colors.wrong, Theme.text.footnote)
        Text("/ $total", style = Theme.text.footnote.copy(fontWeight = FontWeight.Medium), color = Theme.colors.inkSecondary)
    }
}

/** The tap-to-hear question pane the kana quiz and the Challenge run share: content on a lifted card. */
@Composable
fun QuizPromptPanel(onTap: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier
            .fillMaxWidth()
            .cardChrome(lifted = true)
            .clickable(role = Role.Button, onClick = onTap),
        contentAlignment = Alignment.Center
    ) { content() }
}

/** The accent speaker standing in for an audio prompt. */
@Composable
fun AudioPromptGlyph() {
    val description = stringResource(R.string.tap_to_hear_it)
    Box(Modifier.semantics { contentDescription = description }) {
        SymbolIcon(R.drawable.ic_volume_up, Theme.colors.accent, AUDIO_GLYPH_SP)
    }
}

private const val AUDIO_GLYPH_SP = 64

/** The verdict that flashes over a swipe quiz after an answer: icon, word, green or red. */
@Composable
fun AnswerBadge(correct: Boolean, modifier: Modifier = Modifier) {
    val color = if (correct) Theme.colors.correct else Theme.colors.wrong
    Column(
        modifier
            .background(Theme.colors.surface, Theme.rounded(Theme.Radius.hero))
            .border(2.dp, color, Theme.rounded(Theme.Radius.hero))
            .padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        SymbolIcon(if (correct) R.drawable.ic_check_circle else R.drawable.ic_cancel, color, BADGE_ICON_SP)
        Text(
            stringResource(if (correct) R.string.correct else R.string.wrong),
            style = Theme.text.title.copy(fontWeight = FontWeight.Bold),
            color = color
        )
    }
}

private const val BADGE_ICON_SP = 72

/** A mode row: accent icon well, name in the title face, one-line description under it. */
@Composable
fun ModeRow(@DrawableRes icon: Int, title: String, subtitle: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconWell(icon)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Theme.title(Theme.text.headline), color = Theme.colors.ink)
            Text(subtitle, style = Theme.text.caption, color = Theme.colors.inkSecondary)
        }
        SymbolIcon(R.drawable.ic_chevron_right, Theme.colors.inkTertiary, Theme.text.footnote.fontSize.value.toInt())
    }
}

/** A thin capsule progress bar. */
@Composable
fun CapsuleBar(fraction: Float, fill: Color, modifier: Modifier = Modifier) {
    val shape = Theme.rounded(Theme.Radius.pill)
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = BAR_HEIGHT_DP.dp)
            .background(Theme.colors.inkSecondary.copy(alpha = TRACK_ALPHA), shape)
    ) {
        Box(
            Modifier
                .fillMaxWidth(fraction.coerceIn(0f, 1f))
                .heightIn(min = BAR_HEIGHT_DP.dp)
                .background(fill, shape)
        )
    }
}

private const val BAR_HEIGHT_DP = 8
private const val TRACK_ALPHA = 0.18f

/**
 * A segmented picker. The selected segment takes an accent *border*, never a fill (selection state), and
 * a bold label; the rest sit on a hairline.
 */
@Composable
fun SegmentedPicker(labels: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        labels.forEachIndexed { i, label ->
            val on = i == selected
            Box(
                Modifier
                    .weight(1f)
                    .heightIn(min = TARGET_DP.dp)
                    .background(Theme.colors.surface, Theme.rounded(Theme.Radius.chip))
                    .border(1.dp, Theme.colors.line, Theme.rounded(Theme.Radius.chip))
                    .selectionBorder(on, Theme.Radius.chip)
                    .clickable(role = Role.Tab) { onSelect(i) }
                    .semantics { this.selected = on }
                    .padding(horizontal = 8.dp, vertical = 8.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    label,
                    style = Theme.text.subheadline.copy(fontWeight = if (on) FontWeight.Bold else FontWeight.Normal),
                    color = Theme.colors.ink,
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}

/**
 * One line of text that shrinks to fit, down to [minScale] of [style]'s size (iOS `minimumScaleFactor`):
 * a combo like びゃ shrinks instead of truncating. Pass a Theme style; the size is the ceiling.
 */
@Composable
fun FitText(
    text: String,
    style: TextStyle,
    modifier: Modifier = Modifier,
    color: Color = Theme.colors.ink,
    minScale: Float = 0.4f
) {
    BasicText(
        text,
        modifier = modifier,
        style = style.copy(color = color, textAlign = TextAlign.Center),
        maxLines = 1,
        softWrap = false,
        autoSize = TextAutoSize.StepBased(minFontSize = style.fontSize * minScale, maxFontSize = style.fontSize)
    )
}

/** A full-size box on the canvas colour: the root of a screen. */
@Composable
fun CanvasScreen(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxSize().background(Theme.colors.canvas)) { content() }
}
