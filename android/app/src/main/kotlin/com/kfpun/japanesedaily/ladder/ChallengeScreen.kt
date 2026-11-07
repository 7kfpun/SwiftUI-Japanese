@file:OptIn(
    androidx.compose.material3.ExperimentalMaterial3Api::class,
    androidx.compose.foundation.layout.ExperimentalLayoutApi::class
)

package com.kfpun.japanesedaily.ladder

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.audio.LocalPronouncer
import com.kfpun.japanesedaily.audio.StopSoundOnExit
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.progress.ChallengeResult
import com.kfpun.japanesedaily.data.progress.WordStage
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.lessons.LessonScreenFrame
import com.kfpun.japanesedaily.lessons.LessonSoundToggle
import com.kfpun.japanesedaily.lessons.LessonsEnv
import com.kfpun.japanesedaily.lessons.LessonsNav
import com.kfpun.japanesedaily.lessons.SectionLabel
import com.kfpun.japanesedaily.lessons.StarRow
import com.kfpun.japanesedaily.lessons.VForm
import com.kfpun.japanesedaily.lessons.rememberPref
import com.kfpun.japanesedaily.ui.ScrollIfShort
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.AudioPromptGlyph
import com.kfpun.japanesedaily.ui.components.PrimaryPillButton
import com.kfpun.japanesedaily.ui.components.QuizOptionButton
import com.kfpun.japanesedaily.ui.components.QuizPromptPanel
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.accentPlate
import com.kfpun.japanesedaily.ui.components.cardChrome
import com.kfpun.japanesedaily.ui.glyphStyle
import kotlinx.coroutines.delay

private const val AUTO_PLAY_FORM_MIN_DP = 56
private const val PROMPT_SIZE = 38

/**
 * One run of a challenge (port of `ChallengeView`): briefing, then a bounded set of questions, then the result. The
 * result is `model.isDone`, not a phase, so no state bug can show a score without the questions. `challenge_start`
 * fires from the briefing's button, a result is recorded once, and no ad hook ever fires mid-run.
 */
