package com.kfpun.japanesedaily.today

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.audio.LocalPronouncer
import com.kfpun.japanesedaily.audio.StopSoundOnExit
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.progress.Streak
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.lessons.BookmarkStars
import com.kfpun.japanesedaily.lessons.CardShowMenu
import com.kfpun.japanesedaily.lessons.FlipFaces
import com.kfpun.japanesedaily.lessons.Gating
import com.kfpun.japanesedaily.lessons.LessonPlayer
import com.kfpun.japanesedaily.lessons.LessonStanding
import com.kfpun.japanesedaily.lessons.LessonsEnv
import com.kfpun.japanesedaily.lessons.LocalPremium
import com.kfpun.japanesedaily.lessons.ReadMode
import com.kfpun.japanesedaily.lessons.VocabFace
import com.kfpun.japanesedaily.lessons.VocabFront
import com.kfpun.japanesedaily.lessons.flipped
import com.kfpun.japanesedaily.lessons.holdGestures
import com.kfpun.japanesedaily.lessons.rememberBookmarkTiers
import com.kfpun.japanesedaily.lessons.rememberFlip
import com.kfpun.japanesedaily.lessons.rememberLessonsEnv
import com.kfpun.japanesedaily.lessons.rememberPref
import com.kfpun.japanesedaily.ui.Adaptive
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.CardStackPeek
import com.kfpun.japanesedaily.ui.components.SwipeCard
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.accentPlate
import com.kfpun.japanesedaily.ui.components.cardPager
import com.kfpun.japanesedaily.ui.components.rememberCardPagerState

/** Where Today's taps lead: the host owns the tab bar and the Lessons stack. */
class TodayNav(
    /** To the lesson's mode list (not into the rung). */
    val openLesson: (Int) -> Unit,
    /** To the Lessons list: the lesson is behind the paywall. */
    val openLessonList: () -> Unit,
    val openProgress: () -> Unit
)

/**
 * The Today tab (port of `TodayView`): the words the next unpassed challenge can ask (its new words plus the review
 * window), as a deck to page through. **It writes nothing**: no stage, no result, no streak day; the only thing it
 * publishes is the widget's snapshot, which is not progress. **Never paywalled**: the deck walks all lessons
 * whatever Pro says; only the banner's destination respects the lock (it stops at the Lessons list).
 */
@Composable
fun TodayTab(nav: TodayNav, modifier: Modifier = Modifier) {
    val env = rememberLessonsEnv()
    if (env == null) {
        Box(modifier.fillMaxSize().background(Theme.colors.canvas))
        return
    }
    TodayScreen(env, nav, modifier)
}

