package com.kfpun.japanesedaily.progress

import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.data.progress.Streak
import com.kfpun.japanesedaily.data.progress.StudyDay
import com.kfpun.japanesedaily.lessons.BookmarksScreen
import com.kfpun.japanesedaily.lessons.LessonRoute
import com.kfpun.japanesedaily.lessons.LessonsEnv
import com.kfpun.japanesedaily.lessons.LessonsNav
import com.kfpun.japanesedaily.lessons.rememberLessonsEnv
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.EmptyStatePanel
import com.kfpun.japanesedaily.ui.components.IconWell
import com.kfpun.japanesedaily.ui.components.Illustration
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.cardChrome
import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Locale
import kotlinx.coroutines.delay

/**
 * The Progress tab (port of iOS `StatsView`): the streak, twelve weeks of study days, four tiles and the
 * Bookmarks shelf. Bookmarks opens FOX-153's [BookmarksScreen] on a nav of its own, so Back returns here.
 * Every number is derived from stored rows ([ProgressStats]); nothing on this screen is seeded.
 */
@Composable
fun ProgressTab(bookmarksNav: LessonsNav, modifier: Modifier = Modifier, preview: ProgressStats? = null) {
    val env = rememberLessonsEnv()
    if (env == null) {
        Box(modifier.fillMaxSize().background(Theme.colors.canvas))
        return
    }
    if (bookmarksNav.current == LessonRoute.Bookmarks) {
        BackHandler { bookmarksNav.pop() }
        BookmarksScreen(env, bookmarksNav, modifier)
        return
    }
    val stats = preview ?: rememberProgressStats(env)
    LaunchedEffect(Unit) { Track.screen(TrackScreens.PROGRESS) }
    ProgressContent(stats, onBookmarks = { bookmarksNav.push(LessonRoute.Bookmarks) }, modifier = modifier)
}

/** The live stats: combines the four result streams, re-stamping "today" every minute (midnight, zone change). */
@Composable
private fun rememberProgressStats(env: LessonsEnv): ProgressStats {
    val container = env.container
    val tick = rememberMinuteTick()
    val today = remember(tick) { StudyDay.stamp() }
    val flow = remember(container, today) { progressStatsFlow(container, today) }
    val stats by flow.collectAsStateWithEmpty(today, container)
    return stats
}

@Composable
private fun kotlinx.coroutines.flow.Flow<ProgressStats>.collectAsStateWithEmpty(
    today: Int,
    container: AppContainer
): androidx.compose.runtime.State<ProgressStats> {
    val initial = remember(today) { emptyStats(today, container) }
    return androidx.compose.runtime.produceState(initial, this) { collect { value = it } }
}

private fun emptyStats(today: Int, container: AppContainer) = ProgressStats.from(
    emptyList(),
    emptyList(),
    emptyList(),
    emptyList(),
    today,
    challengesTotal(container),
    kanaTotal(container)
)

private fun challengesTotal(container: AppContainer): Int = (1..container.course.lessonCount).sumOf {
    com.kfpun.japanesedaily.data.progress.LadderRules.count(container.vocab.wordCount(it))
}

private fun kanaTotal(container: AppContainer): Int =
    ProgressStats.kanaTotal(listOf(container.kana.seion, container.kana.dakuon, container.kana.youon))

internal fun progressStatsFlow(container: AppContainer, today: Int) = kotlinx.coroutines.flow.combine(
    container.progress.observeStudyDays(),
    container.progress.observeChallenges(),
    container.progress.observeKana(),
    container.progress.observeBookmarks()
) { days, challenges, kana, bookmarks ->
    ProgressStats.from(
        days,
        challenges.values,
        kana.values,
        bookmarks,
        today,
        challengesTotal(container),
        kanaTotal(container)
    )
}

@Composable
private fun rememberMinuteTick(): Long {
    var tick by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(MINUTE_MS)
            tick = System.currentTimeMillis()
        }
    }
    return tick
}

private const val MINUTE_MS = 60_000L

@Composable
fun ProgressContent(stats: ProgressStats, onBookmarks: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier
            .fillMaxSize()
            .background(Theme.colors.canvas)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
    ) {
        Text(
            stringResource(R.string.progress),
            style = Theme.title(Theme.text.headline),
            color = Theme.colors.ink,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(top = 16.dp)
        )
        if (stats.isEmpty) {
            // The empty state never replaces Bookmarks: saved words need no challenge at all.
            EmptyStatePanel(stringResource(R.string.take_a_challenge_or_a_kana_quiz_to_start_a_streak)) {
                Illustration(R.drawable.ill_skill_tree, tint = Theme.colors.accent.copy(alpha = ART_ALPHA))
            }
        } else {
            Column(
                Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                StreakHero(stats.streak)
                StudyCalendarCard(stats.streak)
                StatGrid(stats)
            }
        }
        BookmarksRow(stats.bookmarkCount, onBookmarks)
    }
}