@Composable
fun ChallengeScreen(
    lessonNumber: Int,
    startIndex: Int,
    env: LessonsEnv,
    nav: LessonsNav,
    modifier: Modifier = Modifier
) {
    val container = env.container
    val lesson = remember(lessonNumber, env.language) { env.lesson(lessonNumber) }
    val total = remember(lesson) { Challenge.count(lesson.entries.size) }
    var index by remember { mutableIntStateOf(startIndex.coerceIn(1, total)) }
    // Bumped to rebuild the model: a retry or the next rung is a fresh run with fresh questions and voices.
    var runKey by remember { mutableIntStateOf(0) }
    val model = remember(index, runKey) { ChallengeModel(lessonNumber, index, total, lesson.entries) }
    var playing by remember(index, runKey) { mutableStateOf(false) }
    var startedAt by remember(index, runKey) { mutableStateOf(0L) }
    var recorded by remember(index, runKey) { mutableStateOf(false) }
    var justEarned by remember { mutableStateOf(false) }
    var resultsTick by remember { mutableIntStateOf(0) }
    val pronouncer = LocalPronouncer.current
    val soundOn = rememberPref(Pref.soundOn, container).value
    StopSoundOnExit()

    val byIndex by produceState<Map<Int, ChallengeResult>>(emptyMap(), lessonNumber, resultsTick) {
        value = container.progress.challengesByIndex(lessonNumber)
    }

    LaunchedEffect(index) {
        Track.screen(TrackScreens.CHALLENGE, mapOf("lesson" to lessonNumber, "index" to index))
    }

    // Persist once: `isDone` can re-compose and a second record would inflate `attempts`.
    LaunchedEffect(model, model.isDone) {
        if (!model.isDone || recorded || model.questions.isEmpty()) return@LaunchedEffect
        recorded = true
        val earnedBefore = container.progress.hasEarnedFirstGroup()
        container.progress.recordChallenge(lessonNumber, model.index, model.scorePercent)
        resultsTick++
        Track.event(
            TrackEvents.CHALLENGE_COMPLETE,
            mapOf(
                "lesson" to lessonNumber,
                "index" to model.index,
                "score" to model.scorePercent,
                "stars" to model.stars,
                "passed" to model.passed
            )
        )
        // Before the prompts: an unlock just earned outranks anything we want from the learner.
        if (!earnedBefore && container.progress.hasEarnedFirstGroup()) {
            justEarned = true
            Track.event(TrackEvents.EARNED_FIRST_GROUP, mapOf("lesson" to lessonNumber, "index" to model.index))
            return@LaunchedEffect
        }
        if (model.passed) container.rating.onRungPassed(container.progress.totalPassed())
    }

    // The way out: an abandon past question 1, or the interstitial hook for a finished run. Never mid-run.
    val latestModel by rememberUpdatedState(model)
    DisposableEffect(Unit) {
        onDispose {
            val m = latestModel
            if (!m.isDone && m.current > 0) {
                Track.event(
                    TrackEvents.CHALLENGE_ABANDON,
                    mapOf(
                        "lesson" to lessonNumber,
                        "index" to m.index,
                        "question" to m.current + 1,
                        "of" to m.questions.size,
                        "correct" to m.correct
                    )
                )
            }
            if (m.isDone) {
                container.onChallengeFinished()
            }
        }
    }

    fun autoPlay(q: ChallengeQuestion?) {
        q ?: return
        // An audio prompt always speaks: the clip is the question. A translation prompt never does.
        if (q.from.isAudio || (soundOn && VForm.promptAudioSafe(q.from, q.to))) pronouncer.speak(q.answer, q.voice)
    }

    LaunchedEffect(model.current, playing) { if (playing) autoPlay(model.question) }

    LessonScreenFrame(
        stringResource(R.string.challenge_arg, model.index.toString()),
        onBack = { nav.pop() },
        modifier = modifier,
        actions = { LessonSoundToggle(container) }
    ) {
        when {
            model.isDone -> ResultContent(
                model = model,
                total = total,
                byIndex = byIndex,
                onSpeak = { pronouncer.speak(it) },
                onRetry = {
                    Track.event(
                        TrackEvents.CHALLENGE_RETRY,
                        mapOf("lesson" to lessonNumber, "index" to model.index, "previous_score" to model.scorePercent)
                    )
                    runKey++
                },
                onNext = if (model.index < total) {
                    {
                        Track.event(
                            TrackEvents.CHALLENGE_NEXT,
                            mapOf("lesson" to lessonNumber, "from_index" to index, "stars" to model.stars)
                        )
                        index += 1
                    }
                } else {
                    null
                },
                onDone = {
                    Track.event(
                        TrackEvents.CHALLENGE_DONE_TAPPED,
                        mapOf("lesson" to lessonNumber, "index" to model.index, "passed" to model.passed)
                    )
                    nav.pop()
                },
                onCheer = { pronouncer.speakCheer(it.key, it.text) },
                soundOn = soundOn
            )

            !playing -> Briefing(model, lesson.entries, total, byIndex[index]) {
                startedAt = System.currentTimeMillis()
                playing = true
                Track.event(
                    TrackEvents.CHALLENGE_START,
                    mapOf("lesson" to lessonNumber, "index" to index, "questions" to model.questions.size)
                )
            }

            else -> ScrollIfShort {
                Play(model, startedAt, onPick = { i, q ->
                    model.choose(i)
                    Track.event(
                        TrackEvents.CHALLENGE_ANSWER,
                        mapOf(
                            "lesson" to lessonNumber,
                            "index" to model.index,
                            "from" to q.from.label,
                            "to" to q.to.label,
                            "correct" to q.isCorrect(i)
                        )
                    )
                    // A ladder miss demotes the word's Practice stage, so "missed words come back in Practice" is true.
                    if (!q.isCorrect(i) && container.practice.stage(q.answer.id).raw >= WordStage.Recognized.raw) {
                        container.practice.set(WordStage.Seen, q.answer.id)
                    }
                    if (soundOn || q.from.isAudio) pronouncer.speak(q.answer, q.voice)
                }, onReplay = { pronouncer.speak(it.answer, it.voice) })
            }
        }
    }

    if (justEarned) {
        ModalBottomSheet(onDismissRequest = { justEarned = false }, containerColor = Theme.colors.surface) {
            EarnedUnlockCard(onDone = { justEarned = false })
        }
    }
}

