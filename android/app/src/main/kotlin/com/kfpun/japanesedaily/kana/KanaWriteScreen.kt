package com.kfpun.japanesedaily.kana

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.data.vocab.K
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.CanvasScreen
import com.kfpun.japanesedaily.ui.components.ScoreBadge
import com.kfpun.japanesedaily.ui.components.ScreenBar
import com.kfpun.japanesedaily.ui.components.SegmentedPicker
import com.kfpun.japanesedaily.ui.components.SoundToggle
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Grading is separate from scoring and happens on Next: a hard pass or fail (iOS `KanaWriteView.grade`). */
object WriteGrade {
    /**
     * The textbook stroke count must match exactly (when known) and the score must clear [KanaSketch.PASS_SCORE]:
     * exactly where the score row turns green, so the verdict and the feedback agree.
     */
    fun passes(score: Int, drawnStrokes: Int, expectedStrokes: Int?): Boolean {
        val strokesOk = expectedStrokes?.let { drawnStrokes == it } ?: true
        return strokesOk && score >= KanaSketch.PASS_SCORE
    }
}

private const val TEMPLATE_PIXELS = 640
private const val TEMPLATE_SHARE = 0.6f
private const val PROMPT_SIZE = 40
private const val INK_WIDTH_DP = 10f

/**
 * Write test (iOS `KanaWriteView`): hear the kana, see its romaji, then trace or draw it over an optional
 * stroke-shape template. After each stroke the drawing is scored 0-100; on Next the kana is graded and the verdict
 * feeds the same green and red tiles as every other mode. An undrawn, skipped kana is not graded.
 */
