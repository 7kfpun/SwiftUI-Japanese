package com.kfpun.japanesedaily.ui.components

import androidx.annotation.DrawableRes
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.kana.FlashDeck
import com.kfpun.japanesedaily.ui.Theme

/**
 * The shared Tinder-style flashcard screen (iOS `FlashcardScreen`): drag and tap gestures, the Again and Got it
 * chips, the status count, auto-play, reveal and the done panel. Callers supply only what is type-specific: the
 * card [face], an [id] (for auto-play change detection), the [speak] action and the reveal and summary text.
 *
 * A swipe is a self-assessment here (right means "knew it"), and the screen writes nothing: no result, no
 * streak day. Events are `<trackName>_reveal|grade|done|restart`, merged with [trackParams].
 */
@Composable
fun <T> FlashcardScreen(
    deck: FlashDeck<T>,
    id: (T) -> String,
    speak: (T) -> Unit,
    soundOn: Boolean,
    onToggleSound: () -> Unit,
    onBack: () -> Unit,
    summary: @Composable (Int) -> String,
    trackName: String?,
    modifier: Modifier = Modifier,
    trackParams: Map<String, Any> = emptyMap(),
    face: @Composable (T, Boolean) -> Unit
) {
    var revealed by remember { mutableStateOf(false) }
    var animating by remember { mutableStateOf(false) }
    val swipe = rememberCardSwipeState()
    val current = deck.current
    val currentId = current?.let(id)

    // Auto-play on appear, on every new card and when the sound is switched on.
    LaunchedEffect(currentId, soundOn) {
        if (soundOn && current != null) speak(current)
    }

    fun grade(right: Boolean, via: String) {
        if (animating) return
        animating = true
        if (trackName != null) {
            Track.event("${trackName}_grade", trackParams + mapOf("known" to right, "via" to via))
        }
        swipe.fling(toRight = right) {
            if (right) deck.know() else deck.dontKnow()
            revealed = false
            swipe.reset()
            animating = false
            if (deck.isDone && trackName != null) {
                Track.event("${trackName}_done", trackParams + mapOf("total" to deck.total))
            }
        }
    }

    Column(modifier.fillMaxSize()) {
        ScreenBar(
            onBack = onBack,
            center = {
                ToolbarStatus {
                    IconCount(R.drawable.ic_check, deck.mastered, Theme.colors.correct, Theme.text.footnote)
                    IconCount(R.drawable.ic_view_carousel, deck.remaining, Theme.colors.accent, Theme.text.footnote)
                    Text(
                        "/ ${deck.total}",
                        style = Theme.text.footnote.copy(fontWeight = FontWeight.Medium),
                        color = Theme.colors.inkSecondary
                    )
                }
            },
            actions = { SoundToggle(soundOn, onToggleSound) }
        )
        Column(
            Modifier.weight(1f).fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (current != null) {
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    // The peek stack is a static backdrop: only the top card moves.
                    CardStackPeek(count = deck.peek(2).size, modifier = Modifier.fillMaxSize())
                    SwipeCard(
                        Modifier
                            .fillMaxSize()
                            .cardSwipe(swipe, canDrag = { !animating }, canCommit = { !animating }) {
                                grade(it, "swipe")
                            }
                            .clickable(role = Role.Button) { speak(current) },
                        drag = { swipe.offset },
                        leftStamp = StampSpec(R.drawable.ic_close, Theme.colors.wrong),
                        rightStamp = StampSpec(R.drawable.ic_check, Theme.colors.correct)
                    ) {
                        Column(
                            Modifier.padding(24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(14.dp)
                        ) {
                            face(current, revealed)
                            if (!revealed) {
                                RevealButton {
                                    if (trackName != null) Track.event("${trackName}_reveal", trackParams)
                                    revealed = true
                                }
                            }
                        }
                    }
                }
                Graders(onAgain = { grade(false, "tap") }, onGotIt = { grade(true, "tap") })
            } else {
                DeckDone(summary(deck.total)) {
                    if (trackName !=
                        null
                    ) {
                        Track.event("${trackName}_restart", trackParams + mapOf("total" to deck.total))
                    }
                    deck.restart()
                    revealed = false
                    swipe.reset()
                }
            }
        }
    }
}

@Composable
private fun RevealButton(onClick: () -> Unit) {
    Row(
        Modifier
            .heightIn(min = 48.dp)
            .accentPlate(Theme.Radius.pill)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SymbolIcon(R.drawable.ic_visibility, Theme.colors.accent, Theme.text.subheadline.fontSize.value.toInt())
        Text(stringResource(R.string.reveal), style = Theme.text.subheadline, color = Theme.colors.accent)
    }
}

/** The grade chips double as swipe legends: arrows on the outer edges point the way to swipe. */
@Composable
private fun Graders(onAgain: () -> Unit, onGotIt: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Grader(R.drawable.ic_arrow_back, stringResource(R.string.again), Theme.colors.wrong, leading = true, onAgain)
        Grader(
            R.drawable.ic_arrow_forward,
            stringResource(R.string.got_it),
            Theme.colors.correct,
            leading = false,
            onGotIt
        )
    }
}

@Composable
private fun RowScope.Grader(
    @DrawableRes icon: Int,
    label: String,
    color: Color,
    leading: Boolean,
    onClick: () -> Unit
) {
    Row(
        Modifier
            .weight(1f)
            .heightIn(min = 52.dp)
            .choiceChip(color)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val size = Theme.text.headline.fontSize.value.toInt()
        if (leading) SymbolIcon(icon, color, size)
        Text(label, style = Theme.title(Theme.text.headline), color = color, textAlign = TextAlign.Center)
        if (!leading) SymbolIcon(icon, color, size)
    }
}

@Composable
private fun DeckDone(summary: String, onRestart: () -> Unit) {
    Column(
        Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically)
    ) {
        SymbolIcon(R.drawable.ic_check_circle, Theme.colors.streak, DONE_ICON_SP)
        Text(summary, style = Theme.title(Theme.text.title2), color = Theme.colors.ink, textAlign = TextAlign.Center)
        Row(
            Modifier
                .heightIn(min = 52.dp)
                .choiceChip(Theme.colors.accent)
                .clickable(role = Role.Button, onClick = onRestart)
                .padding(horizontal = 28.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                stringResource(R.string.restart),
                style = Theme.title(Theme.text.headline),
                color = Theme.colors.accent
            )
        }
    }
}

private const val DONE_ICON_SP = 72