// region Briefing

@Composable
private fun Briefing(
    model: ChallengeModel,
    words: List<Vocab>,
    total: Int,
    best: ChallengeResult?,
    onStart: () -> Unit
) {
    val index = model.index
    val q = model.questions.size
    val w2 = Challenge.allowedWrong(q, 90)
    val w1 = Challenge.allowedWrong(q, Challenge.PASS_SCORE)
    val newWords = remember(words, index) { Challenge.newWords(words, index) }
    val reviewCount = maxOf(0, q - newWords.size)
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                stringResource(R.string.rung_arg_of_arg, index.toString(), total.toString()).uppercase(),
                style = Theme.text.caption.copy(fontWeight = FontWeight.SemiBold),
                color = Theme.colors.inkSecondary
            )
            Text(
                stringResource(R.string.challenge_arg, index.toString()),
                style = Theme.title(Theme.text.title, FontWeight.Bold),
                color = Theme.colors.ink
            )
            Text(
                if (index == 1) {
                    stringResource(R.string.arg_questions_recognise_each_new_word, q.toString())
                } else {
                    stringResource(R.string.arg_mixed_questions_recall_listening_and_kanji_can_a_2ab7a4a, q.toString())
                },
                style = Theme.text.subheadline,
                color = Theme.colors.inkSecondary
            )
        }
        // The words this rung introduces, each guaranteed a question; the review share is a count, not a list.
        Column(
            Modifier.fillMaxWidth().cardChrome().padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionLabel(stringResource(R.string.new_in_this_challenge))
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                for (word in newWords) {
                    Text(
                        if (word.displaysKanji) word.kanji else word.kana,
                        style = Theme.jp(Theme.text.subheadline),
                        color = Theme.colors.ink,
                        modifier = Modifier
                            .background(Theme.colors.canvas, Theme.rounded(Theme.Radius.inset))
                            .padding(horizontal = 11.dp, vertical = 6.dp)
                    )
                }
            }
            Text(
                if (reviewCount > 0) {
                    stringResource(R.string.each_one_is_asked_plus_arg_from_earlier_words, reviewCount.toString())
                } else {
                    stringResource(R.string.each_one_is_asked)
                },
                style = Theme.text.caption,
                color = Theme.colors.inkSecondary
            )
        }
        // The star bands in misses, from this run's real question count.
        Column(
            Modifier.fillMaxWidth().cardChrome().padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionLabel(stringResource(R.string.how_stars_work))
            StarRule(3, stringResource(R.string.all_correct))
            if (w2 > 0) StarRule(2, stringResource(R.string.up_to_arg_wrong, w2.toString()))
            if (w1 > w2) StarRule(1, stringResource(R.string.up_to_arg_wrong, w1.toString()))
        }
        if (best != null && best.bestScore > 0 && best.stars < 3) {
            Row(
                Modifier.fillMaxWidth().accentPlate().padding(14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        stringResource(
                            R.string.last_time_arg_pct_arg,
                            best.bestScore.toString(),
                            best.stars.toString()
                        ),
                        style = Theme.text.subheadline.copy(fontWeight = FontWeight.Medium),
                        color = Theme.colors.ink
                    )
                    Text(
                        stringResource(R.string.a_clean_run_fills_all_3),
                        style = Theme.text.caption,
                        color = Theme.colors.accent
                    )
                }
                StarRow(best.stars, sizeSp = 12)
            }
        }
        PrimaryPillButton(onStart, Modifier.padding(top = 4.dp)) {
            Text(stringResource(R.string.start_the_challenge), style = Theme.text.headline)
        }
    }
}

