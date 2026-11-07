package com.kfpun.japanesedaily.kana

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.progress.KanaResult
import com.kfpun.japanesedaily.data.vocab.K
import com.kfpun.japanesedaily.ui.KanaForm
import com.kfpun.japanesedaily.ui.JapaneseFace
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.BarIconButton
import com.kfpun.japanesedaily.ui.components.CanvasScreen
import com.kfpun.japanesedaily.ui.components.CapsuleBar
import com.kfpun.japanesedaily.ui.components.FitText
import com.kfpun.japanesedaily.ui.components.ScreenBar
import com.kfpun.japanesedaily.ui.components.SegmentedPicker
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.glyphStyle
import kotlinx.coroutines.launch

/**
 * The Kana tab's browser (iOS `KanaBrowserView`): a Seion / Dakuon / Youon picker, a progress bar for the chart
 * on screen, the grid of mastery tiles, and the toolbar's rotating tile-script button. Everything under the
 * tab is free: there is no gating anywhere here.
 */
@Composable
fun KanaBrowser(env: KanaEnv, onQuiz: (KanaTable) -> Unit, modifier: Modifier = Modifier) {
    var table by rememberSaveable { mutableStateOf(KanaTable.Seion) }
    val tileScript by env.prefState(Pref.kanaTileScript)
    val results by remember { env.container.progress.observeKana() }.collectAsState(emptyMap())
    val scope = rememberCoroutineScope()
    var confirmClear by remember { mutableStateOf(false) }
    val latest = remember(results) { results.mapValues { it.value.isCorrect } }
    val cells = remember(table) { table.pool(env.data) }

    LaunchedEffect(Unit) { Track.screen(TrackScreens.KANA) }

    CanvasScreen(modifier) {
        Column(Modifier.fillMaxSize()) {
            ScreenBar(
                leading = {
                    BarIconButton(
                        R.drawable.ic_delete,
                        stringResource(R.string.clear),
                        { confirmClear = true },
                        enabled = results.isNotEmpty()
                    )
                },
                center = {
                    Text(
                        stringResource(R.string.kana),
                        style = Theme.title(Theme.text.headline),
                        color = Theme.colors.ink
                    )
                },
                actions = {
                    // What the tiles show big. One tap rotates hiragana, katakana, romaji; the glyph says which.
                    val current = TileScript.of(tileScript)
                    val label = stringResource(current.name)
                    Box(
                        Modifier
                            .heightIn(min = 48.dp)
                            .clickable(role = Role.Button) {
                                val next = TileScript.next(tileScript)
                                scope.launch { env.container.prefs.set(Pref.kanaTileScript, next) }
                                Track.event(TrackEvents.KANA_TILE_SCRIPT, mapOf("script" to next))
                            }
                            .padding(horizontal = 12.dp)
                            .semantics { contentDescription = label },
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            current.glyph,
                            style = glyphStyle(
                                current.form.isJapanese,
                                BUTTON_GLYPH,
                                JapaneseFace.Bold,
                                FontWeight.SemiBold
                            ),
                            color = Theme.colors.accent
                        )
                    }
                    // The quiz opens on whichever chart is on screen, so the event carries it.
                    TextButton(onClick = {
                        Track.event(TrackEvents.KANA_QUIZ_OPEN, mapOf("table" to table.raw))
                        onQuiz(table)
                    }) {
                        Text(stringResource(R.string.quiz), color = Theme.colors.accent)
                    }
                }
            )
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                SegmentedPicker(
                    labels = KanaTable.entries.map { stringResource(it.title) },
                    selected = table.ordinal,
                    onSelect = {
                        table = KanaTable.entries[it]
                        Track.event(TrackEvents.KANA_TABLE, mapOf("table" to table.raw))
                    }
                )
                KanaProgressBar(learned = learnedCount(cells, latest), total = distinctRomaji(cells).size)
                KanaGrid(
                    rows = table.rows(env.data),
                    big = TileScript.of(tileScript).form,
                    square = table != KanaTable.Youon,
                    latest = latest,
                    onTap = {
                        env.speaker.speak(it)
                        Track.event(TrackEvents.PLAY_KANA, mapOf("romaji" to it.romaji))
                    }
                )
                Spacer(Modifier.padding(bottom = 12.dp))
            }
        }
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text(stringResource(R.string.clear_all_learned_kana)) },
            text = { Text(stringResource(R.string.resets_the_green_red_progress_on_every_kana_tile)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmClear = false
                    // Counted before the delete: wiping three tiles is a tidy-up, ninety is starting over.
                    val cleared = results.size
                    scope.launch { env.container.progress.clearKana() }
                    Track.event(TrackEvents.KANA_CLEAR, mapOf("cleared" to cleared))
                }) { Text(stringResource(R.string.clear_arg, results.size.toString()), color = Theme.colors.wrong) }
            },
            dismissButton = {
                TextButton(onClick = { confirmClear = false }) { Text(stringResource(R.string.cancel)) }
            }
        )
    }
}