@Composable
private fun TodayScreen(env: LessonsEnv, nav: TodayNav, modifier: Modifier) {
    StopSoundOnExit()
    val container = env.container
    val context = LocalContext.current
    val pronouncer = LocalPronouncer.current
    val isPremium = LocalPremium.current.isPremium
    val scope = rememberCoroutineScope()
    val soundOn = rememberPref(Pref.soundOn, container).value
    val results by remember(container) { container.progress.observeChallenges() }
        .collectAsStateOrNull()
    val streak by remember(container) { container.progress.observeStreak() }.collectAsStateOrNull()
    val tiers = rememberBookmarkTiers(container).value

    val deal = remember(results, env.language) {
        results?.let { rows ->
            TodayDeck.derive(rows.values, env::wordCount, { env.lesson(it).entries })
        }
    }
    val words = deal?.words.orEmpty()
    val dealKey = deal?.let { Triple(it.lesson, it.upNext, it.words.map(Vocab::id)) }

    var index by remember(dealKey) { mutableIntStateOf(0) }
    var deepest by remember(dealKey) { mutableIntStateOf(1) }
    var flipped by remember(dealKey) { mutableStateOf(false) }
    var holdPeek by remember { mutableStateOf(false) }
    var flippedThisCard by remember { mutableStateOf(false) }
    val detailPlayer = remember(pronouncer) { LessonPlayer(pronouncer, scope) }
    val angle = rememberFlip(flipped)
    val word = words.getOrNull(index)
    val lesson = deal?.lesson ?: 1

    fun readDetails(w: Vocab) {
        if (!soundOn) return
        pronouncer.stop()
        detailPlayer.stop()
        // Free users get the word leg: the spoken meaning is Read along's paid feature.
        detailPlayer.toggle(
            listOf(w),
            if (isPremium) ReadMode.WithExample else ReadMode.Japanese,
            env.language,
            loops = false
        )
    }

    fun setFlipped(on: Boolean, w: Vocab) {
        flipped = on
        if (on) {
            if (!flippedThisCard) {
                flippedThisCard = true
                Track.event(TrackEvents.TODAY_FLIP, mapOf("lesson" to lesson))
            }
            readDetails(w)
        } else {
            detailPlayer.stop()
        }
    }

    fun turnPage(dir: Int) {
        if (words.isEmpty()) return
        detailPlayer.stop()
        flipped = false
        holdPeek = false
        flippedThisCard = false
        index = (index + (if (dir > 0) 1 else -1) + words.size) % words.size
        // Explicit: every completed page-turn speaks the new word.
        if (soundOn) pronouncer.speak(words[index])
        deepest = maxOf(deepest, index + 1)
        Track.event(
            TrackEvents.TODAY_SWIPE,
            mapOf("lesson" to lesson, "depth" to deepest, "deck" to words.size, "for_challenge" to (deal?.upNext ?: 0))
        )
    }

    val pager = rememberCardPagerState(canPage = { words.size > 1 }, page = ::turnPage)

    // The widget cycles the same words: publish the deck whenever it changes (not progress, and not Room).
    LaunchedEffect(dealKey) {
        deal?.let { TodayWidgetUpdater.publish(context, TodayDeck.snapshot(it)) }
    }
    LaunchedEffect(dealKey != null) {
        if (dealKey == null) return@LaunchedEffect
        Track.screen(TrackScreens.TODAY, mapOf("lesson" to lesson))
        if (soundOn) words.getOrNull(index)?.let { pronouncer.speak(it) }
    }
    DisposableEffect(detailPlayer) { onDispose { detailPlayer.release() } }

    Column(modifier.fillMaxSize().background(Theme.colors.canvas).statusBarsPadding()) {
        TopBar(streak, nav.openProgress, container)
        Column(
            Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            if (deal != null) {
                WarmupBanner(deal) {
                    val earned = LessonStanding.earnedFirstGroup(results.orEmpty().values, env::wordCount)
                    val locked = Gating.isLocked(deal.lesson, isPremium, earned)
                    // `locked` on the event: a locked lesson lands on the list, not the rung the event names.
                    Track.event(
                        TrackEvents.TODAY_CHALLENGE_OPEN,
                        mapOf("lesson" to deal.lesson, "index" to deal.upNext, "locked" to locked)
                    )
                    if (locked) nav.openLessonList() else nav.openLesson(deal.lesson)
                }
                if (words.size > 1) DeckSegments(index, words.size)
            }
            if (deal != null && word != null) {
                Box(
                    Modifier.weight(
                        1f
                    ).fillMaxWidth().wrapContentHeight(Alignment.Top).heightIn(max = Adaptive.CARD_MAX_HEIGHT_DP.dp)
                ) {
                    CardStackPeek(minOf(2, maxOf(0, words.size - 1)), Modifier.fillMaxSize().padding(vertical = 12.dp))
                    // `cardPager` on the card, never on this Box: outside it the peek layers fling with the card.
                    SwipeCard(
                        Modifier
                            .fillMaxSize()
                            .padding(vertical = 12.dp)
                            .flipped(angle)
                            .cardPager(pager)
                            .holdGestures(
                                onTap = { if (flipped) readDetails(word) else pronouncer.speak(word) },
                                onHold = {
                                    if (!flipped) {
                                        holdPeek = true
                                        setFlipped(true, word)
                                    }
                                },
                                onHoldEnd = {
                                    if (holdPeek) {
                                        holdPeek = false
                                        setFlipped(false, word)
                                    }
                                },
                                onDoubleTap = {
                                    holdPeek = false
                                    setFlipped(!flipped, word)
                                }
                            ),
                        hint = if (words.size > 1 && !flipped) stringResource(R.string.swipe) else null
                    ) {
                        Box(Modifier.fillMaxSize().padding(horizontal = 18.dp).padding(top = 18.dp, bottom = 4.dp)) {
                            FlipFaces(
                                angle,
                                front = {
                                    CardFront(
                                        word,
                                        deal,
                                        env,
                                        tiers,
                                        onSpeak = { pronouncer.speak(word) },
                                        onDetails = {
                                            holdPeek = false
                                            setFlipped(!flipped, word)
                                        }
                                    )
                                },
                                back = {
                                    VocabFace(word, onSpeakExample = {
                                        pronouncer.speakExample(word)
                                        Track.event(
                                            TrackEvents.PLAY_EXAMPLE,
                                            mapOf("lesson" to word.lesson, "surface" to "today")
                                        )
                                    })
                                }
                            )
                        }
                    }
                }
            } else {
                Box(Modifier.weight(1f).fillMaxWidth())
            }
        }
    }
}

@Composable
private fun <T> kotlinx.coroutines.flow.Flow<T>.collectAsStateOrNull() =
    androidx.compose.runtime.produceState<T?>(null, this) { collect { value = it } }

@Composable
private fun TopBar(streak: Streak?, onStreak: () -> Unit, container: com.kfpun.japanesedaily.data.AppContainer) {
    Box(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 12.dp)) {
        Box(Modifier.align(Alignment.CenterStart).widthIn(min = 48.dp)) {
            if (streak != null && streak.current > 0) {
                StreakBadge(streak) {
                    Track.event(
                        TrackEvents.STREAK_OPEN,
                        mapOf("streak" to streak.current, "studied_today" to streak.studiedToday)
                    )
                    onStreak()
                }
            }
        }
        Text(
            stringResource(R.string.today),
            style = Theme.title(Theme.text.headline),
            color = Theme.colors.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 64.dp)
        )
        Box(Modifier.align(Alignment.CenterEnd)) { CardShowMenu(container, sound = true) }
    }
}

