package com.kfpun.japanesedaily.lessons

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.PaywallSource
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.data.progress.ChallengeResult
import com.kfpun.japanesedaily.data.progress.LadderRules
import com.kfpun.japanesedaily.data.vocab.Lesson
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.accentPlate
import com.kfpun.japanesedaily.ui.components.cardChrome

/*
 * ============================================================================================
 * FOX-154 ENTRY POINT: the Challenge ladder.
 *
 * Everything on the lesson screen below the practice modes is the ladder's *entry*: the rung
 * strip, the "next up" card and the retry card. They are drawn here from the persisted results
 * (read-only), and every tap on an open rung goes through [LocalOpenChallenge]. The ladder
 * ticket (FOX-154) provides the real [OpenChallenge], which pushes the run (briefing, play and
 * result screens), and replaces the question-count estimate in [nextQuestions] with
 * `Challenge.pool(...)`. Nothing else in the Lessons tab needs to change.
 *
 * Lock rules, unchanged from iOS: a premium lock opens the paywall (`locked_challenge`,
 * reason "paywall"); a rung locked by progress is dimmed and only logs.
 * ============================================================================================
 */

/** Opens rung [index] of [lesson]. A no-op until FOX-154 provides the real ladder. */
fun interface OpenChallenge {
    fun open(lesson: Int, index: Int)
}

val LocalOpenChallenge = staticCompositionLocalOf { OpenChallenge { _, _ -> } }

/** How many questions a rung will ask, for the "next up" card. FOX-154 replaces this with the pool's real size. */
internal fun nextQuestions(lesson: Lesson): Int = minOf(QUESTIONS_PER_CHALLENGE, lesson.entries.size)

private const val QUESTIONS_PER_CHALLENGE = 10

/**
 * The Challenge section of the lesson screen (port of `challengeSection`): header with the star tally,
 * the rung strip, the sequence-lock sentence, the next-up and retry cards. The earn hint is the caller's.
 */
@Composable
fun ChallengeSection(
    lesson: Lesson,
    results: Map<Int, ChallengeResult>,
    previousCleared: Boolean,
    locked: Boolean,
    onPaywall: (source: String) -> Unit,
    modifier: Modifier = Modifier
) {
    val open = LocalOpenChallenge.current
    val count = LadderRules.count(lesson.entries.size)
    val next = LessonStanding.nextIndex(count, results)
    val earned = results.values.sumOf { it.stars }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            SectionLabel(stringResource(R.string.challenge), Modifier.weight(1f))
            // Numerals and a star: no localization to drift.
            Text(
                "$earned / ${count * 3} ★",
                style = Theme.text.footnote.copy(fontWeight = FontWeight.Medium),
                color = Theme.colors.inkSecondary
            )
        }
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            for (i in 1..count) {
                val result = results[i]
                val passed = result?.isPassed == true
                when {
                    locked -> RungChip(i, null, false, true) {
                        Track.event(
                            TrackEvents.LOCKED_CHALLENGE,
                            mapOf("lesson" to lesson.number, "index" to i, "reason" to "paywall")
                        )
                        onPaywall(PaywallSource.LOCKED_CHALLENGE)
                    }

                    // Sequence-locked: nothing to open (the line under the strip says why), but the tap logs so
                    // the dashboard can see who bounces off. Earned stars still show.
                    !previousCleared -> RungChip(i, result?.stars, false, !passed, Modifier.alpha(DIM)) {
                        Track.event(
                            TrackEvents.LOCKED_CHALLENGE,
                            mapOf("lesson" to lesson.number, "index" to i, "reason" to "previous_lesson")
                        )
                    }

                    passed || next == i -> RungChip(i, result?.stars, next == i, false) { open.open(lesson.number, i) }

                    else -> RungChip(i, null, false, true, Modifier.alpha(DIM)) {
                        Track.event(
                            TrackEvents.LOCKED_CHALLENGE,
                            mapOf("lesson" to lesson.number, "index" to i, "reason" to "not_unlocked")
                        )
                    }
                }
            }
        }
        if (!locked && !previousCleared) {
            Text(
                stringResource(R.string.clear_every_challenge_in_lesson_arg_first, (lesson.number - 1).toString()),
                style = Theme.text.caption,
                color = Theme.colors.inkSecondary
            )
        }
        if (!locked && previousCleared &&
            next != null
        ) {
            NextCard(next, nextQuestions(lesson)) { open.open(lesson.number, next) }
        }
        val retry = LessonStanding.retryTarget(results)
        if (!locked && previousCleared && retry != null) {
            RetryCard(retry, results[retry]) { open.open(lesson.number, retry) }
        }
    }
}