private const val BUTTON_GLYPH = 17

/** Grid of tiles. Seion and Dakuon are square; Youon (three columns) is not, or the tiles would be huge. */
@Composable
private fun KanaGrid(
    rows: List<List<K>>,
    big: KanaForm,
    square: Boolean,
    latest: Map<String, Boolean>,
    onTap: (K) -> Unit
) {
    val cols = rows.maxOfOrNull { it.size } ?: 1
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (row in rows) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (c in 0 until cols) {
                    val cell = row.getOrNull(c)
                    val sizing = if (square) Modifier.aspectRatio(1f) else Modifier.heightIn(min = FLEX_TILE_MIN.dp)
                    Box(Modifier.weight(1f).then(sizing)) {
                        if (cell != null && !cell.isEmpty) {
                            KanaTile(cell, latest[cell.romaji], big, Modifier.fillMaxSize()) { onTap(cell) }
                        }
                    }
                }
            }
        }
    }
}

private const val FLEX_TILE_MIN = 64
private const val TILE_GLYPH = 26

/** One tile: the big form plus the other two as captions, bordered green, red or neutral by the last answer. */
@Composable
fun KanaTile(cell: K, lastCorrect: Boolean?, big: KanaForm, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = Theme.colors
    val border = when (lastCorrect) {
        true -> colors.correct
        false -> colors.wrong
        null -> colors.line
    }
    val shape = Theme.rounded(Theme.Radius.chip)
    val caption = when (big) {
        KanaForm.Katakana -> listOf(cell.hiragana, cell.romaji)
        KanaForm.Romaji -> listOf(cell.hiragana, cell.katakana)
        KanaForm.Hiragana -> listOf(cell.katakana, cell.romaji)
    }
    val correctWord = stringResource(R.string.correct)
    val wrongWord = stringResource(R.string.wrong)
    Box(
        modifier
            .background(colors.surface, shape)
            .border(if (lastCorrect == null) 1.dp else 1.5.dp, border, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics {
                stateDescription = when (lastCorrect) {
                    true -> correctWord
                    false -> wrongWord
                    null -> ""
                }
            }
            .padding(4.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            // Romaji is Latin and takes the Latin face; kana takes the Japanese one.
            FitText(
                cell.value(big),
                glyphStyle(big.isJapanese, TILE_GLYPH, JapaneseFace.Bold, FontWeight.SemiBold),
                minScale = 0.5f
            )
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                caption.forEach { Text(it, style = Theme.text.caption, color = colors.inkSecondary, maxLines = 1) }
            }
        }
        // The verdict's glyph beside its colour: green and red are one colour to roughly 8% of men.
        if (lastCorrect != null) {
            SymbolIcon(
                if (lastCorrect) R.drawable.ic_check else R.drawable.ic_close,
                border,
                Theme.text.caption2.fontSize.value.toInt(),
                Modifier.align(Alignment.TopEnd).padding(1.dp)
            )
        }
    }
}

/**
 * How much of the chart on screen is learned: a bar and a percentage, scoped to the selected table so three
 * reachable hundreds beat one distant one, and the bar resets when the picker moves.
 */
@Composable
private fun KanaProgressBar(learned: Int, total: Int) {
    val fraction = if (total > 0) learned.toFloat() / total else 0f
    val animated by animateFloatAsState(fraction, label = "kana-progress")
    val percent = Math.round(fraction * PERCENT)
    val complete = total > 0 && learned >= total
    val tint = if (complete) Theme.colors.streak else Theme.colors.accent
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            SymbolIcon(
                if (complete) R.drawable.ic_check_circle else R.drawable.ic_bar_chart,
                tint,
                Theme.text.caption.fontSize.value.toInt()
            )
            Text(
                if (complete) stringResource(R.string.complete) else "$learned / $total",
                style = Theme.text.footnote.copy(fontWeight = FontWeight.SemiBold),
                color = if (complete) tint else Theme.colors.inkSecondary
            )
            Spacer(Modifier.weight(1f))
            Text("$percent%", style = Theme.text.footnote.copy(fontWeight = FontWeight.Bold), color = tint)
        }
        CapsuleBar(animated, tint)
    }
}

private const val PERCENT = 100
