package com.kfpun.japanesedaily.lessons

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.audio.LocalPronouncer
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.ScoreBadge
import kotlinx.coroutines.delay

/** A tile's slot on the board: the key its frame is filed under. */
private data class Anchor(val side: MatchModel.Side, val index: Int)

private const val MISS_MILLIS = 450L
private const val FLASH_MILLIS = 600L
private const val SHAKE_PX = 8f
private const val SHAKE_STEP_MILLIS = 30
private const val LINE_WIDTH_DP = 3

/**
 * Match (port of `MatchView`): five words down the left, their meanings shuffled down the right, endless.
 * Tap one from each side **or drag a line between them**; either side can start (meanings first is recall).
 * Tiles report their frames so the drop test and the lines have real geometry. A miss shakes its tile; the
 * round's last pair gets the same moment as the other four before the board deals the next five.
 */
@Composable
fun MatchScreen(lessonNumber: Int, env: LessonsEnv, nav: LessonsNav, modifier: Modifier = Modifier) {
    val container = env.container
    val pronouncer = LocalPronouncer.current
    val exits = LocalLessonExits.current
    val soundOn = rememberPref(Pref.soundOn, container).value
    val model = remember(lessonNumber) { MatchModel(env.lesson(lessonNumber).entries) }

    // The pair whose green moment is still on screen: view state, the model records *what* matched.
    var flashId by remember { mutableStateOf<String?>(null) }
    val frames = remember { mutableStateMapOf<Anchor, Rect>() }
    var boardOrigin by remember { mutableStateOf(Offset.Zero) }
    var dragFrom by remember { mutableStateOf<Anchor?>(null) }
    var dragPoint by remember { mutableStateOf<Offset?>(null) }

    LaunchedEffect(lessonNumber) {
        Track.screen(TrackScreens.MATCH, mapOf("lesson" to lessonNumber))
        container.prefs.markModeVisit(lessonNumber, LessonMode.MATCH)
    }
    DisposableEffect(model) { onDispose { exits.onLeaveMatch(model.attempts > 0) } }

    // The miss flash: long enough to see which two were wrong, short enough never to feel like a penalty.
    LaunchedEffect(model.wrong) {
        if (!model.wrong) return@LaunchedEffect
        Track.event(
            TrackEvents.MATCH_ANSWER,
            mapOf("lesson" to lessonNumber, "correct" to false, "via" to model.lastVia)
        )
        delay(MISS_MILLIS)
        model.clearMiss()
    }
    // The green moment, keyed on `matched` (a count) rather than the id: the last pair of one round and the
    // first of the next could be the same word, and an id that does not change would not re-fire.
    LaunchedEffect(model.matched) {
        val id = model.lastMatched ?: return@LaunchedEffect
        Track.event(
            TrackEvents.MATCH_ANSWER,
            mapOf("lesson" to lessonNumber, "correct" to true, "via" to model.lastVia)
        )
        flashId = id
        delay(FLASH_MILLIS)
        if (flashId == id) flashId = null
        // The deal is deferred in the model precisely so the last pair is not swallowed by its own success.
        if (model.roundCleared) {
            Track.event(
                TrackEvents.MATCH_ROUND,
                mapOf("lesson" to lessonNumber, "round" to model.rounds, "attempts" to model.attempts)
            )
            model.dealNext()
        }
    }

    fun speakLeft(id: String) {
        // Only the Japanese side speaks: a Japanese voice reading a German gloss is unintelligible.
        if (soundOn) model.word(id)?.let { pronouncer.speak(it) }
    }

    val matchedColor = Theme.colors.correct
    val dragColor = Theme.colors.accent

    LessonScreenFrame(
        stringResource(R.string.match),
        onBack = { nav.pop() },
        modifier = modifier,
        center = {
            ScoreBadge(
                model.matched,
                model.attempts,
                caption = stringResource(
                    R.string.round_arg_arg_pairs,
                    model.rounds.toString(),
                    model.left.size.toString()
                )
            )
        },
        actions = { LessonSoundToggle(container) }
    ) {
        Column(
            Modifier.fillMaxSize().padding(16.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .onGloballyPositioned { boardOrigin = it.positionInRoot() }
            ) {
                // One grid row per pair: both tiles share its height, whatever is in them, so a long gloss on the
                // right never lets the two columns drift out of step.
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (i in 0 until maxOf(model.left.size, model.right.size)) {
                        Row(
                            Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                            horizontalArrangement = Arrangement.spacedBy(34.dp)
                        ) {
                            for (side in MatchModel.Side.entries) {
                                val tiles = if (side == MatchModel.Side.Left) model.left else model.right
                                Box(Modifier.weight(1f).fillMaxHeight()) {
                                    tiles.getOrNull(i)?.let { tile ->
                                        MatchTile(
                                            tile,
                                            side,
                                            i,
                                            model,
                                            flashId == tile.id,
                                            frames,
                                            onTap = {
                                                // Resolved *before* the pick: a pick that completes the round must
                                                // still speak the word that was tapped.
                                                if (side == MatchModel.Side.Left) speakLeft(tile.id)
                                                model.pick(side, i)
                                            },
                                            drag = DragHooks(
                                                onStart = { a ->
                                                    dragFrom = a
                                                    // The line starts by saying its word, like a tap would.
                                                    if (a.side == MatchModel.Side.Left) speakLeft(tile.id)
                                                },
                                                onMove = { dragPoint = it },
                                                onEnd = { from, at ->
                                                    dragFrom = null
                                                    dragPoint = null
                                                    if (model.wrong || model.roundCleared) return@DragHooks
                                                    val targetSide = if (from.side == MatchModel.Side.Left) {
                                                        MatchModel.Side.Right
                                                    } else {
                                                        MatchModel.Side.Left
                                                    }
                                                    val targetTiles = if (targetSide ==
                                                        MatchModel.Side.Left
                                                    ) {
                                                        model.left
                                                    } else {
                                                        model.right
                                                    }
                                                    // Where the finger let go decides; a release over nothing (or a
                                                    // cleared tile) just lets the line snap back, no penalty.
                                                    val hit = frames.entries.firstOrNull { (a, r) ->
                                                        a.side == targetSide && r.contains(at) &&
                                                            targetTiles.getOrNull(a.index)?.cleared == false
                                                    } ?: return@DragHooks
                                                    // Drop any tile still selected from an earlier tap: a pick left on
                                                    // the opposite side would resolve against the drag's first pick.
                                                    model.clearMiss()
                                                    model.pick(from.side, from.index, via = "drag")
                                                    model.pick(targetSide, hit.key.index, via = "drag")
                                                }
                                            )
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                // The lines draw over the board but swallow nothing: a Canvas takes no pointer input.
                Canvas(Modifier.fillMaxSize()) {
                    val id = flashId
                    if (id != null) {
                        val i = model.left.indexOfFirst { it.id == id }
                        val j = model.right.indexOfFirst { it.id == id }
                        val a = frames[Anchor(MatchModel.Side.Left, i)]
                        val b = frames[Anchor(MatchModel.Side.Right, j)]
                        if (a != null && b != null) {
                            drawLine(
                                matchedColor,
                                Offset(a.right - boardOrigin.x, a.center.y - boardOrigin.y),
                                Offset(b.left - boardOrigin.x, b.center.y - boardOrigin.y),
                                LINE_WIDTH_DP.dp.toPx(),
                                StrokeCap.Round
                            )
                        }
                    }
                    val from = dragFrom
                    val point = dragPoint
                    val rect = from?.let { frames[it] }
                    if (from != null && point != null && rect != null) {
                        val startX = if (from.side == MatchModel.Side.Left) rect.right else rect.left
                        drawLine(
                            dragColor,
                            Offset(startX - boardOrigin.x, rect.center.y - boardOrigin.y),
                            Offset(point.x - boardOrigin.x, point.y - boardOrigin.y),
                            LINE_WIDTH_DP.dp.toPx(),
                            StrokeCap.Round
                        )
                    }
                }
            }
            // The gesture is invisible until tried, so say it once, quietly. The tap still works.
            Text(
                stringResource(R.string.drag_a_word_to_its_meaning),
                style = Theme.text.caption,
                color = Theme.colors.inkTertiary
            )
        }
    }
}

private class DragHooks(
    val onStart: (Anchor) -> Unit,
    val onMove: (Offset) -> Unit,
    val onEnd: (Anchor, Offset) -> Unit
)

@Composable
private fun MatchTile(
    tile: MatchModel.Tile,
    side: MatchModel.Side,
    index: Int,
    model: MatchModel,
    flashing: Boolean,
    frames: MutableMap<Anchor, Rect>,
    onTap: () -> Unit,
    drag: DragHooks
) {
    val anchor = Anchor(side, index)
    val picked = (if (side == MatchModel.Side.Left) model.pickedLeft else model.pickedRight) == index
    val missed = picked && model.wrong
    val shape = Theme.rounded(Theme.Radius.chip)
    val shake = remember { Animatable(0f) }
    // A miss shakes the tile it happened on: over in a fraction of a second, before it feels like a telling-off.
    LaunchedEffect(missed) {
        if (!missed) return@LaunchedEffect
        repeat(2) {
            shake.animateTo(SHAKE_PX, tween(SHAKE_STEP_MILLIS))
            shake.animateTo(-SHAKE_PX, tween(SHAKE_STEP_MILLIS))
        }
        shake.animateTo(0f, tween(SHAKE_STEP_MILLIS))
    }
    // Selection stays an accent *border*; a miss takes the red it earned, a match the green (feedback only).
    val border = when {
        flashing -> Theme.colors.correct
        missed -> Theme.colors.wrong
        picked -> Theme.colors.accent
        else -> Theme.colors.line
    }
    val bw = if (picked || flashing) 2.dp else 0.dp
    // Cleared pairs keep their footprint and *empty*: tiles that reflow under a thumb make the next tap miss.
    val hidden = tile.cleared && !flashing
    Box(
        Modifier
            .fillMaxSize()
            .heightIn(min = 56.dp)
            .graphicsLayer { translationX = shake.value }
            .onGloballyPositioned { frames[anchor] = it.boundsInRoot() }
            .background(
                when {
                    flashing -> Theme.colors.wash(Theme.colors.correct)
                    hidden -> Theme.colors.line.copy(alpha = 0.35f)
                    else -> Theme.colors.surface
                },
                shape
            )
            .border(bw, border, shape)
            .clip(shape)
            .then(if (hidden) Modifier else Modifier.clickable(role = Role.Button, onClick = onTap))
            // The drag rides *beside* the tap: press-and-release is still a pick, movement becomes a line.
            .pointerInput(tile.id, hidden) {
                if (hidden) return@pointerInput
                var point = Offset.Zero
                var active = false
                detectDragGestures(
                    onDragStart = { start ->
                        active = !(model.wrong || model.roundCleared)
                        if (active) {
                            point = (frames[anchor]?.topLeft ?: Offset.Zero) + start
                            drag.onStart(anchor)
                            drag.onMove(point)
                        }
                    },
                    onDrag = { change, amount ->
                        if (active) {
                            change.consume()
                            point += amount
                            drag.onMove(point)
                        }
                    },
                    onDragEnd = {
                        if (active) drag.onEnd(anchor, point)
                        active = false
                    },
                    onDragCancel = {
                        if (active) drag.onEnd(anchor, Offset.Unspecified)
                        active = false
                    }
                )
            }
            .semantics { contentDescription = tile.text }
            .padding(horizontal = 7.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            tile.text,
            style = if (tile.isJapanese) {
                Theme.jp(
                    20.sp
                )
            } else {
                Theme.text.subheadline.copy(fontWeight = FontWeight.Medium)
            },
            color = Theme.colors.ink.let { if (hidden) it.copy(alpha = 0f) else it },
            textAlign = TextAlign.Center
        )
    }
}