@Composable
private fun StarRule(stars: Int, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(11.dp)) {
        StarRow(stars, sizeSp = 12)
        Text(text, style = Theme.text.subheadline, color = Theme.colors.ink)
    }
}

// endregion

// region The run

@Composable
private fun Play(
    model: ChallengeModel,
    startedAt: Long,
    onPick: (Int, ChallengeQuestion) -> Unit,
    onReplay: (ChallengeQuestion) -> Unit
) {
    val question = model.question ?: return
    val total = maxOf(model.questions.size, 1)
    val wrongs = model.current + (if (model.picked == null) 0 else 1) - model.correct
    val potentialStars = Challenge.stars(Challenge.percent(total - wrongs, total))
    val seconds by produceState(0L, startedAt) {
        while (true) {
            value = maxOf(0L, (System.currentTimeMillis() - startedAt) / 1000)
            delay(1000)
        }
    }
    val picked = model.picked
    val showingWrong = picked != null && !question.isCorrect(picked)
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "%02d:%02d".format(seconds / 60, seconds % 60),
                style = Theme.text.footnote.copy(fontWeight = FontWeight.Medium),
                color = Theme.colors.inkSecondary,
                modifier = Modifier.weight(1f)
            )
            // The stars are a stake, not a score: labelled so three greyed stars do not read as a result.
            Text(
                stringResource(R.string.still_winnable),
                style = Theme.text.caption2,
                color = Theme.colors.inkSecondary,
                modifier = Modifier.padding(end = 6.dp)
            )
            StarRow(potentialStars, sizeSp = 13)
        }
        Pips(model.current, model.questions.size)
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                promptLabel(question),
                style = Theme.text.footnote.copy(fontWeight = FontWeight.SemiBold),
                color = Theme.colors.inkSecondary,
                textAlign = TextAlign.Center
            )
            QuizPromptPanel(onTap = { onReplay(question) }, Modifier.heightIn(min = 150.dp)) {
                if (question.from.isAudio) {
                    AudioPromptGlyph()
                } else {
                    Text(
                        question.from.value(question.answer),
                        style = if (question.from == VForm.Translation) {
                            Theme.text.title.copy(fontWeight = FontWeight.SemiBold)
                        } else {
                            glyphStyle(question.from.isJapanese, PROMPT_SIZE)
                        },
                        color = Theme.colors.ink,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp)
                    )
                }
            }
            Text(
                if (question.from.isAudio) {
                    stringResource(
                        R.string.tap_to_hear_it_again
                    )
                } else {
                    stringResource(R.string.tap_to_hear_it)
                },
                style = Theme.text.caption2,
                color = Theme.colors.inkTertiary
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            question.options.forEachIndexed { i, option ->
                QuizOptionButton(
                    text = question.to.value(option),
                    index = i,
                    picked = picked,
                    isAnswer = question.isCorrect(i),
                    onClick = { onPick(i, question) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = AUTO_PLAY_FORM_MIN_DP.dp),
                    textStyle = if (question.to.isJapanese) Theme.jp(Theme.text.title3) else Theme.text.headline
                )
            }
        }
        Text(
            riskLine(question, picked, wrongs, potentialStars),
            style = Theme.text.footnote,
            // Red only for a wrong answer's correction: the running stake is commentary, not feedback.
            color = if (showingWrong) Theme.colors.wrong else Theme.colors.inkSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth()
        )
        Box(Modifier.fillMaxWidth().heightIn(min = 54.dp), contentAlignment = Alignment.Center) {
            if (picked != null) {
                PrimaryPillButton({ model.advance() }) {
                    Text(
                        if (model.isLastQuestion) stringResource(R.string.finish) else stringResource(R.string.next),
                        style = Theme.text.headline
                    )
                }
            }
        }
    }
}