private const val DIM = 0.55f

/** One rung: passed ones show their stars, the next one is the filled call to action, later ones wait behind a lock. */
@Composable
private fun RungChip(
    index: Int,
    stars: Int?,
    isNext: Boolean,
    lockIcon: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val shape = Theme.rounded(Theme.Radius.row)
    val description = stringResource(R.string.challenge_arg, index.toString())
    val ink = if (isNext) Theme.colors.onAccent else Theme.colors.ink
    Column(
        modifier
            .widthIn(min = 56.dp)
            .heightIn(min = 48.dp)
            .background(if (isNext) Theme.colors.accent else Theme.colors.surface, shape)
            .then(if (isNext) Modifier else Modifier.border(1.dp, Theme.colors.line, shape))
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description }
            .padding(horizontal = 8.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Text(index.toString(), style = Theme.text.headline, color = ink)
        when {
            isNext -> Text(
                stringResource(R.string.next_up),
                style = Theme.text.caption2.copy(fontWeight = FontWeight.SemiBold),
                color = ink,
                maxLines = 1
            )

            stars != null -> StarRow(stars, sizeSp = 8)

            lockIcon -> SymbolIcon(
                R.drawable.ic_lock,
                Theme.colors.inkSecondary,
                Theme.text.caption2.fontSize.value.toInt()
            )
        }
    }
}

/** The forward step, as a card: which rung, and what it will ask. */
@Composable
private fun NextCard(index: Int, questions: Int, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().accentPlate().clickable(role = Role.Button, onClick = onClick).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(Modifier.size(32.dp).background(Theme.colors.accent, CircleShape), contentAlignment = Alignment.Center) {
            Text(
                index.toString(),
                style = Theme.text.subheadline.copy(fontWeight = FontWeight.Bold),
                color = Theme.colors.onAccent
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                stringResource(R.string.challenge_arg, index.toString()),
                style = Theme.title(Theme.text.headline),
                color = Theme.colors.ink
            )
            Text(
                "${stringResource(
                    R.string.next_up
                )} · ${stringResource(R.string.arg_mixed_questions, questions.toString())}",
                style = Theme.text.caption,
                color = Theme.colors.inkSecondary
            )
        }
        SymbolIcon(R.drawable.ic_chevron_right, Theme.colors.accent, Theme.text.footnote.fontSize.value.toInt())
    }
}

/** The gap most worth closing: a passed rung still short of three stars. */
@Composable
private fun RetryCard(index: Int, result: ChallengeResult?, onClick: () -> Unit) {
    val stars = result?.stars ?: 0
    Row(
        Modifier.fillMaxWidth().cardChrome().clickable(role = Role.Button, onClick = onClick).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        StarRow(stars, sizeSp = 10)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                stringResource(R.string.retry_challenge_arg, index.toString()),
                style = Theme.title(Theme.text.headline),
                color = Theme.colors.ink
            )
            Text(
                "${stringResource(R.string.best_arg_pct, (result?.bestScore ?: 0).toString())} · " +
                    stringResource(R.string.earn_arg_more, (3 - stars).toString()),
                style = Theme.text.caption,
                color = Theme.colors.inkSecondary
            )
        }
        SymbolIcon(R.drawable.ic_chevron_right, Theme.colors.inkTertiary, Theme.text.footnote.fontSize.value.toInt())
    }
}
