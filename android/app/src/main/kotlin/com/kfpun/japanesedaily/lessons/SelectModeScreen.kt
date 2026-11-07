package com.kfpun.japanesedaily.lessons

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.ads.AdSlot
import com.kfpun.japanesedaily.ads.UseBannerSlot
import com.kfpun.japanesedaily.analytics.PaywallSource
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.IconWell
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.cardChrome

/** The mode keys: the analytics name, the visit key and the route all agree. */
object LessonMode {
    const val PRACTICE = "practice"
    const val VOCAB_LIST = "vocab_list"
    const val FLASHCARDS = "flashcards"
    const val MATCH = "match"
    const val LEARN = "learn"
    const val READ_ALONG = "read_along"
}

/**
 * The lesson screen (port of `SelectModeView`, design 2a): a per-word standing bar, the Practice hero, the
 * other modes as status-carrying tiles, and the Challenge ladder entry.
 *
 * **This is the one place lesson gating is enforced for the practice modes and the ladder**: a locked tile
 * (the hero and every rung chip included) opens the paywall instead of navigating, so no practice screen
 * polices access itself. Vocab List is the exception and is free on every lesson.
 */
@Composable
fun SelectModeScreen(lessonNumber: Int, env: LessonsEnv, nav: LessonsNav, modifier: Modifier = Modifier) {
    val isPremium = LocalPremium.current.isPremium
    val openPaywall = LocalOpenPaywall.current
    UseBannerSlot(AdSlot.SelectMode)
    val container = env.container
    val lesson = remember(lessonNumber, env.language) { env.lesson(lessonNumber) }
    val results by remember { container.progress.observeChallenges() }.collectAsState(emptyMap())
    val earned = remember(results) { LessonStanding.earnedFirstGroup(results.values, env::wordCount) }
    val locked = Gating.isLocked(lessonNumber, isPremium, earned)
    val byIndex = remember(results, lessonNumber) {
        results.values.filter { it.lesson == lessonNumber }.associateBy { it.index }
    }
    val previousCleared by produceState(true, results, lessonNumber) {
        value = container.progress.previousLessonCleared(lessonNumber)
    }
    // Re-read when the screen appears: a mode just left has marked itself visited.
    val visits by produceState(emptySet<String>(), lessonNumber) { value = container.prefs.modeVisits(lessonNumber) }
    val counts = container.practice.counts(lesson.entries)

    LaunchedEffect(lessonNumber) { Track.screen(TrackScreens.SELECT_MODE, mapOf("lesson" to lessonNumber)) }

    fun paywall(mode: String) {
        Track.event(TrackEvents.LOCKED_MODE, mapOf("mode" to mode, "lesson" to lessonNumber))
        openPaywall.open(PaywallSource.LOCKED_MODE, lessonNumber)
    }

    LessonScreenFrame(stringResource(R.string.lesson_arg, lessonNumber.toString()), onBack = {
        nav.pop()
    }, modifier = modifier, showBack = !LocalTwoPane.current) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp)
        ) {
            Standing(counts.memorized, counts.recognized, counts.unseen, lesson.entries.size)
            PracticeHero(counts, lesson.entries.size, locked) {
                if (locked) paywall(LessonMode.PRACTICE) else nav.push(LessonRoute.Practice(lessonNumber))
            }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionLabel(stringResource(R.string.other_ways_to_practice))
                // A grid rather than four rows: the modes are peers, and each tile takes its row's height so a
                // long German or Burmese description grows both tiles together instead of staggering them.
                Row(Modifier.height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    // Vocab List is free on every lesson: browsing and search stay open.
                    ModeTile(
                        LessonMode.VOCAB_LIST,
                        R.drawable.ic_list,
                        R.string.vocab_list,
                        R.string.browse_hear_all_words,
                        gated = false,
                        visited = LessonMode.VOCAB_LIST in visits,
                        Modifier.weight(1f).fillMaxHeight()
                    ) { nav.push(LessonRoute.VocabList(lessonNumber)) }
                    ModeTile(
                        LessonMode.FLASHCARDS,
                        R.drawable.ic_cards,
                        R.string.flashcards,
                        R.string.swipe_through_the_words,
                        locked,
                        LessonMode.FLASHCARDS in visits,
                        Modifier.weight(1f).fillMaxHeight()
                    ) { if (locked) paywall(LessonMode.FLASHCARDS) else nav.push(LessonRoute.Flashcards(lessonNumber)) }
                }
                Row(Modifier.height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ModeTile(
                        LessonMode.MATCH,
                        R.drawable.ic_link,
                        R.string.match,
                        R.string.pair_each_word_with_its_meaning,
                        locked,
                        LessonMode.MATCH in visits,
                        Modifier.weight(1f).fillMaxHeight()
                    ) { if (locked) paywall(LessonMode.MATCH) else nav.push(LessonRoute.Match(lessonNumber)) }
                    ModeTile(
                        LessonMode.LEARN,
                        R.drawable.ic_grid_view,
                        R.string.learn,
                        R.string.rebuild_the_reading_from_tiles,
                        locked,
                        LessonMode.LEARN in visits,
                        Modifier.weight(1f).fillMaxHeight()
                    ) { if (locked) paywall(LessonMode.LEARN) else nav.push(LessonRoute.Learn(lessonNumber)) }
                }
            }
            ChallengeSection(lesson, byIndex, previousCleared, locked, onPaywall = {
                openPaywall.open(it, lessonNumber)
            })
            EarnHint(lessonNumber, earned, isPremium, results.values, env)
        }
    }
}

