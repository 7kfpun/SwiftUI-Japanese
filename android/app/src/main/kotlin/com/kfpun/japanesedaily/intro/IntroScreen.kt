package com.kfpun.japanesedaily.intro

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.audio.LocalPronouncer
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.data.vocab.Vocab
import java.util.Locale

/** Analytics seam of the intro; the default is `Track`, tests and previews pass their own. */
fun interface IntroEvents {
    fun event(name: String, params: Map<String, Any>)

    companion object {
        val Track = IntroEvents { name, params -> com.kfpun.japanesedaily.analytics.Track.event(name, params) }
    }
}

/**
 * First launch: a six-card tour that also asks the three questions worth asking before anyone has
 * used anything. Port of `IntroView`.
 *
 * - Only card 1 writes a setting as you go (the meanings language, via [onLanguage]). The three answers
 *   are held here and written once, on the way out, so a skip halfway persists exactly what was answered.
 * - It never touches the app language.
 * - Paging is clamped, not wrapped: a forward swipe off the last card finishes. The reminders card must
 *   be *answered*, so it has no Next button and its forward swipe does nothing.
 * - No pricing, premium or free-lesson count is mentioned in any card (product decision).
 */
@Composable
fun IntroScreen(
    samples: IntroSamples,
    language: String,
    onLanguage: (String) -> Unit,
    onFinish: (IntroAnswers, Intro.Tab, completed: Boolean) -> Unit,
    onReminders: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    events: IntroEvents = IntroEvents.Track,
    questionsPerChallenge: Int = 10,
    passScore: Int = 80,
    freeLessonLimit: Int = 5
) {
    val cards = Intro.Card.entries
    var index by rememberSaveable { mutableIntStateOf(0) }
    var direction by remember { mutableIntStateOf(1) }
    val seen = remember { mutableSetOf<Intro.Card>() }
    var kana by rememberSaveable { mutableStateOf<String?>(null) }
    var lesson by rememberSaveable { mutableStateOf<Int?>(null) }
    var goal by rememberSaveable { mutableStateOf<String?>(null) }
    var stepper by rememberSaveable { mutableIntStateOf(5) }
    var peek by rememberSaveable { mutableStateOf(Intro.Mode.VOCAB_LIST.id) }
    val card = cards[index]

    fun answers() = IntroAnswers(
        kana = Intro.KanaLevel.entries.firstOrNull { it.id == kana },
        textbookLesson = lesson,
        goal = Intro.Goal.entries.firstOrNull { it.id == goal }
    )

    fun finish(completed: Boolean) {
        val a = answers()
        if (completed) {
            events.event(TrackEvents.INTRO_DONE, a.trackParams)
        } else {
            events.event(TrackEvents.INTRO_SKIP, mapOf("card" to card.number) + a.trackParams)
        }
        onFinish(a, Intro.landingTab(a.kana), completed)
    }

    fun turn(by: Int) {
        if (by > 0 && card == Intro.Card.REMINDERS) return
        if (by > 0 && index == cards.lastIndex) return finish(true)
        val next = (index + by).coerceIn(0, cards.lastIndex)
        if (next != index) {
            direction = by
            index = next
        }
    }

    if (seen.add(card)) events.event(TrackEvents.INTRO_CARD, mapOf("card" to card.number))

    Column(
        modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .safeDrawingPadding()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            TextButton(onClick = { finish(false) }) { Text(stringResource(R.string.skip)) }
        }
        Surface(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .pointerInput(index) {
                    var drag = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { drag = 0f },
                        onDragEnd = {
                            if (drag < -SWIPE_PX) {
                                turn(1)
                            } else if (drag > SWIPE_PX) {
                                turn(-1)
                            }
                        }
                    ) { _, amount -> drag += amount }
                },
            shape = RoundedCornerShape(24.dp),
            color = MaterialTheme.colorScheme.surfaceContainer,
            tonalElevation = 1.dp
        ) {
            AnimatedContent(
                targetState = card,
                transitionSpec = {
                    (
                        slideInHorizontally(tween(250)) { it * direction } togetherWith
                            slideOutHorizontally(tween(250)) { -it * direction }
                        )
                        .using(SizeTransform(clip = false))
                },
                label = "intro-card"
            ) { shown ->
                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)
                ) {
                    when (shown) {
                        Intro.Card.MEANINGS -> MeaningsCard(samples, language, onLanguage, events)

                        Intro.Card.KANA -> KanaCard(kana) { kana = it }

                        Intro.Card.MODES -> ModesCard(samples, peek, events) { peek = it }

                        Intro.Card.CHALLENGE -> ChallengeCard(
                            lesson = lesson,
                            stepper = stepper,
                            lessonCount = samples.lessonCount,
                            questionsPerChallenge = questionsPerChallenge,
                            passScore = passScore,
                            freeLessonLimit = freeLessonLimit,
                            onNo = { lesson = 0 },
                            onYes = { lesson = stepper },
                            onStepper = {
                                stepper = it
                                lesson = it
                            }
                        )

                        Intro.Card.TODAY -> TodayCard(samples, goal) { goal = it }

                        Intro.Card.REMINDERS -> RemindersCard { wants ->
                            events.event(
                                TrackEvents.NOTIFICATION_OPT_IN,
                                mapOf("source" to "intro", "accepted" to wants)
                            )
                            onReminders(wants)
                            finish(true)
                        }
                    }
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (index > 0) {
                OutlinedButton(onClick = { turn(-1) }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                }
            }
            Dots(index, cards.size, Modifier.weight(1f))
            if (card != Intro.Card.REMINDERS) {
                Button(onClick = { turn(1) }) {
                    Text(
                        stringResource(if (index == cards.lastIndex) R.string.start_learning else R.string.next),
                        maxLines = 1
                    )
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowForward,
                        contentDescription = null,
                        modifier = Modifier.padding(start = 6.dp)
                    )
                }
            }
        }
    }
}