private const val ART_ALPHA = 0.7f

@Composable
private fun StatGrid(stats: ProgressStats) {
    val tiles = listOf(
        Tile(R.drawable.ic_trophy, stringResource(R.string.best_streak), "${stats.streak.best}", null),
        Tile(R.drawable.ic_calendar, stringResource(R.string.days_studied), "${stats.daysStudied}", null),
        Tile(
            R.drawable.ic_verified,
            stringResource(R.string.challenges_passed),
            "${stats.challengesPassed}",
            "${stats.challengesTotal}"
        ),
        Tile(
            R.drawable.ic_menu_book,
            stringResource(R.string.kana_learned),
            "${stats.kanaLearned}",
            "${stats.kanaTotal}"
        )
    )
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        tiles.chunked(2).forEach { pair ->
            Row(
                Modifier.fillMaxWidth().height(IntrinsicSize.Max),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                pair.forEach { StatTile(it, Modifier.weight(1f).fillMaxSize()) }
            }
        }
    }
}

private class Tile(val icon: Int, val label: String, val value: String, val total: String?)

/** One counter: what it is, then the number, with its ceiling (if any) set smaller. */
@Composable
private fun StatTile(tile: Tile, modifier: Modifier = Modifier) {
    val description = tile.total?.let { "${tile.value} / $it" } ?: tile.value
    Column(
        modifier
            .cardChrome(Theme.Radius.row)
            .padding(14.dp)
            .clearAndSetSemantics {
                contentDescription = tile.label
                stateDescription = description
            },
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        IconWell(tile.icon)
        Text(tile.label, style = Theme.text.subheadline, color = Theme.colors.inkSecondary)
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(tile.value, style = Theme.title(Theme.text.title2, FontWeight.Bold), color = Theme.colors.ink)
            tile.total?.let {
                Text("/ $it", style = Theme.title(Theme.text.subheadline), color = Theme.colors.inkSecondary)
            }
        }
    }
}

/** The shelf entry, shown unconditionally: it is the only route to saved words. */
@Composable
private fun BookmarksRow(count: Int, onClick: () -> Unit) {
    Row(
        Modifier
            .padding(16.dp)
            .fillMaxWidth()
            .cardChrome(Theme.Radius.row)
            .clickable(onClick = onClick)
            .heightIn(min = 56.dp)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        IconWell(R.drawable.ic_star_outline)
        Text(
            stringResource(R.string.bookmarks),
            style = Theme.text.body,
            color = Theme.colors.ink,
            modifier = Modifier.weight(1f)
        )
        // The count says whether there is anything behind the row before you tap.
        if (count > 0) {
            Text(
                "$count",
                style = Theme.title(Theme.text.body),
                color = Theme.colors.inkSecondary
            )
        }
        SymbolIcon(R.drawable.ic_chevron_right, Theme.colors.inkTertiary, CHEVRON_SP)
    }
}

private const val CHEVRON_SP = 20

/** The locale the UI is drawn in (the per-app language is applied to the activity's configuration). */
@Composable
private fun uiLocale(): Locale = LocalConfiguration.current.locales.let { if (it.isEmpty) Locale.ROOT else it[0] }

/** The streak, full size: the number, the week behind it, and what is at stake. Nothing is invented pressure. */
@Composable
fun StreakHero(streak: Streak, modifier: Modifier = Modifier) {
    val colors = Theme.colors
    val locale = uiLocale()
    val label = stringResource(R.string.arg_day_streak, streak.current)
    Column(
        modifier
            .fillMaxWidth()
            .cardChrome(Theme.Radius.deck)
            .padding(horizontal = 18.dp, vertical = 22.dp)
            .semantics(mergeDescendants = true) { contentDescription = label },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            // Hollow while today is open, filled once it is done: "on a run" versus "on a run, still open".
            SymbolIcon(
                if (streak.studiedToday) R.drawable.ic_flame_filled else R.drawable.ic_flame,
                colors.streak,
                FLAME_SP
            )
            Text("${streak.current}", style = Theme.display(NUMBER_SP), color = colors.streak, maxLines = 1)
        }
        WeekStrip(streak, locale)
        val message = when {
            streak.atRisk -> stringResource(R.string.study_today_to_keep_your_streak)
            streak.toBeatBest != null -> stringResource(R.string.arg_more_days_to_beat_your_best, streak.toBeatBest!!)
            else -> null
        }
        if (message != null) {
            Text(
                message,
                style = Theme.text.footnote,
                color = if (streak.atRisk) colors.streak else colors.inkSecondary,
                textAlign = TextAlign.Center
            )
        }
        Countdown(streak, locale)
    }
}