/** One proportional bar over the lesson's words, with the three counts spelled out under it. */
@Composable
private fun Standing(memorized: Int, recognized: Int, unseen: Int, wordCount: Int) {
    val total = maxOf(wordCount, 1).toFloat()
    val label = stringResource(
        R.string.arg_memorized_arg_recognized_arg_unseen,
        memorized.toString(),
        recognized.toString(),
        unseen.toString()
    )
    Column(
        Modifier.semantics(mergeDescendants = true) {
            contentDescription = label
        },
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(Modifier.fillMaxWidth().height(6.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            // Weights, so a segment never overflows the bar however the counts fall.
            segment(memorized, total, Theme.colors.accent)
            segment(recognized, total, Theme.colors.accent.copy(alpha = 0.35f))
            segment(unseen, total, Theme.colors.line)
        }
        Text(label, style = Theme.text.footnote, color = Theme.colors.inkSecondary)
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.segment(
    count: Int,
    total: Float,
    color: androidx.compose.ui.graphics.Color
) {
    if (count > 0) Box(Modifier.weight(count / total).fillMaxHeight().clip(CircleShape).background(color))
}

/**
 * The default next action gets the page's one heavy card: ink on the canvas, so it inverts cleanly in dark
 * mode, with everything on it in the canvas colour.
 */
@Composable
private fun PracticeHero(
    counts: com.kfpun.japanesedaily.data.progress.PracticeProgress.Counts,
    wordCount: Int,
    locked: Boolean,
    onClick: () -> Unit
) {
    val onInk = Theme.colors.canvas
    val (minutes, queue) = heroEstimate(counts, wordCount)
    val total = maxOf(wordCount, 1)
    val label = stringResource(
        R.string.arg_memorized_arg_recognized_arg_unseen,
        counts.memorized.toString(),
        counts.recognized.toString(),
        counts.unseen.toString()
    )
    Column(
        Modifier
            .fillMaxWidth()
            .background(Theme.colors.ink, Theme.rounded(Theme.Radius.hero))
            .clip(Theme.rounded(Theme.Radius.hero))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.up_next).uppercase(),
                style = Theme.text.caption.copy(fontWeight = FontWeight.SemiBold),
                color = onInk.copy(alpha = 0.65f),
                modifier = Modifier.weight(1f)
            )
            Text(
                stringResource(R.string.about_arg_min_arg_cards, minutes.toString(), queue.toString()),
                style = Theme.text.caption,
                color = onInk.copy(alpha = 0.65f)
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            // Set in an accent well: the glyph is the one colour on the card, so the hero reads as Practice's.
            Box(
                Modifier
                    .heightIn(min = 48.dp)
                    .widthIn(min = 48.dp)
                    .background(Theme.colors.accent.copy(alpha = 0.18f), Theme.rounded(Theme.Radius.row)),
                contentAlignment = Alignment.Center
            ) {
                SymbolIcon(R.drawable.ic_school, Theme.colors.accent, Theme.text.title2.fontSize.value.toInt())
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(stringResource(R.string.practice), style = Theme.title(Theme.text.title2), color = onInk)
                Text(
                    stringResource(R.string.two_choices_per_card_the_app_keeps_score),
                    style = Theme.text.footnote,
                    color = onInk.copy(alpha = 0.65f)
                )
            }
            if (locked) {
                SymbolIcon(R.drawable.ic_lock, onInk.copy(alpha = 0.7f), Theme.text.subheadline.fontSize.value.toInt())
            } else {
                Text(
                    stringResource(R.string.start),
                    style = Theme.text.subheadline.copy(fontWeight = FontWeight.SemiBold),
                    color = Theme.colors.ink,
                    modifier = Modifier
                        .background(onInk, CircleShape)
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }
        }
        CapsuleBar(
            counts.memorized.toDouble() / total,
            Modifier.semantics { contentDescription = label },
            height = 4,
            track = onInk.copy(alpha = 0.25f),
            fill = onInk
        )
    }
}

/** Icon and status on top, then name and one-line description. Honest data only: "tried", not a made-up completion. */
@Composable
private fun ModeTile(
    @Suppress("UNUSED_PARAMETER") key: String,
    @DrawableRes icon: Int,
    title: Int,
    subtitle: Int,
    gated: Boolean,
    visited: Boolean,
    modifier: Modifier,
    onClick: () -> Unit
) {
    Column(
        modifier
            .cardChrome()
            .clip(Theme.rounded(Theme.Radius.card))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            IconWell(icon, active = !gated)
            Box(Modifier.weight(1f), contentAlignment = Alignment.TopEnd) {
                when {
                    // Amber, not red: a lock is an offer, not an error.
                    gated -> SymbolIcon(
                        R.drawable.ic_lock,
                        Theme.colors.streak,
                        Theme.text.footnote.fontSize.value.toInt()
                    )

                    visited -> Text(
                        stringResource(R.string.tried),
                        style = Theme.text.caption.copy(fontWeight = FontWeight.Medium),
                        color = Theme.colors.accent,
                        modifier = Modifier
                            .background(Theme.colors.wash(Theme.colors.accent), CircleShape)
                            .padding(horizontal = 9.dp, vertical = 4.dp)
                    )

                    else -> Text(
                        stringResource(R.string.not_tried_yet),
                        style = Theme.text.caption,
                        color = Theme.colors.inkTertiary
                    )
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(title), style = Theme.title(Theme.text.headline), color = Theme.colors.ink)
            Text(stringResource(subtitle), style = Theme.text.caption, color = Theme.colors.inkSecondary)
        }
    }
}

/**
 * The offer, stated where the work happens: free lessons only, non-premium only (on a locked lesson it
 * would read as a taunt), gone the moment it is won.
 */
@Composable
private fun EarnHint(
    lesson: Int,
    earned: Boolean,
    isPremium: Boolean,
    results: Collection<com.kfpun.japanesedaily.data.progress.ChallengeResult>,
    env: LessonsEnv
) {
    val band = Gating.earnableGroup()
    val (swept, total) = remember(results) { LessonStanding.firstGroupProgress(results, env::wordCount) }
    if (isPremium || earned || lesson > Gating.freeLessonLimit() || band == null || total <= 0) return
    Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            SymbolIcon(R.drawable.ic_lock_open, Theme.colors.streak, Theme.text.footnote.fontSize.value.toInt())
            Text(
                stringResource(
                    R.string.three_star_every_challenge_in_lessons_1_arg_and_all_8f2191d,
                    Gating.freeLessonLimit().toString(),
                    stringResource(groupLabel(band.name))
                ),
                style = Theme.text.footnote,
                color = Theme.colors.inkSecondary
            )
        }
        // The number is the point: a bar with a count turns "some day" into "four more".
        CapsuleBar(swept.toDouble() / total, fill = Theme.colors.streak)
        Text(
            stringResource(R.string.arg_arg_three_starred, swept.toString(), total.toString()),
            style = Theme.text.footnote,
            color = Theme.colors.inkSecondary
        )
    }
}
