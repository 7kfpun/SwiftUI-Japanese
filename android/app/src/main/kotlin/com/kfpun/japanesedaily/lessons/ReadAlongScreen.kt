package com.kfpun.japanesedaily.lessons

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.PaywallSource
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.audio.LocalPronouncer
import com.kfpun.japanesedaily.audio.PlaybackRates
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.cardChrome

/** "1x", "1.2x": a whole number drops its decimal. */
fun rateLabel(r: Double): String = if (r == Math.rint(r)) "${r.toInt()}×" else "$r×"

/**
 * Read along (port of `ReadAlongView`): the whole lesson read out as a *player* rather than a list that
 * happens to be talking. "Japanese only" is free on every lesson; "+ Meaning" and "+ Example" are premium
 * and, without it, preview [Gating.FREE_MEANING_PREVIEW] words and then open the paywall; the speed dial is
 * premium; only subscribers loop. [cutKey] is the Vocab List cut this was opened from.
 */
@Composable
fun ReadAlongScreen(
    lessonNumber: Int,
    cutKey: String,
    env: LessonsEnv,
    nav: LessonsNav,
    modifier: Modifier = Modifier
) {
    val container = env.container
    val isPremium = LocalPremium.current.isPremium
    val openPaywall = LocalOpenPaywall.current
    val pronouncer = LocalPronouncer.current
    val scope = rememberCoroutineScope()
    val entries = remember(lessonNumber, env.language) { env.lesson(lessonNumber).entries }
    val tiers by rememberBookmarkTiers(container)
    val words =
        remember(entries, cutKey) {
            cutWords(VocabCut.of(cutKey), entries, { v: com.kfpun.japanesedaily.data.vocab.Vocab ->
                container.practice.stage(v.id)
            }, tiers)
        }
    val player = remember(pronouncer) { LessonPlayer(pronouncer, scope) }
    val storedRate = rememberPref(Pref.playbackRate, container)
    val effectiveRate = Gating.rate(storedRate.value, isPremium)

    fun start(mode: ReadMode) {
        val limit = Gating.wordsToRead(mode, words.size, isPremium)
        val list = words.take(limit)
        val isPreview = limit < words.size
        val loops = Gating.loopsForever(mode, isPremium)
        player.onFinished = if (isPreview) {
            {
                Track.event(TrackEvents.LOCKED_READ_ALL, mapOf("lesson" to lessonNumber, "heard" to list.size))
                openPaywall.open(PaywallSource.READ_ALL_MEANINGS, lessonNumber)
            }
        } else {
            null
        }
        player.onLap = if (loops) {
            { lap ->
                Track.event(
                    TrackEvents.READ_ALL_LOOP,
                    mapOf(
                        "lesson" to lessonNumber,
                        "mode" to mode.key,
                        "lap" to lap
                    )
                )
            }
        } else {
            null
        }
        player.rate = effectiveRate
        val wasPlayingSameMode = player.isPlaying && player.mode == mode
        player.toggle(list, mode, env.language, loops)
        if (player.isPlaying) {
            Track.event(
                TrackEvents.READ_ALL,
                mapOf("lesson" to lessonNumber, "mode" to mode.key, "preview" to isPreview)
            )
        } else if (wasPlayingSameMode) {
            Track.event(TrackEvents.READ_ALL_STOP, mapOf("lesson" to lessonNumber, "mode" to mode.key))
        }
    }

    LaunchedEffect(lessonNumber) {
        Track.screen(TrackScreens.READ_ALONG, mapOf("lesson" to lessonNumber))
        container.prefs.markModeVisit(lessonNumber, LessonMode.READ_ALONG)
        if (!player.isPlaying) start(ReadMode.Japanese)
    }
    DisposableEffect(player) { onDispose { player.release() } }

    val listState = rememberLazyListState()
    LaunchedEffect(player.currentIndex) {
        val i = player.currentIndex
        if (i != null && i < words.size) listState.animateScrollToItem(i)
    }

    LessonScreenFrame(
        stringResource(R.string.read_along),
        onBack = { nav.pop() },
        modifier = modifier,
        actions = {
            // Pause, not mute: this screen needs a way to stop without leaving it.
            ToolbarButton(
                if (player.isPaused) R.drawable.ic_play else R.drawable.ic_pause,
                stringResource(if (player.isPaused) R.string.resume else R.string.pause),
                {
                    val pausing = !player.isPaused
                    Track.event(TrackEvents.READ_ALL_PAUSE, mapOf("lesson" to lessonNumber, "paused" to pausing))
                    if (pausing) player.pause() else player.resume()
                },
                enabled = player.isPlaying
            )
        }
    ) {
        Column(Modifier.fillMaxWidth().padding(top = 12.dp)) {
            PlayerCard(
                player = player,
                words = words,
                isPremium = isPremium,
                hasExamples = container.vocab.hasExamples,
                storedRate = storedRate.value,
                start = ::start,
                onRate = {
                    storedRate.set(it)
                    player.rate = it
                    Track.event(TrackEvents.READ_ALL_SPEED, mapOf("rate" to it, "lesson" to lessonNumber))
                },
                onLockedSpeed = {
                    Track.event(TrackEvents.LOCKED_SPEED, mapOf("lesson" to lessonNumber))
                    openPaywall.open(PaywallSource.PLAYBACK_SPEED, lessonNumber)
                },
                modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 14.dp)
            )
            SectionLabel(stringResource(R.string.playlist), Modifier.padding(horizontal = 20.dp).padding(bottom = 6.dp))
            LazyColumn(
                Modifier.fillMaxWidth(),
                state = listState,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 16.dp,
                    end = 16.dp,
                    bottom = 20.dp
                ),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                itemsIndexed(words, key = { _, w -> w.id }) { i, word ->
                    val isCurrent = player.currentIndex == i && player.isPlaying
                    PlaylistRow(i, word, isCurrent, player, tiers, container, isPremium) {
                        if (player.isPlaying && i < player.count) {
                            Track.event(TrackEvents.READ_ALL_JUMP, mapOf("lesson" to lessonNumber, "index" to i))
                            player.play(i)
                        } else if (!player.isPlaying) {
                            pronouncer.speak(word)
                        }
                    }
                }
            }
        }
    }
}

