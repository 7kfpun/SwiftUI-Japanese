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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.SymbolIcon

/**
 * The Vocab List (port of `VocabListView`): every entry as a scannable list with three cut chips (All / Not
 * memorized / Bookmarked, each with a live count) and the Examples switch beside them. **Always free, even on
 * a locked lesson**: the one mode exempt from gating, so browsing and search never lock. The cut also decides
 * what Read along reads.
 *
 * Not ported here: the swipe-to-report action. It opens the feedback sheet, which belongs to the Feedback and
 * Survey ticket; the caption that teaches it comes with it.
 */
@Composable
fun VocabListScreen(lessonNumber: Int, env: LessonsEnv, nav: LessonsNav, modifier: Modifier = Modifier) {
    val container = env.container
    val entries = remember(lessonNumber, env.language) { env.lesson(lessonNumber).entries }
    val tiers by rememberBookmarkTiers(container)
    val examples = rememberPref(Pref.examplesShown, container)
    var cutKey by rememberSaveable { mutableStateOf(VocabCut.All.key) }
    val cut = VocabCut.of(cutKey)
    val hasExamples = container.vocab.hasExamples
    // The stored flag AND the dataset agreeing: a switch hidden for a course with no sentences must not leave
    // "examples shown" promising rows that show none.
    val showsExamples = examples.value && hasExamples
    val stage = { v: com.kfpun.japanesedaily.data.vocab.Vocab -> container.practice.stage(v.id) }
    val shown = cutWords(cut, entries, stage, tiers)

    LaunchedEffect(lessonNumber) {
        Track.screen(TrackScreens.VOCAB_LIST, mapOf("lesson" to lessonNumber))
        container.prefs.markModeVisit(lessonNumber, LessonMode.VOCAB_LIST)
    }

    LessonScreenFrame(
        stringResource(R.string.vocab_list),
        onBack = { nav.pop() },
        modifier = modifier,
        subtitle = "${stringResource(R.string.lesson_arg, lessonNumber.toString())} · " +
            stringResource(R.string.arg_words, entries.size.toString()),
        actions = {
            // One control into Read along, which takes the current cut with it.
            ToolbarButton(
                R.drawable.ic_play,
                stringResource(R.string.read_along),
                { nav.push(LessonRoute.ReadAlong(lessonNumber, cut.key)) },
                enabled = shown.isNotEmpty()
            )
        }
    ) {
        Column(Modifier.fillMaxWidth()) {
            Row(
                Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                for (c in VocabCut.entries) {
                    CutChip(
                        title = stringResource(
                            when (c) {
                                VocabCut.All -> R.string.all
                                VocabCut.NotMemorized -> R.string.not_memorized
                                VocabCut.Bookmarked -> R.string.bookmarked
                            }
                        ),
                        count = cutWords(c, entries, stage, tiers).size,
                        star = c == VocabCut.Bookmarked,
                        selected = cut == c
                    ) {
                        cutKey = c.key
                        Track.event(TrackEvents.VOCAB_CUT, mapOf("cut" to c.key, "lesson" to lessonNumber))
                    }
                }
                // Examples filters what each row *shows* as the chips filter which rows appear, so it rides in
                // the same row, marked as a different kind of control. Only where the dataset has sentences.
                if (hasExamples) {
                    Box(Modifier.width(1.dp).heightIn(min = 20.dp).background(Theme.colors.line))
                    ExamplesSwitch(examples.value) {
                        examples.set(!examples.value)
                        Track.event(TrackEvents.EXAMPLES_SHOWN, mapOf("on" to !examples.value))
                    }
                }
            }
            LazyColumn(Modifier.fillMaxWidth()) {
                if (shown.isEmpty()) {
                    // A cut that filters everything out has to say *why*: an empty list under "Bookmarked 0"
                    // otherwise looks like a screen that failed to load.
                    item(key = "empty") {
                        Text(
                            stringResource(
                                when (cut) {
                                    VocabCut.Bookmarked -> R.string.nothing_saved_yet_swipe_any_word_left_to_shelve_it
                                    VocabCut.NotMemorized -> R.string.every_word_in_this_lesson_is_memorized
                                    VocabCut.All -> R.string.no_words_here
                                }
                            ),
                            style = Theme.text.subheadline,
                            color = Theme.colors.inkSecondary,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
                        )
                    }
                }
                items(shown, key = { it.id }) { v ->
                    VocabRow(
                        v,
                        container,
                        tiers,
                        surface = "vocab_list",
                        showExample = showsExamples,
                        stage = stage(v)
                    )
                    HorizontalDivider(color = Theme.colors.line)
                }
            }
        }
    }
}

/**
 * One cut chip: label and count. **A solid ink fill, not an accent border**: the border rule exists to stop
 * accent fills competing with answer feedback, and this fill carries no verdict. Four capsules distinguished
 * only by border weight are hard to read at a glance.
 */
@Composable
private fun CutChip(title: String, count: Int, star: Boolean, selected: Boolean, onClick: () -> Unit) {
    val ink = if (selected) Theme.colors.canvas else Theme.colors.ink
    Row(
        Modifier
            .heightIn(min = 44.dp)
            .background(if (selected) Theme.colors.ink else Theme.colors.surface, CircleShape)
            .then(if (selected) Modifier else Modifier.border(1.dp, Theme.colors.line, CircleShape))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        if (star) SymbolIcon(R.drawable.ic_star, ink, Theme.text.caption.fontSize.value.toInt())
        Text(title, style = Theme.text.subheadline, color = ink)
        Text(
            count.toString(),
            style = Theme.text.caption.copy(fontWeight = FontWeight.SemiBold),
            color = if (selected) ink.copy(alpha = 0.7f) else Theme.colors.inkSecondary
        )
    }
}

/** A label and a drawn switch in the chip shell. At its real size, so it is sharp and sits *inside* the chip. */
@Composable
private fun ExamplesSwitch(on: Boolean, onClick: () -> Unit) {
    val label = stringResource(R.string.show_examples)
    Row(
        Modifier
            .heightIn(min = 44.dp)
            .background(Theme.colors.surface, CircleShape)
            .border(1.dp, Theme.colors.line, CircleShape)
            .clickable(role = Role.Switch, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = label }
            .padding(start = 13.dp, end = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(stringResource(R.string.examples), style = Theme.text.subheadline, color = Theme.colors.ink)
        Box(
            Modifier.size(
                width = 36.dp,
                height = 20.dp
            ).background(if (on) Theme.colors.accent else Theme.colors.line, CircleShape).padding(2.dp),
            contentAlignment = if (on) Alignment.CenterEnd else Alignment.CenterStart
        ) {
            Box(Modifier.size(16.dp).background(Theme.colors.onAccent, CircleShape))
        }
    }
}