@Composable
private fun Pips(current: Int, count: Int) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        for (i in 0 until count) {
            Box(
                Modifier
                    .weight(1f)
                    .height(4.dp)
                    .background(
                        when {
                            i < current -> Theme.colors.ink
                            i == current -> Theme.colors.inkSecondary
                            else -> Theme.colors.line
                        },
                        CircleShape
                    )
            )
        }
    }
}

@Composable
private fun promptLabel(q: ChallengeQuestion): String = when {
    q.from.isAudio -> stringResource(R.string.hear_it_pick_the_word)
    q.from == VForm.Translation -> stringResource(R.string.which_word_means_this)
    q.to == VForm.Kanji -> stringResource(R.string.which_kanji_writes_this_reading)
    else -> stringResource(R.string.what_does_this_word_mean)
}

/** The stake between the options and Next: what the run still holds before an answer, the verdict after one. */
@Composable
private fun riskLine(q: ChallengeQuestion, picked: Int?, wrongs: Int, potentialStars: Int): String {
    if (picked == null) {
        return when {
            wrongs == 0 -> stringResource(R.string.all_correct_so_far_keep_it_up_for_3)

            potentialStars > 0 -> stringResource(
                R.string.arg_wrong_finish_clean_to_keep_arg,
                wrongs.toString(),
                potentialStars.toString()
            )

            else -> stringResource(R.string.no_stars_this_run_you_can_retry_right_after)
        }
    }
    if (q.isCorrect(picked)) return stringResource(R.string.correct)
    return stringResource(R.string.the_answer_is_arg, q.to.value(q.answer))
}

// endregion

// region Result