private const val SWIPE_PX = 120f

@Composable
private fun Dots(current: Int, count: Int, modifier: Modifier = Modifier) {
    Row(
        modifier
            .padding(horizontal = 12.dp)
            .semantics { contentDescription = "${current + 1} / $count" },
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        repeat(count) {
            val on = it == current
            Box(
                Modifier
                    .size(if (on) 8.dp else 6.dp)
                    .background(
                        if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
                        CircleShape
                    )
            )
        }
    }
}

/** One answer chip. Selection is an accent border, never a fill: green and red are for answer feedback. */
@Composable
internal fun IntroChip(text: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    val color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .semantics { this.selected = selected }
            .clickable(role = Role.RadioButton, onClick = onClick),
        shape = shape,
        color = MaterialTheme.colorScheme.surfaceContainer,
        border = BorderStroke(if (selected) 2.dp else 1.dp, color)
    ) {
        Text(
            text,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
            style = MaterialTheme.typography.labelLarge,
            color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            maxLines = 2
        )
    }
}

@Composable
private fun Question(text: String) =
    Text(text, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)

@Composable
private fun Caption(text: String) = Text(
    text,
    style = MaterialTheme.typography.bodyMedium,
    color = MaterialTheme.colorScheme.onSurfaceVariant,
    textAlign = TextAlign.Center
)

@Composable
private fun Heading(text: String) =
    Text(text, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)

private fun nativeName(code: String): String =
    Locale.forLanguageTag(code).let { it.getDisplayName(it) }.replaceFirstChar { c -> c.uppercase() }