/** The player card: the current word large, "Word n of m", the speed pill, the mode segments and the caption. */
@Composable
private fun PlayerCard(
    player: LessonPlayer,
    words: List<com.kfpun.japanesedaily.data.vocab.Vocab>,
    isPremium: Boolean,
    hasExamples: Boolean,
    storedRate: Double,
    start: (ReadMode) -> Unit,
    onRate: (Double) -> Unit,
    onLockedSpeed: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier.fillMaxWidth().cardChrome(Theme.Radius.deck, lifted = true).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            PlayingBars(player.isPlaying)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    player.currentWord?.kana ?: words.firstOrNull()?.kana.orEmpty(),
                    style = Theme.jp(28.sp),
                    color = Theme.colors.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    stringResource(
                        R.string.word_arg_of_arg,
                        ((player.currentIndex ?: 0) + 1).toString(),
                        maxOf(player.count, words.size).toString()
                    ),
                    style = Theme.text.caption,
                    color = Theme.colors.inkSecondary
                )
            }
            SpeedPill(isPremium, storedRate, onRate, onLockedSpeed)
        }
        ModePicker(player, isPremium, hasExamples, start)
        Text(
            stringResource(
                when (player.mode) {
                    ReadMode.Japanese -> R.string.japanese_only
                    ReadMode.WithMeaning -> R.string.each_word_then_its_meaning
                    ReadMode.WithExample -> R.string.each_word_and_meaning_then_a_sentence_and_its_meaning
                }
            ),
            style = Theme.text.caption2,
            color = Theme.colors.inkTertiary
        )
    }
}

/** The speed dial: a menu for subscribers, a locked pill (opening the paywall) for everyone else. */
@Composable
private fun SpeedPill(isPremium: Boolean, stored: Double, onRate: (Double) -> Unit, onLocked: () -> Unit) {
    var open by remember { mutableStateOf(false) }
    val label = stringResource(R.string.playback_speed)
    Box {
        Row(
            Modifier
                .heightIn(min = 44.dp)
                .background(Theme.colors.canvas, CircleShape)
                .clickable(role = Role.Button) { if (isPremium) open = true else onLocked() }
                .padding(horizontal = 12.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                rateLabel(if (isPremium) stored else PlaybackRates.NORMAL),
                style = Theme.text.subheadline.copy(fontWeight = FontWeight.SemiBold),
                color = Theme.colors.ink
            )
            if (!isPremium) {
                SymbolIcon(R.drawable.ic_lock, Theme.colors.streak, Theme.text.caption2.fontSize.value.toInt())
            }
        }
        DropdownMenu(open, { open = false }, containerColor = Theme.colors.surface) {
            Text(
                label,
                style = Theme.text.caption,
                color = Theme.colors.inkSecondary,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
            )
            for (r in PlaybackRates.choices) {
                DropdownMenuItem(
                    text = { Text(rateLabel(r), style = Theme.text.body, color = Theme.colors.ink) },
                    leadingIcon = {
                        if (r ==
                            stored
                        ) {
                            SymbolIcon(
                                R.drawable.ic_check,
                                Theme.colors.accent,
                                Theme.text.body.fontSize.value.toInt()
                            )
                        }
                    },
                    onClick = {
                        open = false
                        onRate(r)
                    }
                )
            }
        }
    }
}

