package com.kfpun.japanesedaily.lessons

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.data.Course
import com.kfpun.japanesedaily.data.progress.LadderRules
import com.kfpun.japanesedaily.data.vocab.searchVocab
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.cardChrome
import com.kfpun.japanesedaily.ui.components.scaledSize
import kotlinx.coroutines.delay

/** The group name keys are `UIStrings.json` keys ("Beginning 1"); resolve them to string resources. */
internal fun groupLabel(name: String): Int = when (name) {
    "Beginning 1" -> R.string.beginning_1
    "Beginning 2" -> R.string.beginning_2
    "Advanced 1" -> R.string.advanced_1
    else -> R.string.advanced_2
}

/**
 * The Lessons tab's list (port of `LessonListView`): four fixed groups and a debounced `contains` search.
 * Locked lessons are not marked "free" anywhere; the lock appears on rows past the free limit and the
 * paywall opens one level in, in the mode picker, where gating is enforced.
 */
@Composable
fun LessonListScreen(env: LessonsEnv, nav: LessonsNav, modifier: Modifier = Modifier) {
    val isPremium = LocalPremium.current.isPremium
    val groups = Course.current.groups
    var query by rememberSaveable { mutableStateOf("") }
    var group by rememberSaveable { mutableIntStateOf(0) }
    val results by remember { env.container.progress.observeChallenges() }.collectAsState(emptyMap())
    val passed = remember(results) { LessonStanding.passedByLesson(results.values) }
    val earned = remember(results) { LessonStanding.earnedFirstGroup(results.values, env::wordCount) }
    val tiers by rememberBookmarkTiers(env.container)
    val language = env.language

    LaunchedEffect(Unit) { Track.screen(TrackScreens.LESSONS) }
    // Debounced 600 ms; counted *inside* the debounce so a keystroke never costs a second corpus pass.
    LaunchedEffect(query, language) {
        if (query.isEmpty()) return@LaunchedEffect
        delay(SEARCH_DEBOUNCE_MILLIS)
        val hits = searchVocab(query, env.container.vocab.allVocab(language)).size
        Track.event(TrackEvents.SEARCH_VOCAB, mapOf("query_length" to query.length, "results" to hits))
    }
    // One evaluation per query, shared by the rows and the header count: each pass lowercases four
    // fields per entry across the whole corpus.
    val hits = remember(query, language) { searchVocab(query, env.container.vocab.allVocab(language)) }

    Column(modifier.fillMaxSize().background(Theme.colors.canvas).statusBarsPadding()) {
        Text(
            stringResource(R.string.lessons),
            style = Theme.title(Theme.text.title, FontWeight.Bold),
            color = Theme.colors.ink,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)
        )
        SearchField(query, { query = it }, Modifier.padding(horizontal = 16.dp))
        if (query.isEmpty()) {
            Row(
                Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                groups.forEachIndexed { i, g ->
                    SegmentChip(
                        stringResource(groupLabel(g.name)),
                        i == group,
                        {
                            if (group != i) {
                                group = i
                                Track.event(TrackEvents.LESSON_GROUP, mapOf("group" to i))
                            }
                        },
                        Modifier.weight(1f)
                    )
                }
            }
            val band = groups[group]
            val cleared = band.range.sumOf { passed[it] ?: 0 }
            Text(
                listOf(
                    stringResource(R.string.lesson_arg, "${band.first}–${band.last}"),
                    stringResource(R.string.arg_lessons, band.range.count().toString()),
                    stringResource(R.string.arg_challenges_passed, cleared.toString())
                ).joinToString(" · "),
                style = Theme.title(Theme.text.footnote, FontWeight.Normal),
                color = Theme.colors.inkSecondary,
                modifier = Modifier.padding(horizontal = 20.dp)
            )
        }
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (query.isEmpty()) {
                val next = LessonStanding.continueLesson(passed, env::wordCount)
                if (next != null) {
                    item(key = "continue") {
                        ContinueCard(next, passed[next] ?: 0, LadderRules.count(env.wordCount(next))) {
                            nav.push(LessonRoute.Select(next))
                        }
                    }
                }
                items(groups[group].range.toList(), key = { it }) { n ->
                    val lesson = env.lesson(n)
                    LessonRow(
                        number = n,
                        preview = lesson.entries.take(PREVIEW_WORDS).map { it.kanji },
                        done = passed[n] ?: 0,
                        total = LadderRules.count(lesson.entries.size),
                        locked = Gating.isLocked(n, isPremium, earned)
                    ) { nav.push(LessonRoute.Select(n)) }
                }
            } else {
                item(key = "header") {
                    SectionLabel(
                        stringResource(R.string.arg_results, hits.size.toString()),
                        Modifier.padding(horizontal = 4.dp)
                    )
                }
                if (hits.isEmpty()) {
                    item(key = "empty") {
                        Column(
                            Modifier.padding(horizontal = 4.dp, vertical = 6.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                stringResource(R.string.nothing_matched_arg, query),
                                style = Theme.text.subheadline,
                                color = Theme.colors.ink
                            )
                            Text(
                                stringResource(R.string.try_kana_kanji_romaji_or_the_meaning),
                                style = Theme.text.footnote,
                                color = Theme.colors.inkSecondary
                            )
                        }
                    }
                }
                items(hits, key = { it.id }) { v ->
                    Box(Modifier.fillMaxWidth().cardChrome(Theme.Radius.row)) {
                        VocabRow(v, env.container, tiers, surface = "search", showLesson = true)
                    }
                }
            }
        }
    }
}

private const val SEARCH_DEBOUNCE_MILLIS = 600L
private const val PREVIEW_WORDS = 3