@Composable
fun KanaWriteScreen(env: KanaEnv, table: KanaTable, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val pool = remember(table) { table.pool(env.data) }
    val sound = env.rememberSound()
    val scope = rememberCoroutineScope()
    var answer by remember(table) { mutableStateOf(pool.randomOrNull() ?: K("あ", "ア", "a")) }
    var katakana by remember { mutableStateOf(false) }
    val strokes = remember { mutableStateListOf<List<Offset>>() }
    val current = remember { mutableStateListOf<Offset>() }
    var showTemplate by remember { mutableStateOf(true) }
    var score by remember { mutableStateOf<Int?>(null) }
    var correct by remember { mutableIntStateOf(0) }
    var total by remember { mutableIntStateOf(0) }
    var template by remember { mutableStateOf<ImageBitmap?>(null) }
    var playTick by remember { mutableIntStateOf(0) }
    var scoreRun by remember { mutableIntStateOf(0) }

    val glyph = if (katakana) answer.katakana else answer.hiragana
    val expected = (if (katakana) answer.katakanaStrokes else answer.hiraganaStrokes).takeIf { it > 0 }
    val android = env.glyphs as? AndroidGlyphRasterizer

    LaunchedEffect(Unit) { Track.screen(TrackScreens.KANA_WRITE) }
    // Auto-play respects the global sound setting (an explicit prompt tap does not).
    LaunchedEffect(playTick) { if (sound.on) env.speaker.speak(answer) }
    // A stale in-flight render is cancelled when the glyph changes.
    LaunchedEffect(glyph) {
        template = withContext(Dispatchers.Default) { android?.templateBitmap(glyph, TEMPLATE_PIXELS)?.asImageBitmap() }
    }

    fun clear() {
        strokes.clear()
        current.clear()
        score = null
        scoreRun++
    }

    fun rescore() {
        val copy = strokes.map { s -> s.map { SketchPoint(it.x.toDouble(), it.y.toDouble()) } }
        val run = ++scoreRun
        scope.launch {
            val s = withContext(Dispatchers.Default) { KanaSketch.matchScore(copy, glyph, env.glyphs, expected) }
            if (run == scoreRun) score = s
        }
    }

    /** One verdict per kana, so the low scores midway through a multi-stroke glyph never count as misses. */
    fun grade() {
        val s = score
        if (s == null) {
            // Next on an undrawn canvas is not an answer, but skipping is the strongest difficulty signal here.
            Track.event(TrackEvents.KANA_WRITE_SKIP, mapOf("romaji" to answer.romaji))
            return
        }
        val pass = WriteGrade.passes(s, strokes.size, expected)
        total += 1
        if (pass) correct += 1
        env.record(answer.romaji, pass)
        Track.event(TrackEvents.KANA_WRITE_GRADE, mapOf("pass" to pass, "score" to s))
    }

    CanvasScreen(modifier) {
        Column(Modifier.fillMaxSize()) {
            ScreenBar(
                onBack = onBack,
                center = { ScoreBadge(correct, total) },
                actions = { SoundToggle(sound.on, sound.toggle) }
            )
            Column(
                Modifier.weight(1f).fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                SegmentedPicker(
                    labels = listOf(stringResource(R.string.hiragana), stringResource(R.string.katakana)),
                    selected = if (katakana) 1 else 0,
                    onSelect = {
                        katakana = it == 1
                        Track.event(
                            TrackEvents.KANA_WRITE_SCRIPT,
                            mapOf("script" to if (katakana) "katakana" else "hiragana")
                        )
                        clear()
                    }
                )
                // The prompt is just the romaji: the picker above already says which script. Tap to replay.
                Box(
                    Modifier.fillMaxWidth().clickable(role = Role.Button) {
                        env.speaker.speak(answer)
                    },
                    Alignment.Center
                ) {
                    Text(
                        answer.romaji,
                        style = Theme.display(PROMPT_SIZE, FontWeight.SemiBold),
                        color = Theme.colors.ink
                    )
                }
                DrawingCanvas(
                    strokes = strokes,
                    current = current,
                    template = if (showTemplate) template else null,
                    onStrokeEnd = {
                        if (current.size > 1) {
                            strokes.add(current.toList())
                            rescore()
                        }
                        current.clear()
                    },
                    modifier = Modifier.weight(1f)
                )
                ScoreRow(score, strokes.size, expected)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    WriteButton(stringResource(R.string.clear), null) {
                        // Only the button logs: clear() also runs on script switches and page turns.
                        Track.event(
                            TrackEvents.KANA_WRITE_CLEAR,
                            mapOf("strokes" to strokes.size, "romaji" to answer.romaji)
                        )
                        clear()
                    }
                    WriteButton(
                        stringResource(R.string.reveal),
                        if (showTemplate) R.drawable.ic_visibility_off else R.drawable.ic_visibility
                    ) {
                        showTemplate = !showTemplate
                        // How often the stroke guide is needed is this mode's difficulty signal.
                        Track.event(
                            TrackEvents.KANA_WRITE_TEMPLATE,
                            mapOf("shown" to showTemplate, "romaji" to answer.romaji)
                        )
                    }
                    Box(
                        Modifier
                            .weight(1f)
                            .heightIn(min = 48.dp)
                            .background(Theme.colors.accent, Theme.rounded(Theme.Radius.chip))
                            .clickable(role = Role.Button) {
                                grade()
                                clear()
                                answer = pool.randomOrNull() ?: answer
                                playTick++
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            stringResource(R.string.next),
                            style = Theme.title(Theme.text.headline),
                            color = Theme.colors.onAccent
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.WriteButton(text: String, icon: Int?, onClick: () -> Unit) {
    val shape = Theme.rounded(Theme.Radius.chip)
    Row(
        Modifier
            .heightIn(min = 48.dp)
            .border(1.dp, Theme.colors.accent, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icon != null) SymbolIcon(icon, Theme.colors.accent, Theme.text.subheadline.fontSize.value.toInt())
        Text(text, style = Theme.text.subheadline, color = Theme.colors.accent)
    }
}

@Composable
private fun DrawingCanvas(
    strokes: List<List<Offset>>,
    current: MutableList<Offset>,
    template: ImageBitmap?,
    onStrokeEnd: () -> Unit,
    modifier: Modifier = Modifier
) {
    val ink = Theme.colors.ink
    Box(
        modifier
            .fillMaxWidth()
            .background(Theme.colors.surface, Theme.rounded(Theme.Radius.card))
            .border(1.dp, Theme.colors.line, Theme.rounded(Theme.Radius.card))
            .pointerInput(Unit) {
                // Minimum distance zero, like iOS: every touch point counts from the first.
                awaitEachGesture {
                    val down = awaitFirstDown()
                    current.clear()
                    current.add(down.position)
                    drag(down.id) { change ->
                        current.add(change.position)
                        change.consume()
                    }
                    onStrokeEnd()
                }
            },
        contentAlignment = Alignment.Center
    ) {
        if (template != null) {
            // Pre-rendered, digit-free stroke shape, aspect-preserved so combos never squish, sized down so
            // it reads as a guide rather than a shape to fill edge to edge.
            Image(
                template,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                colorFilter = ColorFilter.tint(Theme.colors.inkTertiary),
                modifier = Modifier.fillMaxSize(TEMPLATE_SHARE)
            )
        }
        Canvas(Modifier.fillMaxSize()) {
            val style = Stroke(width = INK_WIDTH_DP.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
            for (s in strokes + listOf(current.toList())) {
                if (s.size <= 1) continue
                val path = Path().apply {
                    moveTo(s[0].x, s[0].y)
                    for (p in s.drop(1)) lineTo(p.x, p.y)
                }
                drawPath(path, ink, style = style)
            }
        }
    }
}

/** Live match feedback after each stroke, wordless so there is nothing to localise: shape score and drawn/expected. */
@Composable
private fun ScoreRow(score: Int?, drawn: Int, expected: Int?) {
    val colors = Theme.colors
    val style = Theme.title(Theme.text.headline).copy(fontWeight = FontWeight.SemiBold)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 28.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (score == null) return@Row
        val tint = when {
            score >= KanaSketch.PASS_SCORE -> colors.correct
            score >= KanaSketch.WEAK_SCORE -> colors.streak
            else -> colors.wrong
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SymbolIcon(R.drawable.ic_edit, tint, style.fontSize.value.toInt())
            Text("$score%", style = style, color = tint)
        }
        if (expected != null) {
            // Too few strokes may just mean "not finished": stay neutral.
            val strokeTint = when {
                drawn == expected -> colors.correct
                drawn > expected -> colors.wrong
                else -> colors.inkSecondary
            }
            Text("$drawn/$expected", style = style, color = strokeTint)
        }
    }
}