/**
 * The mode on the surface, as a cumulative segmented track: Word / + Meaning / + Example, switchable mid-run,
 * with a lock naming the gate before the tap (every non-subscriber, not only locked lessons).
 */
@Composable
private fun ModePicker(player: LessonPlayer, isPremium: Boolean, hasExamples: Boolean, start: (ReadMode) -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(Theme.colors.canvas, Theme.rounded(Theme.Radius.row)).padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        ModeSegment(R.string.word, ReadMode.Japanese, player, isPremium, start, Modifier.weight(1f))
        ModeSegment(R.string.meaning_e4f082d, ReadMode.WithMeaning, player, isPremium, start, Modifier.weight(1f))
        if (hasExamples) {
            ModeSegment(
                R.string.example,
                ReadMode.WithExample,
                player,
                isPremium,
                start,
                Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun ModeSegment(
    title: Int,
    mode: ReadMode,
    player: LessonPlayer,
    isPremium: Boolean,
    start: (ReadMode) -> Unit,
    modifier: Modifier
) {
    val selected = player.mode == mode && player.isPlaying
    val shape = Theme.rounded(Theme.Radius.inset)
    Row(
        modifier
            .heightIn(min = 44.dp)
            .then(
                if (selected) {
                    Modifier.background(
                        Theme.colors.surface,
                        shape
                    ).border(1.dp, Theme.colors.line, shape)
                } else {
                    Modifier
                }
            )
            .clickable(role = Role.Button) { start(mode) }
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            stringResource(title),
            style = Theme.text.subheadline.copy(fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal),
            color = if (selected) Theme.colors.ink else Theme.colors.inkSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        if (mode.readsBeyondTheWord && !isPremium) {
            SymbolIcon(R.drawable.ic_lock, Theme.colors.streak, Theme.text.caption2.fontSize.value.toInt())
        }
    }
}

/** One playlist row; the playing row expands to add romaji, and in the example mode every row carries its sentence. */
@Composable
private fun PlaylistRow(
    i: Int,
    word: com.kfpun.japanesedaily.data.vocab.Vocab,
    isCurrent: Boolean,
    player: LessonPlayer,
    tiers: Map<String, Int>,
    container: com.kfpun.japanesedaily.data.AppContainer,
    isPremium: Boolean,
    onJump: () -> Unit
) {
    val shape = Theme.rounded(Theme.Radius.row)
    val gutter = 22.dp
    val gap = 12.dp
    Column(
        Modifier
            .fillMaxWidth()
            .background(Theme.colors.surface, shape)
            .border(if (isCurrent) 2.dp else 1.dp, if (isCurrent) Theme.colors.accent else Theme.colors.line, shape)
            .padding(horizontal = 14.dp, vertical = 11.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier.weight(1f).heightIn(min = 44.dp).clickable(role = Role.Button, onClick = onJump),
                horizontalArrangement = Arrangement.spacedBy(gap),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(Modifier.width(gutter), contentAlignment = Alignment.Center) {
                    if (isCurrent) {
                        PlayingBars(true)
                    } else {
                        Text((i + 1).toString(), style = Theme.text.footnote, color = Theme.colors.inkSecondary)
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        word.kana,
                        style = Theme.jp((if (isCurrent) 20 else 17).sp),
                        color = Theme.colors.ink,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        word.translation,
                        style = Theme.text.caption,
                        color = Theme.colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            BookmarkStars(word, tiers, container)
        }
        if (isCurrent) {
            Row(Modifier.padding(start = gutter + gap), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (word.romaji.isNotEmpty()) {
                    Text(word.romaji, style = Theme.text.caption, color = Theme.colors.inkSecondary)
                }
                if (!isPremium && !player.mode.readsBeyondTheWord) {
                    Text(
                        stringResource(R.string.pro_reads_the_meaning_too),
                        style = Theme.text.caption2,
                        color = Theme.colors.streak
                    )
                }
            }
        }
        val example = word.example
        if (player.mode == ReadMode.WithExample && example != null) {
            ExampleSentenceView(
                example,
                Modifier
                    .padding(start = gutter + gap)
                    .fillMaxWidth()
                    .background(Theme.colors.canvas, Theme.rounded(Theme.Radius.inset))
                    .padding(10.dp),
                translation = word.exampleTranslation,
                translationStyle = Theme.text.caption2
            )
        }
    }
}