/** The search box. A plain field on the surface colour rather than Material's, which brings its own palette. */
@Composable
private fun SearchField(query: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    val shape = Theme.rounded(Theme.Radius.chip)
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .background(Theme.colors.surface, shape)
            .border(1.dp, Theme.colors.line, shape)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        SymbolIcon(R.drawable.ic_search, Theme.colors.inkSecondary, Theme.text.body.fontSize.value.toInt())
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) {
                Text(
                    stringResource(R.string.search_vocabulary),
                    style = Theme.text.body,
                    color = Theme.colors.inkTertiary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            BasicTextField(
                query,
                onChange,
                Modifier.fillMaxWidth(),
                textStyle = Theme.text.body.copy(color = Theme.colors.ink),
                singleLine = true,
                cursorBrush = SolidColor(Theme.colors.accent),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    imeAction = ImeAction.Search
                )
            )
        }
        if (query.isNotEmpty()) {
            Box(
                Modifier.size(40.dp).clickable(role = Role.Button) {
                    onChange("")
                },
                contentAlignment = Alignment.Center
            ) {
                SymbolIcon(R.drawable.ic_close, Theme.colors.inkSecondary, Theme.text.callout.fontSize.value.toInt())
            }
        }
    }
}

/** The list's one inverted card: the lesson you are on, and how far up its ladder. Same ink as the lesson hero. */
@Composable
private fun ContinueCard(number: Int, done: Int, total: Int, onClick: () -> Unit) {
    val onInk = Theme.colors.canvas
    Row(
        Modifier
            .fillMaxWidth()
            .background(Theme.colors.ink, Theme.rounded(Theme.Radius.row))
            .clip(Theme.rounded(Theme.Radius.row))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Box(
            Modifier
                .heightIn(min = scaledSize(NUMBER_BOX_SP))
                .widthIn(min = scaledSize(NUMBER_BOX_SP))
                .background(onInk.copy(alpha = 0.12f), Theme.rounded(Theme.Radius.card)),
            contentAlignment = Alignment.Center
        ) {
            Text(number.toString(), style = Theme.title(Theme.text.title2, FontWeight.Bold), color = onInk)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                stringResource(R.string.up_next).uppercase(),
                style = Theme.text.caption.copy(fontWeight = FontWeight.SemiBold),
                color = onInk.copy(alpha = 0.7f)
            )
            Text(
                stringResource(R.string.lesson_arg, number.toString()),
                style = Theme.title(Theme.text.title3, FontWeight.Bold),
                color = onInk
            )
            CapsuleBar(
                if (total > 0) done.toDouble() / total else 0.0,
                Modifier.padding(top = 2.dp),
                track = onInk.copy(alpha = 0.25f),
                fill = onInk
            )
            Text(
                stringResource(R.string.arg_challenges_passed, done.toString()),
                style = Theme.text.footnote,
                color = onInk.copy(alpha = 0.7f)
            )
        }
        SymbolIcon(R.drawable.ic_chevron_right, onInk.copy(alpha = 0.7f), Theme.text.footnote.fontSize.value.toInt())
    }
}

private const val NUMBER_BOX_SP = 48

/**
 * A lesson row: numbered badge, title, the lesson's first few words, then its standing: nothing when
 * untouched (an empty ring on fifty rows reads "nothing works"), a count and ring once under way, and an
 * amber lock past the free limit (a lock is an offer, not an error).
 */
@Composable
private fun LessonRow(number: Int, preview: List<String>, done: Int, total: Int, locked: Boolean, onClick: () -> Unit) {
    val tint = if (locked) Theme.colors.inkSecondary else Theme.colors.accent
    val title = stringResource(R.string.lesson_arg, number.toString())
    val description = if (done > 0) "$title, $done / $total" else title
    Row(
        Modifier
            .fillMaxWidth()
            .cardChrome(Theme.Radius.row)
            .clip(Theme.rounded(Theme.Radius.row))
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = description }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            Modifier
                .heightIn(min = scaledSize(BADGE_SP))
                .widthIn(min = scaledSize(BADGE_SP))
                .background(Theme.colors.wash(tint), Theme.rounded(Theme.Radius.chip)),
            contentAlignment = Alignment.Center
        ) {
            Text(number.toString(), style = Theme.text.subheadline.copy(fontWeight = FontWeight.SemiBold), color = tint)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Theme.title(Theme.text.body, FontWeight.Normal), color = Theme.colors.ink)
            Text(
                preview.joinToString("・"),
                style = Theme.jp(Theme.text.subheadline),
                color = Theme.colors.inkSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        if (locked) {
            SymbolIcon(R.drawable.ic_lock, Theme.colors.streak, Theme.text.footnote.fontSize.value.toInt())
        } else if (done > 0) {
            Text("$done / $total", style = Theme.text.footnote, color = Theme.colors.inkSecondary)
            ProgressRing(if (total > 0) done.toFloat() / total else 0f)
        }
    }
}

private const val BADGE_SP = 36

/** A lesson's ladder as a ring, scaled with the footnote it sits next to. */
@Composable
fun ProgressRing(fraction: Float, modifier: Modifier = Modifier) {
    val size = scaledSize(RING_SP)
    val line = Theme.colors.line
    val accent = Theme.colors.accent
    Box(
        modifier.size(size).drawBehind {
            val stroke = Stroke(this.size.minDimension * 0.18f, cap = StrokeCap.Round)
            val inset = stroke.width / 2
            val arc = Size(this.size.width - stroke.width, this.size.height - stroke.width)
            drawArc(line, 0f, 360f, false, Offset(inset, inset), arc, style = stroke)
            drawArc(accent, -90f, 360f * fraction.coerceIn(0f, 1f), false, Offset(inset, inset), arc, style = stroke)
        }
    )
}

private const val RING_SP = 20
