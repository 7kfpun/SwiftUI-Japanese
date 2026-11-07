package com.kfpun.japanesedaily.ui.components

import androidx.annotation.DrawableRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.ui.Theme

/** A size in `sp` as a `Dp`, so an icon beside text grows with the font scale like an SF Symbol does. */
@Composable
fun scaledSize(sp: Int): Dp = with(LocalDensity.current) { sp.sp.toDp() }

/**
 * Surface, hairline and a lift (iOS `cardChrome`). `lifted` is the deck; the resting blur is for a
 * panel among other panels. Dark mode drops the shadow (`Theme.colors.shadow` is clear) and keeps the line.
 */
@Composable
fun Modifier.cardChrome(radius: Dp = Theme.Radius.card, lifted: Boolean = false): Modifier {
    val colors = Theme.colors
    val shape = Theme.rounded(radius)
    return this
        .shadow(
            if (lifted) Theme.Elevation.deck else Theme.Elevation.rest,
            shape,
            ambientColor = colors.shadow,
            spotColor = colors.shadow
        )
        .background(colors.surface, shape)
        .border(1.dp, colors.line, shape)
}

/**
 * A tinted callout: wash plus a hairline in the same colour (iOS `accentPlate`). Not a fill, which
 * would spend the accent the way a selected answer must not.
 */
@Composable
fun Modifier.accentPlate(radius: Dp = Theme.Radius.card, tint: Color = Theme.colors.accent): Modifier {
    val shape = Theme.rounded(radius)
    return this.background(Theme.colors.wash(tint), shape).border(1.dp, tint, shape)
}

/** Selection state is an accent *border*, never a fill, and never green or red. */
@Composable
fun Modifier.selectionBorder(selected: Boolean, radius: Dp = Theme.Radius.card): Modifier =
    if (selected) border(BorderStroke(2.dp, Theme.colors.accent), Theme.rounded(radius)) else this

/**
 * Shared chrome for every choice control on a swipe screen (iOS `choiceChip`): a light tint fill
 * and a coloured border. The caller sets the foreground to the same [color].
 */
@Composable
fun Modifier.choiceChip(color: Color): Modifier {
    val shape = Theme.rounded(Theme.Radius.pill)
    return this.background(color.copy(alpha = CHIP_FILL_ALPHA), shape).border(2.dp, color, shape)
}

internal const val CHIP_FILL_ALPHA = 0.12f

/** A Material icon drawable tinted to [tint] and sized in `sp` (functional icons are never illustrations). */
@Composable
fun SymbolIcon(@DrawableRes id: Int, tint: Color, sizeSp: Int, modifier: Modifier = Modifier) {
    Icon(painterResource(id), contentDescription = null, tint = tint, modifier = modifier.size(scaledSize(sizeSp)))
}

/** The "< Swipe >" whisper at a card's bottom edge. [label] is the localised "Swipe". */
@Composable
fun SwipeHint(label: String, modifier: Modifier = Modifier) {
    val tertiary = Theme.colors.inkTertiary
    Row(
        modifier.padding(bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SymbolIcon(R.drawable.ic_chevron_left, tertiary, Theme.text.caption.fontSize.value.toInt())
        Text(label, style = Theme.text.caption, color = tertiary)
        SymbolIcon(R.drawable.ic_chevron_right, tertiary, Theme.text.caption.fontSize.value.toInt())
    }
}

/** What a corner stamp shows. Paired with an icon so a verdict never rests on colour alone. */
class StampSpec(@DrawableRes val icon: Int, val color: Color)

/** Tinder-style corner stamp for swipeable cards. */
@Composable
fun SwipeStamp(spec: StampSpec, rotation: Float, modifier: Modifier = Modifier) {
    Box(
        modifier
            .rotate(rotation)
            .border(3.dp, spec.color, Theme.rounded(Theme.Radius.chip))
            .padding(10.dp)
    ) {
        SymbolIcon(spec.icon, spec.color, STAMP_ICON_SP)
    }
}

private const val STAMP_ICON_SP = 22

/** The accent (or quiet) icon well list rows share. */
@Composable
fun IconWell(@DrawableRes icon: Int, active: Boolean = true, modifier: Modifier = Modifier) {
    val tint = if (active) Theme.colors.accent else Theme.colors.inkSecondary
    Box(
        modifier
            .heightIn(min = scaledSize(ICON_WELL_SP))
            .widthIn(min = scaledSize(ICON_WELL_SP))
            .background(Theme.colors.wash(tint), Theme.rounded(Theme.Radius.chip)),
        contentAlignment = Alignment.Center
    ) {
        SymbolIcon(icon, tint, Theme.text.title3.fontSize.value.toInt())
    }
}

private const val ICON_WELL_SP = 36

/**
 * The full-width action pill (iOS `PrimaryPillButton`): ink fill, canvas-coloured text. Fill, shape
 * and hit region are one and the same modifier chain, so the whole bar takes taps. `minHeight`,
 * not a fixed height, so large text and long languages can grow it.
 */
@Composable
fun PrimaryPillButton(onClick: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val shape = Theme.rounded(Theme.Radius.pill)
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 54.dp)
            .background(Theme.colors.ink, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center
    ) {
        androidx.compose.runtime.CompositionLocalProvider(
            androidx.compose.material3.LocalContentColor provides Theme.colors.canvas,
            content = content
        )
    }
}

/**
 * A whole-screen empty state: art over one line of guidance, on the canvas. The art is a slot
 * because call sites disagree on it. The koboyo illustrations are for this and nothing else.
 */
@Composable
fun EmptyStatePanel(text: String, modifier: Modifier = Modifier, art: @Composable () -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .background(Theme.colors.canvas)
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Box(
            Modifier
                .background(Theme.colors.wash(Theme.colors.accent), Theme.rounded(Theme.Radius.deck))
                .padding(20.dp)
        ) { art() }
        Text(
            text,
            style = Theme.text.subheadline,
            color = Theme.colors.inkSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 320.dp)
        )
    }
}

/** Empty-state artwork, template-rendered so it takes [tint] (a Theme colour). Decorative. */
@Composable
fun Illustration(@DrawableRes id: Int, modifier: Modifier = Modifier, tint: Color = Theme.colors.accent) {
    Image(
        painterResource(id),
        contentDescription = null,
        colorFilter = ColorFilter.tint(tint),
        modifier = modifier.widthIn(max = 160.dp)
    )
}
