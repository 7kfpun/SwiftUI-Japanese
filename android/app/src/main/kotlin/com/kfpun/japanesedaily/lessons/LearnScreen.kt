package com.kfpun.japanesedaily.lessons

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.audio.LocalPronouncer
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.SwipeCard
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.cardPager
import com.kfpun.japanesedaily.ui.components.rememberCardPagerState

private const val TILE_COLUMNS = 5

/**
 * Learn (port of `LearnView`): rebuild a word's kana reading by tapping shuffled character tiles in order.
 * The deepest ask short of the ladder: producing a reading from nothing rather than choosing between options.
 * Correct the instant the built string equals the target, wrong the instant it stops being a prefix. An
 * entry too long for the tile cap shows the card with a message instead of a game.
 */
@Composable
fun LearnScreen(lessonNumber: Int, env: LessonsEnv, nav: LessonsNav, modifier: Modifier = Modifier) {
    val container = env.container
    val pronouncer = LocalPronouncer.current
    val model = remember(lessonNumber, env.language) { LearnModel(env.lesson(lessonNumber).entries) }
    val ordered = rememberPref(Pref.ordered, container)
    val soundOn = rememberPref(Pref.soundOn, container).value
    val showKanji = rememberPref(Pref.kanjiShown, container).value
    val showKana = rememberPref(Pref.kanaShown, container).value
    val showRomaji = rememberPref(Pref.romajiShown, container).value
    val showMeaning = rememberPref(Pref.translationShown, container).value

    // Set by the Random button so the page-turn knows the shuffle it is about to run was already logged
    // `via: button`: the button pages through the pager, so without this one tap would also count as a swipe.
    var shuffledByButton by remember { mutableStateOf(false) }

    fun autoPlay() {
        if (soundOn) pronouncer.speak(model.current)
    }

    /** Swipe/fling handler: next/prev (ordered) or shuffle (random). Speaks explicitly, not on index change. */
    fun turnPage(dir: Int) {
        if (ordered.value) {
            if (dir > 0) model.next() else model.prev()
            // Its own name: a page through the course order is not a reshuffle.
            Track.event(TrackEvents.LEARN_PAGE, mapOf("lesson" to lessonNumber, "forward" to (dir > 0)))
        } else {
            model.random()
            if (shuffledByButton) {
                shuffledByButton = false
            } else {
                Track.event(TrackEvents.LEARN_SHUFFLE, mapOf("lesson" to lessonNumber, "via" to "swipe"))
            }
        }
        autoPlay()
    }

    val pager = rememberCardPagerState(canPage = { model.vocab.size > 1 }, page = ::turnPage)

    LaunchedEffect(lessonNumber) {
        Track.screen(TrackScreens.LEARN, mapOf("lesson" to lessonNumber))
        container.prefs.markModeVisit(lessonNumber, LessonMode.LEARN)
        autoPlay()
    }
    LaunchedEffect(model.state) {
        if (model.state == AnswerState.InProgress) return@LaunchedEffect
        Track.event(
            TrackEvents.LEARN_ANSWER,
            mapOf("correct" to (model.state == AnswerState.Correct), "lesson" to lessonNumber)
        )
    }

    LessonScreenFrame("${model.index + 1} / ${model.vocab.size}", onBack = { nav.pop() }, modifier = modifier) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            CardOptionsBar(container)
            OrderPicker(ordered.value, ordered.set, TrackEvents.LEARN_ORDER_MODE)
            Box(Modifier.fillMaxWidth().heightIn(min = 260.dp)) {
                SwipeCard(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 260.dp)
                        .cardPager(pager)
                        .clickable { pronouncer.speak(model.current) },
                    hint = if (ordered.value) stringResource(R.string.swipe) else null
                ) {
                    Column(
                        Modifier.fillMaxWidth().padding(vertical = 24.dp, horizontal = 12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        // The assembled reading is the task, so it gets the space.
                        Row(
                            Modifier.heightIn(min = 70.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(
                                model.answer.joinToString(""),
                                style = Theme.jp(52.sp),
                                color = Theme.colors.ink,
                                maxLines = 1,
                                overflow = TextOverflow.Clip
                            )
                            if (model.state != AnswerState.InProgress) {
                                val ok = model.state == AnswerState.Correct
                                SymbolIcon(
                                    if (ok) R.drawable.ic_check_circle else R.drawable.ic_cancel,
                                    if (ok) Theme.colors.correct else Theme.colors.wrong,
                                    Theme.text.title2.fontSize.value.toInt()
                                )
                            }
                        }
                        if (showKana) {
                            Text(
                                model.target,
                                style = Theme.jp(30.sp),
                                color = Theme.colors.ink,
                                maxLines = 1
                            )
                        }
                        if (showKanji && model.current.displaysKanji) {
                            Text(model.current.kanji, style = Theme.jp(30.sp), color = Theme.colors.ink, maxLines = 1)
                        }
                        if (showRomaji) {
                            Text(
                                model.current.romaji,
                                style = Theme.text.body,
                                color = Theme.colors.inkSecondary
                            )
                        }
                        if (showMeaning) {
                            Text(
                                model.current.translation,
                                style = Theme.text.body,
                                color = Theme.colors.inkSecondary,
                                textAlign = TextAlign.Center
                            )
                        }
                    }
                }
            }
            if (model.isPlayable) {
                TileGrid(model)
            } else {
                Text(
                    stringResource(R.string.this_entry_is_a_full_sentence_no_tile_game),
                    style = Theme.text.footnote,
                    color = Theme.colors.inkSecondary
                )
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                if (model.state == AnswerState.Wrong) {
                    OutlineAction(stringResource(R.string.clear), null) { model.clearAnswer() }
                }
                Box(Modifier.weight(1f))
                if (!ordered.value) {
                    OutlineAction(stringResource(R.string.random), R.drawable.ic_shuffle) {
                        // Its own name: the picker's event says which mode the learner chose, this says how often
                        // they actually reshuffle inside it.
                        Track.event(TrackEvents.LEARN_SHUFFLE, mapOf("lesson" to lessonNumber, "via" to "button"))
                        shuffledByButton = true
                        pager.fling(1)
                    }
                }
            }
        }
    }
}