@Composable
private fun ResultContent(
    model: ChallengeModel,
    total: Int,
    byIndex: Map<Int, ChallengeResult>,
    onSpeak: (Vocab) -> Unit,
    onRetry: () -> Unit,
    onNext: (() -> Unit)?,
    onDone: () -> Unit,
    onCheer: (Cheer) -> Unit,
    soundOn: Boolean
) {
    // Chosen once per result screen, and spoken only when the sound is on: the text is the part being taught.
    val phrase = remember(model) { Cheer.next(model.stars, model.passed) }
    LaunchedEffect(phrase) { if (phrase != null && soundOn) onCheer(phrase) }
    val title = when (model.stars) {
        3 -> stringResource(R.string.perfect_3)
        2 -> stringResource(R.string.so_close_to_perfect)
        1 -> stringResource(R.string.passed)
        else -> stringResource(R.string.try_again)
    }
    val blurb = when {
        model.passed && model.index >= total -> stringResource(R.string.lesson_complete)
        model.stars == 3 -> stringResource(R.string.full_marks_the_next_challenge_is_open)
        model.passed -> stringResource(R.string.missed_words_will_come_back_in_practice)
        else -> stringResource(R.string.arg_pct_needed_to_pass_try_again, Challenge.PASS_SCORE.toString())
    }
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp).navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        StarRow(model.stars, sizeSp = 34, modifier = Modifier.padding(top = 12.dp))
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                title,
                style = Theme.title(Theme.text.title2, FontWeight.Bold),
                color = Theme.colors.ink,
                textAlign = TextAlign.Center
            )
            Text(blurb, style = Theme.text.subheadline, color = Theme.colors.inkSecondary, textAlign = TextAlign.Center)
        }
        if (phrase != null) CheerLine(phrase, model) { onCheer(phrase) }
        Stats(model, total, byIndex)
        if (model.missed.isNotEmpty()) {
            Column(
                Modifier.fillMaxWidth().cardChrome().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    stringResource(R.string.review_these),
                    style = Theme.title(Theme.text.subheadline),
                    color = Theme.colors.ink
                )
                for (word in model.uniqueMissed) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .clickable(role = Role.Button) {
                                onSpeak(word)
                                Track.event(
                                    TrackEvents.CHALLENGE_REVIEW_PLAY,
                                    mapOf("lesson" to model.lessonNumber, "index" to model.index)
                                )
                            },
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        SymbolIcon(
                            R.drawable.ic_volume_up,
                            Theme.colors.accent,
                            Theme.text.footnote.fontSize.value.toInt()
                        )
                        Text(word.kana, style = Theme.jp(Theme.text.title3), color = Theme.colors.ink)
                        Text(
                            word.translation,
                            style = Theme.text.subheadline,
                            color = Theme.colors.inkSecondary,
                            textAlign = TextAlign.End,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
                Text(
                    stringResource(R.string.tap_any_word_to_hear_it),
                    style = Theme.text.caption2,
                    color = Theme.colors.inkTertiary
                )
            }
        }
        WhatIsLeft(model, total)
        // After a pass the forward step leads; after a miss, Try again leads and no forward button is offered.
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (model.passed && onNext != null) {
                PrimaryPillButton(onNext) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        SymbolIcon(
                            R.drawable.ic_chevron_right,
                            Theme.colors.onAccent,
                            Theme.text.headline.fontSize.value.toInt()
                        )
                        Text(
                            stringResource(R.string.keep_going_challenge_arg, (model.index + 1).toString()),
                            style = Theme.text.headline
                        )
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                ResultButton(
                    stringResource(R.string.try_again),
                    prominent = !model.passed,
                    onClick = onRetry,
                    modifier = Modifier.weight(1f)
                )
                ResultButton(
                    if (model.passed) stringResource(R.string.done) else stringResource(R.string.back),
                    prominent = model.passed && model.index >= total,
                    onClick = onDone,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun ResultButton(text: String, prominent: Boolean, onClick: () -> Unit, modifier: Modifier) {
    val shape = Theme.rounded(Theme.Radius.pill)
    Box(
        modifier
            .heightIn(min = 48.dp)
            .background(if (prominent) Theme.colors.accent else Theme.colors.surface, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text,
            style = Theme.text.headline,
            color = if (prominent) Theme.colors.onAccent else Theme.colors.accent,
            textAlign = TextAlign.Center
        )
    }
}

/** This run, the rung's best, and the lesson's star tally: whether to retry, move on or close the lesson. */
@Composable
private fun Stats(model: ChallengeModel, total: Int, byIndex: Map<Int, ChallengeResult>) {
    val best = maxOf(byIndex[model.index]?.bestScore ?: 0, model.scorePercent)
    val lessonStars = byIndex.values.sumOf { it.stars }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        StatCard(stringResource(R.string.this_run), "${model.scorePercent}%", Theme.colors.ink, Modifier.weight(1f))
        StatCard(stringResource(R.string.best), "$best%", Theme.colors.ink, Modifier.weight(1f))
        // Accented: the other two describe this run, this one the lesson.
        StatCard(
            stringResource(R.string.lesson_stars),
            "$lessonStars / ${total * 3}",
            Theme.colors.accent,
            Modifier.weight(1f)
        )
    }
}

@Composable
private fun StatCard(label: String, value: String, tint: androidx.compose.ui.graphics.Color, modifier: Modifier) {
    Column(modifier.cardChrome(Theme.Radius.row).padding(12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(label, style = Theme.text.caption, color = Theme.colors.inkSecondary)
        Text(value, style = Theme.title(Theme.text.title3), color = tint, maxLines = 1)
    }
}

/** What is left to win, stated where the retry button is: an invitation, never a verdict. */
@Composable
private fun WhatIsLeft(model: ChallengeModel, total: Int) {
    val passed = model.passed
    val short = maxOf(0, Challenge.PASS_SCORE - model.scorePercent)
    val (title, body) = when {
        model.stars >= 3 -> stringResource(R.string.every_word_in_this_challenge_stuck) to
            if (model.index >= total) {
                stringResource(R.string.lesson_complete)
            } else {
                stringResource(R.string.challenge_arg_is_open, (model.index + 1).toString())
            }

        passed -> stringResource(R.string.a_clean_run_fills_all_3) to
            stringResource(R.string.your_best_only_goes_up_replaying_never_costs_a_star_you_have)

        else -> stringResource(R.string.arg_pct_short_of_passing, short.toString()) to
            stringResource(R.string.missed_words_will_come_back_in_practice)
    }
    Row(
        Modifier.fillMaxWidth().accentPlate(
            tint = if (passed) Theme.colors.accent else Theme.colors.streak
        ).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = Theme.text.subheadline.copy(fontWeight = FontWeight.Medium), color = Theme.colors.ink)
            Text(body, style = Theme.text.caption, color = Theme.colors.inkSecondary)
        }
        StarRow(model.stars, sizeSp = 12)
    }
}