private const val FLAME_SP = 40
private const val NUMBER_SP = 56

/** Time remaining until the streak actually ends; absent unless it is at risk. Redrawn every minute. */
@Composable
private fun Countdown(streak: Streak, locale: Locale) {
    val tick = rememberMinuteTick()
    val left = remember(tick, streak) { streak.timeLeft(Instant.ofEpochMilli(tick)) } ?: return
    val text = remember(left, locale) { formatRemaining(left, locale) }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        SymbolIcon(R.drawable.ic_schedule, Theme.colors.streak, CAPTION_ICON_SP)
        Text(
            stringResource(R.string.arg_left_today, text),
            style = Theme.title(Theme.text.caption),
            color = Theme.colors.streak
        )
    }
}

private const val CAPTION_ICON_SP = 14

/** "5h 12m", in the app's language rather than the phone's; the leading hour is dropped under an hour. */
internal fun formatRemaining(left: Duration, locale: Locale): String {
    val (h, m) = hoursAndMinutes(left)
    val format = MeasureFormat.getInstance(locale, MeasureFormat.FormatWidth.NARROW)
    val parts = buildList {
        if (h > 0) add(Measure(h, MeasureUnit.HOUR))
        add(Measure(m, MeasureUnit.MINUTE))
    }
    return format.formatMeasures(*parts.toTypedArray())
}

/** Seven dots; a missed day is a hole you can see. */
@Composable
private fun WeekStrip(streak: Streak, locale: Locale) {
    val colors = Theme.colors
    Row(
        Modifier.clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        for ((stamp, studied) in streak.lastWeek()) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                Box(
                    Modifier
                        .size(DOT_RING)
                        // Today is ringed whether or not it is filled, so the eye lands on the one day still open.
                        .then(
                            if (stamp ==
                                streak.today
                            ) {
                                Modifier.border(2.dp, colors.streak, CircleShape)
                            } else {
                                Modifier
                            }
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        Modifier
                            .size(DOT)
                            .clip(CircleShape)
                            .background(if (studied) colors.streak else colors.inkSecondary.copy(alpha = EMPTY_ALPHA))
                    )
                }
                Text(
                    StudyCalendar.dayOfWeek(stamp).getDisplayName(TextStyle.NARROW_STANDALONE, locale),
                    style = Theme.text.caption2,
                    color = colors.inkTertiary
                )
            }
        }
    }
}

private val DOT = 14.dp
private val DOT_RING = 22.dp
private const val EMPTY_ALPHA = 0.15f

/** Twelve weeks, a column per week, the current week last. Laid out on the locale's first weekday. */
@Composable
private fun StudyCalendarCard(streak: Streak) {
    val colors = Theme.colors
    val locale = uiLocale()
    val columns = remember(streak.today, locale) {
        StudyCalendar.columns(streak.today, WeekFields.of(locale).firstDayOfWeek)
    }
    val studied = remember(columns, streak) { StudyCalendar.studiedIn(columns, streak.days) }
    val days = stringResource(R.string.arg_days, studied)
    val title = stringResource(R.string.last_12_weeks)
    Column(
        Modifier
            .fillMaxWidth()
            .cardChrome(Theme.Radius.deck)
            .padding(16.dp)
            .clearAndSetSemantics {
                contentDescription = title
                stateDescription = days
            },
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
            Text(title, style = Theme.title(Theme.text.subheadline), color = colors.ink, modifier = Modifier.weight(1f))
            Text(days, style = Theme.text.footnote, color = colors.inkSecondary)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            columns.forEach { week ->
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    week.forEach { stamp -> CalendarCell(stamp, streak) }
                }
            }
        }
    }
}

@Composable
private fun CalendarCell(stamp: Int?, streak: Streak) {
    val colors = Theme.colors
    val shape = Theme.rounded(Theme.Radius.tick)
    val fill = when {
        stamp == null -> androidx.compose.ui.graphics.Color.Transparent
        stamp in streak.days -> colors.streak
        else -> colors.inkSecondary.copy(alpha = EMPTY_ALPHA)
    }
    Box(
        Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .clip(shape)
            .background(fill)
            // Today is ringed whether or not it is done, as on the week strip; future days are outlined.
            .then(if (stamp == streak.today) Modifier.border(1.5.dp, colors.streak, shape) else Modifier)
            .then(if (stamp == null) Modifier.border(1.dp, colors.line, shape) else Modifier)
    )
}