/** Explicit squares from the measured width: equal-weight columns with a 1:1 aspect divide space evenly. */
@Composable
private fun TileGrid(model: LearnModel) {
    val enabled = model.state == AnswerState.InProgress
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        model.tiles.chunked(TILE_COLUMNS).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (i in 0 until TILE_COLUMNS) {
                    val tile = row.getOrNull(i)
                    val shape = Theme.rounded(Theme.Radius.inset)
                    Box(
                        Modifier
                            .weight(1f)
                            .aspectRatio(1f)
                            .then(
                                if (tile == null) {
                                    Modifier
                                } else {
                                    Modifier
                                        .background(Theme.colors.surface, shape)
                                        .border(1.dp, Theme.colors.line, shape)
                                        .clickable(enabled = enabled, role = Role.Button) { model.tap(tile) }
                                }
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        if (tile != null) {
                            Text(tile.text, style = Theme.jp(Theme.text.title3), color = Theme.colors.ink)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun OutlineAction(text: String, @DrawableRes icon: Int?, onClick: () -> Unit) {
    val shape = Theme.rounded(Theme.Radius.pill)
    Row(
        Modifier
            .heightIn(min = 48.dp)
            .background(Theme.colors.surface, shape)
            .border(1.dp, Theme.colors.line, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        if (icon != null) SymbolIcon(icon, Theme.colors.accent, Theme.text.subheadline.fontSize.value.toInt())
        Text(text, style = Theme.text.subheadline.copy(fontWeight = FontWeight.Medium), color = Theme.colors.ink)
    }
}

/**
 * The field-visibility and sound chips above Learn's card. They read the same `Pref` keys and log the same
 * `toggle_field` event as the Show menu, so the screens cannot disagree about what a card shows.
 */
@Composable
private fun CardOptionsBar(container: AppContainer) {
    val kanji = rememberPref(Pref.kanjiShown, container)
    val kana = rememberPref(Pref.kanaShown, container)
    val romaji = rememberPref(Pref.romajiShown, container)
    val meaning = rememberPref(Pref.translationShown, container)
    val sound = rememberPref(Pref.soundOn, container)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterHorizontally)) {
        OptionChip(kanji, "kanji", stringResource(R.string.kanji)) { Text("漢", style = Theme.jp(Theme.text.callout)) }
        OptionChip(kana, "kana", stringResource(R.string.kana)) { Text("か", style = Theme.jp(Theme.text.callout)) }
        OptionChip(romaji, "romaji", stringResource(R.string.romaji)) { Text("A", style = Theme.text.callout) }
        OptionChip(meaning, "meaning", stringResource(R.string.meaning_19cd7d1)) {
            SymbolIcon(
                R.drawable.ic_tab_translate,
                if (meaning.value) Theme.colors.accent else Theme.colors.inkSecondary,
                Theme.text.callout.fontSize.value.toInt()
            )
        }
        OptionChip(sound, "sound", stringResource(R.string.read_automatically)) {
            SymbolIcon(
                if (sound.value) R.drawable.ic_volume_up else R.drawable.ic_volume_off,
                if (sound.value) Theme.colors.accent else Theme.colors.inkSecondary,
                Theme.text.callout.fontSize.value.toInt()
            )
        }
    }
}

@Composable
private fun OptionChip(pref: PrefValue<Boolean>, name: String, description: String, label: @Composable () -> Unit) {
    val shape = Theme.rounded(Theme.Radius.tick * 2)
    Box(
        Modifier
            .size(48.dp, 44.dp)
            .background(if (pref.value) Theme.colors.wash(Theme.colors.accent) else Theme.colors.canvas, shape)
            .clickable(role = Role.Switch) {
                pref.set(!pref.value)
                Track.event(TrackEvents.TOGGLE_FIELD, mapOf("field" to name, "shown" to !pref.value))
            }
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center
    ) {
        androidx.compose.runtime.CompositionLocalProvider(
            androidx.compose.material3.LocalContentColor provides
                if (pref.value) Theme.colors.accent else Theme.colors.inkSecondary,
            content = label
        )
    }
}