/** The phrase in Japanese with its reading and gloss; tapping says the same phrase again (never a new one). */
@Composable
private fun CheerLine(phrase: Cheer, model: ChallengeModel, onTap: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button) {
                onTap()
                Track.event(TrackEvents.CHEER_REPLAY, mapOf("stars" to model.stars, "passed" to model.passed))
            }
            .padding(vertical = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(phrase.text, style = Theme.jp(Theme.text.title), color = Theme.colors.ink)
        Text(
            "${phrase.romaji} · ${stringResource(cheerMeaning(phrase))}",
            style = Theme.text.footnote,
            color = Theme.colors.inkSecondary,
            textAlign = TextAlign.Center
        )
    }
}

private fun cheerMeaning(phrase: Cheer): Int = when (phrase.meaning) {
    "Amazing" -> R.string.amazing
    "Well done" -> R.string.well_done
    "Nice" -> R.string.nice
    "You did it" -> R.string.you_did_it
    "You're good at this" -> R.string.you_re_good_at_this
    "That's the spirit" -> R.string.that_s_the_spirit
    "Full marks" -> R.string.full_marks
    "Perfect" -> R.string.perfect
    "Keep at it" -> R.string.keep_at_it
    "So close" -> R.string.so_close
    "It's all right" -> R.string.it_s_all_right
    "Once more" -> R.string.once_more
    "You'll get it next time" -> R.string.you_ll_get_it_next_time
    "Don't give up" -> R.string.don_t_give_up
    "A little further" -> R.string.a_little_further
    else -> R.string.let_s_keep_going
}

// endregion

/** Shown once, the moment the first band is earned. Nothing to sell and nothing to ask. */
@Composable
internal fun EarnedUnlockCard(onDone: () -> Unit) {
    val band = com.kfpun.japanesedaily.lessons.Gating.earnableGroup()
    val through = band?.last ?: com.kfpun.japanesedaily.lessons.Gating.freeLessonLimit()
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp).navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        SymbolIcon(R.drawable.ic_lock_open, Theme.colors.streak, EARNED_ICON_SP)
        Text(
            stringResource(
                R.string.arg_unlocked,
                band?.let { stringResource(com.kfpun.japanesedaily.lessons.groupLabel(it.name)) } ?: ""
            ),
            style = Theme.title(Theme.text.title2, FontWeight.Bold),
            color = Theme.colors.ink,
            textAlign = TextAlign.Center
        )
        Text(
            stringResource(R.string.three_stars_on_every_challenge_so_far_lessons_up_to_0bdec0b, through.toString()),
            style = Theme.text.subheadline,
            color = Theme.colors.inkSecondary,
            textAlign = TextAlign.Center
        )
        PrimaryPillButton(onDone, Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.keep_going), style = Theme.text.headline)
        }
    }
}

private const val EARNED_ICON_SP = 44