/** The streak on the surface it measures: dim flame while today is open, lit once it is done. */
@Composable
private fun StreakBadge(streak: Streak, onClick: () -> Unit) {
    val label = stringResource(R.string.arg_day_streak, streak.current.toString())
    val hint = if (streak.atRisk) stringResource(R.string.study_today_to_keep_your_streak) else ""
    Row(
        Modifier
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(24.dp))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 8.dp)
            .semantics { contentDescription = if (hint.isEmpty()) label else "$label. $hint" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        val tint = if (streak.studiedToday) Theme.colors.streak else Theme.colors.streak.copy(alpha = OPEN_FLAME_ALPHA)
        SymbolIcon(R.drawable.ic_local_fire, tint, Theme.text.footnote.fontSize.value.toInt())
        Text(
            streak.current.toString(),
            style = Theme.text.footnote.copy(fontWeight = FontWeight.Bold),
            color = Theme.colors.streak
        )
    }
}

private const val OPEN_FLAME_ALPHA = 0.55f

/**
 * Where you are and the way in. `hasNext` decides the words, not just the icon: a learner who has passed everything
 * is reviewing, not preparing, and the banner must not promise a rung that is gone.
 */
@Composable
private fun WarmupBanner(deal: TodayDeal, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .accentPlate()
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            Modifier.size(36.dp).background(Theme.colors.accent, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            SymbolIcon(
                if (deal.hasNext) R.drawable.ic_flag else R.drawable.ic_check_circle,
                Theme.colors.onAccent,
                Theme.text.subheadline.fontSize.value.toInt()
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                if (deal.hasNext) {
                    stringResource(R.string.warming_up_for_challenge_arg, deal.upNext.toString())
                } else {
                    stringResource(R.string.all_challenges_passed)
                },
                style = Theme.title(Theme.text.subheadline),
                color = Theme.colors.ink
            )
            Text(
                if (deal.hasNext) {
                    stringResource(R.string.these_arg_words_are_exactly_what_it_will_ask, deal.words.size.toString())
                } else {
                    stringResource(R.string.reviewing_the_last_words_of_lesson_arg, deal.lesson.toString())
                },
                style = Theme.text.caption,
                color = Theme.colors.accent
            )
        }
        SymbolIcon(R.drawable.ic_chevron_right, Theme.colors.accent, Theme.text.caption.fontSize.value.toInt())
    }
}

/** One slim segment per card: filled for seen, faint for what is still to come, with the position beside it. */
@Composable
private fun DeckSegments(index: Int, count: Int) {
    val label = stringResource(R.string.word_arg_of_arg, (index + 1).toString(), count.toString())
    Row(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            repeat(count) { i ->
                Box(
                    Modifier
                        .weight(1f)
                        .heightIn(min = 4.dp, max = 4.dp)
                        .background(if (i <= index) Theme.colors.accent else Theme.colors.line, CircleShape)
                )
            }
        }
        Text("${index + 1} / $count", style = Theme.title(Theme.text.caption), color = Theme.colors.inkSecondary)
    }
}

@Composable
private fun CardFront(
    word: Vocab,
    deal: TodayDeal,
    env: LessonsEnv,
    tiers: Map<String, Int>,
    onSpeak: () -> Unit,
    onDetails: () -> Unit
) {
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            // The chip states the deck's contract: these words are the test.
            Text(
                if (deal.hasNext) {
                    stringResource(R.string.asked_in_challenge_arg, deal.upNext.toString())
                } else {
                    stringResource(R.string.review_these)
                },
                style = Theme.text.caption.copy(fontWeight = FontWeight.Medium),
                color = Theme.colors.accent,
                modifier = Modifier
                    .weight(1f, fill = false)
                    .background(Theme.colors.wash(Theme.colors.accent), CircleShape)
                    .padding(horizontal = 11.dp, vertical = 5.dp)
            )
            Box(Modifier.weight(1f))
            // A visible control is what tells anyone the card can talk.
            val hear = stringResource(R.string.tap_to_hear_it)
            Box(
                Modifier
                    .size(44.dp)
                    .background(Theme.colors.ink, CircleShape)
                    .clip(CircleShape)
                    .clickable(role = Role.Button, onClick = onSpeak)
                    .semantics { contentDescription = hear },
                contentAlignment = Alignment.Center
            ) {
                SymbolIcon(R.drawable.ic_volume_up, Theme.colors.surface, Theme.text.body.fontSize.value.toInt())
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth().padding(vertical = 24.dp)) {
            VocabFront(word, env.container, Modifier.fillMaxWidth().align(Alignment.Center))
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            BookmarkStars(word, tiers, env.container)
            Box(Modifier.weight(1f))
            val details = stringResource(R.string.details)
            val hint = stringResource(R.string.double_tap_for_details)
            Box(
                Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .clickable(role = Role.Button, onClick = onDetails)
                    .semantics { contentDescription = "$details. $hint" },
                contentAlignment = Alignment.Center
            ) {
                SymbolIcon(R.drawable.ic_info, Theme.colors.inkSecondary, Theme.text.title3.fontSize.value.toInt())
            }
        }
    }
}
