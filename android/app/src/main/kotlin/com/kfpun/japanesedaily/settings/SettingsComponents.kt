package com.kfpun.japanesedaily.settings

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.cardChrome
import com.kfpun.japanesedaily.ui.components.selectionBorder

/**
 * A grouped block of rows with an optional header above and footer below, the grouped-list look the iOS
 * Settings form has. Rows sit on a card (lighter than the screen); [footer] is secondary prose.
 */
@Composable
internal fun SettingsGroup(
    modifier: Modifier = Modifier,
    header: String? = null,
    footer: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (header != null) {
            // Same size and secondary colour a grouped list gives headers; only the face is the title face.
            Text(
                header,
                style = Theme.title(Theme.text.footnote),
                color = Theme.colors.inkSecondary,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        }
        Column(Modifier.fillMaxWidth().cardChrome(Theme.Radius.card)) { content() }
        if (footer != null) Box(Modifier.padding(horizontal = 16.dp)) { footer() }
    }
}

@Composable
internal fun FooterText(text: String, modifier: Modifier = Modifier) =
    Text(text, style = Theme.text.footnote, color = Theme.colors.inkSecondary, modifier = modifier)

/** A thin rule between two rows of one group, inset like the row text. */
@Composable
internal fun RowDivider() =
    HorizontalDivider(Modifier.padding(start = 16.dp), thickness = 0.5.dp, color = Theme.colors.line)

/**
 * One tappable row: [title] with an optional current [value] (or a [trailing] slot) and an optional
 * symbol. [onClick] is last so a trailing lambda is the tap. `defaultMinSize`, never a fixed height, so German and Burmese can wrap to two lines.
 */
@Composable
internal fun SettingsRow(
    title: String,
    modifier: Modifier = Modifier,
    value: String? = null,
    @DrawableRes icon: Int? = null,
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null
) {
    Row(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 52.dp)
            .let { if (onClick != null) it.clickable(role = Role.Button, onClick = onClick) else it }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (icon != null) SymbolIcon(icon, Theme.colors.accent, ROW_ICON_SP)
        Text(title, style = Theme.text.body, color = Theme.colors.ink, modifier = Modifier.weight(1f))
        if (value != null) {
            Text(value, style = Theme.text.body, color = Theme.colors.inkSecondary)
        }
        trailing?.invoke()
    }
}

/** A row whose whole width toggles [checked]; the switch is the state, never a fill on the row. */
@Composable
internal fun SettingsSwitchRow(title: String, checked: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 52.dp)
            .clickable(role = Role.Switch, onClick = onToggle)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(title, style = Theme.text.body, color = Theme.colors.ink, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            // The row owns the tap, so the switch itself is display-only and not a second target.
            onCheckedChange = null,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Theme.colors.onAccent,
                checkedTrackColor = Theme.colors.accent
            ),
            modifier = Modifier.semantics { role = Role.Switch }
        )
    }
}

/**
 * A titled row of mutually exclusive options. The chosen one gets the accent *border*, never a fill: green
 * and red belong to answer feedback and selection is a border everywhere else.
 */
@Composable
internal fun <T> SettingsChoiceRow(
    title: String,
    options: List<T>,
    selected: T,
    label: @Composable (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = Theme.text.body, color = Theme.colors.ink)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            options.forEach { option ->
                val isSelected = option == selected
                Box(
                    Modifier
                        .weight(1f)
                        .defaultMinSize(minHeight = 44.dp)
                        .background(Theme.colors.canvas, Theme.rounded(Theme.Radius.chip))
                        .selectionBorder(isSelected, Theme.Radius.chip)
                        .clickable(role = Role.RadioButton) { onSelect(option) }
                        .padding(horizontal = 6.dp, vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        label(option),
                        style = Theme.text.subheadline,
                        color = if (isSelected) Theme.colors.accent else Theme.colors.ink
                    )
                }
            }
        }
    }
}

private const val ROW_ICON_SP = 20