@Composable
private fun WordFace(word: Vocab) {
    // Tap to hear it, through the same Pronouncer (and bundled clip) as the rest of the app.
    val pronouncer = LocalPronouncer.current
    Column(
        Modifier.clickable { pronouncer.speak(word) },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (word.displaysKanji) {
            Text(
                word.kanji,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(word.kana, style = MaterialTheme.typography.displayMedium, textAlign = TextAlign.Center)
        Text(
            word.romaji,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            word.translation,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary,
            textAlign = TextAlign.Center
        )
    }
}

/** Card 1: the four-field anatomy every card shares, plus the choice worth making this early. */
@Composable
private fun MeaningsCard(samples: IntroSamples, language: String, onLanguage: (String) -> Unit, events: IntroEvents) {
    var open by remember { mutableStateOf(false) }
    Heading(stringResource(R.string.meanings_in_arg, nativeName(language)))
    samples.anatomyWord?.let { WordFace(it) }
    Caption(stringResource(R.string.tap_any_word_to_hear_it))
    Box {
        OutlinedButton(onClick = { open = true }) { Text(stringResource(R.string.change_language), maxLines = 1) }
        androidx.compose.material3.DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            samples.languages.forEach { code ->
                androidx.compose.material3.DropdownMenuItem(
                    text = { Text(nativeName(code)) },
                    onClick = {
                        open = false
                        if (code != language) {
                            onLanguage(code)
                            events.event(TrackEvents.SET_VOCAB_LANGUAGE, mapOf("code" to code))
                        }
                    }
                )
            }
        }
    }
}

/** Card 2: Kana is free in full; asks whether the learner reads kana. */
@Composable
private fun KanaCard(selected: String?, onSelect: (String) -> Unit) {
    // Tap あ to hear it, through the same Pronouncer (and bundled clip) as the Kana tab; iOS does the same.
    val pronouncer = LocalPronouncer.current
    val context = LocalContext.current
    val a = remember { AppContainer.from(context).kana.seion.flatten().firstOrNull { it.romaji == "a" } }
    Text(
        a?.hiragana ?: "あ",
        style = MaterialTheme.typography.displayLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier
            .semantics { a?.let { contentDescription = it.romaji } }
            .clickable(enabled = a != null) { a?.let(pronouncer::speak) }
    )
    Heading(stringResource(R.string.all_of_kana_is_free))
    Caption(stringResource(R.string.the_chart_the_quizzes_and_drawing_a_kana_to_have_you_d9028e4))
    Question(stringResource(R.string.do_you_read_kana_already))
    Intro.KanaLevel.entries.forEach {
        IntroChip(stringResource(it.title), selected == it.id) { onSelect(it.id) }
    }
}

/** Card 3: the five modes, tap to preview. Static: nothing here records a result. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ModesCard(samples: IntroSamples, peek: String, events: IntroEvents, onPeek: (String) -> Unit) {
    val mode = Intro.Mode.entries.first { it.id == peek }
    Heading(stringResource(R.string.five_ways_through_a_lesson))
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        maxItemsInEachRow = 2
    ) {
        Intro.Mode.entries.forEach {
            IntroChip(stringResource(it.title), peek == it.id, Modifier.fillMaxWidth(0.48f)) {
                onPeek(it.id)
                // The canonical English key, not the localized title: a param whose value shifts with
                // device language cannot be grouped in a dashboard.
                events.event(TrackEvents.INTRO_MODE_PEEK, mapOf("mode" to it.titleKey))
            }
        }
    }
    Caption(stringResource(mode.subtitle))
    Surface(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.background,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
    ) {
        Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            samples.lesson1.take(SAMPLE_ROWS).forEach { word ->
                when (mode) {
                    Intro.Mode.VOCAB_LIST -> Text("${word.kana}  ·  ${word.translation}")
                    Intro.Mode.FLASHCARDS -> Text(word.kana, style = MaterialTheme.typography.headlineSmall)
                    Intro.Mode.PRACTICE -> Text("${word.kana}  →  ${word.translation}")
                    Intro.Mode.MATCH -> Text("${word.kana}  —  ${word.translation}")
                    Intro.Mode.LEARN -> Text(word.kana.toList().joinToString(" "))
                }
            }
        }
    }
    Caption(stringResource(R.string.many_ways_to_learn_all_of_them_fun))
}

private const val SAMPLE_ROWS = 3

/** Card 4: the Challenge ladder, plus the earned unlock in its own tinted panel. */
@Composable
private fun ChallengeCard(
    lesson: Int?,
    stepper: Int,
    lessonCount: Int,
    questionsPerChallenge: Int,
    passScore: Int,
    freeLessonLimit: Int,
    onNo: () -> Unit,
    onYes: () -> Unit,
    onStepper: (Int) -> Unit
) {
    Heading(stringResource(R.string.challenge))
    // Three explicit states, as the real ladder: passed 3 stars, open (numbered, no padlock), locked.
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("1  ★★★", "2  ☆☆☆", "3").forEachIndexed { i, text ->
            Surface(
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.background,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
            ) {
                Row(
                    Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(text)
                    if (i == 2) {
                        Icon(
                            Icons.Filled.Lock,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
    Caption(
        stringResource(R.string.arg_questions_a_rung, questionsPerChallenge.toString()) + "  ·  " +
            stringResource(R.string.arg_pct_to_pass_up_to_three_stars, passScore.toString())
    )
    Caption(stringResource(R.string.pass_one_and_the_next_opens))
    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.tertiaryContainer, RoundedCornerShape(12.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            stringResource(R.string.unlock_more_for_free),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onTertiaryContainer
        )
        Text(
            stringResource(
                R.string.three_star_every_challenge_in_lessons_1_arg_and_all_8f2191d,
                freeLessonLimit.toString(),
                stringResource(R.string.beginning_1)
            ),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onTertiaryContainer,
            textAlign = TextAlign.Center
        )
    }
    Question(stringResource(R.string.studied_minna_no_nihongo_before))
    IntroChip(stringResource(R.string.no_starting_fresh), lesson == 0, onClick = onNo)
    IntroChip(stringResource(R.string.yes_up_to_lesson_arg, stepper.toString()), (lesson ?: 0) > 0, onClick = onYes)
    if ((lesson ?: 0) > 0) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledIconButton(
                onClick = { onStepper((stepper - 1).coerceAtLeast(1)) },
                colors = IconButtonDefaults.filledTonalIconButtonColors()
            ) { Text("−") }
            Text(stringResource(R.string.lesson_arg, stepper.toString()), style = MaterialTheme.typography.titleMedium)
            FilledIconButton(
                onClick = { onStepper((stepper + 1).coerceAtMost(lessonCount)) },
                colors = IconButtonDefaults.filledTonalIconButtonColors()
            ) { Text("+") }
        }
    }
}

/** Card 5: Today deals the next rung's words; asks why they are learning. */
@Composable
private fun TodayCard(samples: IntroSamples, goal: String?, onSelect: (String) -> Unit) {
    samples.lesson1.firstOrNull()?.let {
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.background,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
        ) { Box(Modifier.padding(16.dp)) { WordFace(it) } }
    }
    Text(
        stringResource(R.string.today_deals_exactly_the_words_your_next_challenge_will_ask),
        textAlign = TextAlign.Center
    )
    Caption(stringResource(R.string.the_same_deck_sits_on_your_lock_screen_home_screen_and_watch))
    Question(stringResource(R.string.why_are_you_learning))
    Intro.Goal.entries.forEach { IntroChip(stringResource(it.title), goal == it.id) { onSelect(it.id) } }
}

/** Card 6: the soft opt-in. Only a yes reaches the system permission prompt (the caller's job). */
@Composable
private fun RemindersCard(onAnswer: (Boolean) -> Unit) {
    Heading(stringResource(R.string.never_lose_a_streak))
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.one_reminder_only_on_days_you_haven_t_studied_yet))
        Text(stringResource(R.string.nothing_at_all_once_you_re_done_for_the_day))
        Text(stringResource(R.string.pick_the_time_or_turn_it_off_in_settings))
    }
    Button(onClick = { onAnswer(true) }, Modifier.fillMaxWidth()) { Text(stringResource(R.string.remind_me)) }
    TextButton(onClick = { onAnswer(false) }) { Text(stringResource(R.string.not_now)) }
}
