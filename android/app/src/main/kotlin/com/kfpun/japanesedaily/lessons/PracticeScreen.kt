@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.kfpun.japanesedaily.lessons

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.audio.LocalPronouncer
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.progress.WordStage
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.ui.Adaptive
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.PrimaryPillButton
import com.kfpun.japanesedaily.ui.components.StampSpec
import com.kfpun.japanesedaily.ui.components.SwipeCard
import com.kfpun.japanesedaily.ui.components.SwipeOptionChip
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.cardSwipe
import com.kfpun.japanesedaily.ui.components.rememberCardSwipeState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val REVEAL_DELAY_MILLIS = 600L
private const val CORRECT_EXIT_MILLIS = 500
private const val CARD_MIN_HEIGHT_DP = 230
private const val MIXED_DIM = 0.5f
private const val DISABLED_DIM = 0.35f

/** The three faces by their on-screen names. [VForm.label] stays the analytics key. */
@Composable
internal fun faceName(f: VForm): String = when (f) {
    VForm.Kana -> stringResource(R.string.kana)
    VForm.Kanji -> stringResource(R.string.kanji)
    VForm.Translation -> stringResource(R.string.meaning_19cd7d1)
    else -> f.label
}

/** What the current question asks, in words. */
@Composable
private fun promptLabel(model: PracticeModel): String = when {
    model.questionFrom == VForm.Translation -> stringResource(R.string.which_word_means_this)

    model.questionTo == VForm.Kanji -> stringResource(R.string.which_kanji_writes_this_reading)

    // Kanji to kana: the chips are readings, not meanings.
    model.questionTo == VForm.Kana -> stringResource(R.string.how_is_this_kanji_read)

    else -> stringResource(R.string.what_does_this_word_mean)
}

/**
 * Practice (port of `PracticeView`): one screen, one card. **Only the app scores**: a left or right swipe
 * always means *this answer*. A right answer plays its badge and moves on; a **wrong** one opens the card to
 * teach (meaning, reading, example) and waits for Next. Hold the card to peek: the back says "this one comes
 * back", and a right answer afterwards moves nothing up the ladder. Leaving calls `onLeavePractice`.
 */
@Composable
fun PracticeScreen(lessonNumber: Int, env: LessonsEnv, nav: LessonsNav, modifier: Modifier = Modifier) {
    val container = env.container
    // The stored pair is read before the model exists: it needs it to deal the first card.
    val pair by produceState<Triple<VForm, VForm, Boolean>?>(null) {
        val from = PracticeModel.face(container.prefs.get(Pref.practiceFrom)) ?: VForm.Kana
        val to = PracticeModel.face(container.prefs.get(Pref.practiceTo)) ?: VForm.Translation
        value = Triple(from, to, container.prefs.get(Pref.practiceMixed))
    }
    val stored = pair
    LessonScreenFrame(stringResource(R.string.practice), onBack = {
        nav.pop()
    }, modifier = modifier, scrollIfShort = true) {
        if (stored != null) PracticeContent(lessonNumber, env, stored)
    }
}

@Composable
private fun PracticeContent(lessonNumber: Int, env: LessonsEnv, stored: Triple<VForm, VForm, Boolean>) {
    val container = env.container
    val pronouncer = LocalPronouncer.current
    val exits = LocalLessonExits.current
    val scope = rememberCoroutineScope()
    val soundOn = rememberPref(Pref.soundOn, container).value
    val model = remember(lessonNumber) {
        PracticeModel(
            env.lesson(lessonNumber).entries,
            container.practice.asStageStore(),
            stored.first,
            stored.second,
            stored.third,
            persistPair = { f, t, mixed ->
                container.scope.launch {
                    container.prefs.set(Pref.practiceFrom, f.label)
                    container.prefs.set(Pref.practiceTo, t.label)
                    container.prefs.set(Pref.practiceMixed, mixed)
                }
            }
        )
    }
    val swipe = rememberCardSwipeState()
    var revealed by remember { mutableStateOf(false) }
    var showKana by remember { mutableStateOf(false) }
    var flipped by remember { mutableStateOf(false) }

    // Whether *this* question was peeked at. Turning the card back over does not unsee the answer.
    var peeked by remember { mutableStateOf(false) }
    var lastCorrect by remember { mutableStateOf<Boolean?>(null) }
    var animating by remember { mutableStateOf(false) }
    var showPairSheet by remember { mutableStateOf(false) }
    val angle = rememberFlip(flipped)

    /** Speaks only when hearing the word does not answer the question (`VForm.promptAudioSafe`). */
    fun autoPlay() {
        val item = model.current ?: return
        if (soundOn && VForm.promptAudioSafe(model.questionFrom, model.questionTo)) pronouncer.speak(item.vocab)
    }

    fun afterAdvance() {
        revealed = false
        showKana = false
        flipped = false
        peeked = false
        swipe.reset()
        animating = false
        if (model.isDone) {
            Track.event(TrackEvents.PRACTICE_DONE, mapOf("total" to model.sessionTotal, "lesson" to lessonNumber))
        } else {
            autoPlay() // explicit: a re-queued word can repeat
        }
    }

    fun advanceAfterReveal() {
        if (animating) return
        animating = true
        swipe.fling(toRight = true) {
            model.resolve(credited = !peeked)
            afterAdvance()
        }
    }

    fun decide(side: Int) {
        if (animating || model.picked != null || revealed || flipped || model.options.size <= side) return
        animating = true
        model.choose(side)
        val correct = model.isCorrectOption(side)
        // `from`/`to` ride along: an answer in kana to meaning is not the same exercise as meaning to kanji.
        Track.event(
            TrackEvents.PRACTICE_ANSWER,
            mapOf(
                "correct" to correct,
                "lesson" to lessonNumber,
                "from" to model.questionFrom.label,
                "to" to model.questionTo.label
            )
        )
        lastCorrect = correct
        if (correct) {
            // A longer wait than the exit itself, so the verdict badge reads first.
            swipe.fling(toRight = side == 1, delayMillis = CORRECT_EXIT_MILLIS) {
                model.resolve(credited = !peeked)
                lastCorrect = null
                afterAdvance()
            }
        } else {
            // **Resolved on the way out, not here**: `resolve` grades *and* pops the queue, so calling it now
            // swapped the card to the next word before the reveal opened. Holding the card keeps `picked` set.
            scope.launch {
                delay(REVEAL_DELAY_MILLIS)
                lastCorrect = null
                revealed = true
                swipe.reset()
                animating = false
                val word = model.current?.vocab
                if (soundOn && word != null) pronouncer.speak(word)
            }
        }
    }

    LaunchedEffect(lessonNumber) {
        Track.screen(TrackScreens.PRACTICE, mapOf("lesson" to lessonNumber))
        container.prefs.markModeVisit(lessonNumber, LessonMode.PRACTICE)
        autoPlay()
    }
    // Any answered card is graded on the way out (`resolve` guards on `picked`, so an unanswered card grades
    // nothing), the last stage write lands, and the hook the ads ticket wires sees whether anything happened.
    DisposableEffect(model) {
        onDispose {
            if (model.picked != null) model.resolve(credited = !peeked)
            container.scope.launch { container.practice.flush() }
            exits.onLeavePractice(model.answered > 0)
        }
    }

    Box(Modifier.fillMaxSize()) {
        Column(
            Modifier.fillMaxSize().padding(16.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            val item = model.current
            if (item != null) {
                SessionBar(model.fractionDone)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StageLadder(model.stage(item.vocab), Modifier.weight(1f))
                    PairCapsule(model, enabled = model.picked == null) { showPairSheet = true }
                }
                // A swipe picks a side: the arrows point at the two option chips. No peek layers and no hint:
                // the direction is spelled out under each answer, and a stack would imply a deck, not a question.
                Box(
                    Modifier.weight(1f, fill = false).fillMaxWidth().heightIn(max = Adaptive.CARD_MAX_HEIGHT_DP.dp)
                ) {
                    PracticeCard(
                        model, item.vocab, angle, swipe, revealed, showKana, flipped,
                        onShowKana = {
                            Track.event(TrackEvents.PRACTICE_SHOW_KANA, mapOf("lesson" to lessonNumber))
                            showKana = true
                        },
                        onSpeakExample = {
                            pronouncer.speakExample(item.vocab)
                            Track.event(
                                TrackEvents.PLAY_EXAMPLE,
                                mapOf(
                                    "lesson" to lessonNumber,
                                    "surface" to "practice"
                                )
                            )
                        },
                        onSpeak = { pronouncer.speak(item.vocab) },
                        onHold = {
                            if (!revealed && model.picked == null) {
                                if (!peeked) {
                                    peeked = true
                                    Track.event(TrackEvents.PRACTICE_PEEK, mapOf("lesson" to lessonNumber))
                                }
                                flipped = true
                            }
                        },
                        onHoldEnd = { flipped = false },
                        canDrag = { model.picked == null && !animating && !revealed && !flipped },
                        canCommit = { !flipped },
                        onDecide = { decide(if (it) 1 else 0) }
                    )
                    lastCorrect?.let { AnswerBadge(it) }
                }
                // The two answers always take the same height, whichever one wraps (Min + fillMaxHeight on both).
                Row(
                    Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    for (side in 0..1) {
                        val opt = model.options.getOrNull(side)
                        Box(Modifier.weight(1f).fillMaxHeight()) {
                            SwipeOptionChip(
                                modifier = Modifier.fillMaxHeight(),
                                text = opt?.let { model.questionTo.value(it) }.orEmpty(),
                                side = side,
                                picked = model.picked,
                                isAnswer = opt?.id == item.vocab.id,
                                onClick = { decide(side) },
                                textStyle = if (model.questionTo.isJapanese) {
                                    Theme.jp(24.sp)
                                } else {
                                    Theme.text.title3.copy(fontWeight = FontWeight.SemiBold)
                                },
                                // The chevron says which way; this says it in words, for the first run.
                                hint = stringResource(if (side == 0) R.string.swipe_left else R.string.swipe_right)
                            )
                        }
                    }
                }
                // Only after a miss, and only as the way forward.
                if (revealed) {
                    PrimaryPillButton(onClick = ::advanceAfterReveal) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                stringResource(R.string.next),
                                style = Theme.title(Theme.text.headline),
                                color = Theme.colors.canvas
                            )
                            SymbolIcon(
                                R.drawable.ic_arrow_forward,
                                Theme.colors.canvas,
                                Theme.text.headline.fontSize.value.toInt()
                            )
                        }
                    }
                }
            } else {
                DeckDonePanel(
                    stringResource(
                        R.string.you_reviewed_arg_words,
                        model.sessionTotal.toString()
                    ),
                    onRestart = {
                        Track.event(
                            TrackEvents.PRACTICE_RESTART,
                            mapOf(
                                "lesson" to lessonNumber,
                                "total" to model.sessionTotal
                            )
                        )
                        model.restart()
                        revealed = false
                        swipe.reset()
                        autoPlay()
                    }
                )
            }
        }
    }

    if (showPairSheet) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { showPairSheet = false },
            sheetState = sheetState,
            containerColor = Theme.colors.canvas
        ) {
            LaunchedEffect(Unit) {
                // The denominator for `practice_pair`: opened-then-left-alone was invisible.
                Track.event(TrackEvents.PRACTICE_PAIR_OPEN, mapOf("lesson" to lessonNumber, "mixed" to model.mixed))
            }
            PracticePairSheet(model, lessonNumber)
        }
    }
}

/** The card itself: the question (or, once taught, the details), with the peek and the swipe on the card. */
@Composable
private fun PracticeCard(
    model: PracticeModel,
    vocab: Vocab,
    angle: androidx.compose.runtime.State<Float>,
    swipe: com.kfpun.japanesedaily.ui.components.CardSwipeState,
    revealed: Boolean,
    showKana: Boolean,
    flipped: Boolean,
    onShowKana: () -> Unit,
    onSpeakExample: () -> Unit,
    onSpeak: () -> Unit,
    onHold: () -> Unit,
    onHoldEnd: () -> Unit,
    canDrag: () -> Boolean,
    canCommit: () -> Boolean,
    onDecide: (Boolean) -> Unit
) {
    SwipeCard(
        Modifier
            .fillMaxSize()
            .flipped(angle)
            .holdGestures(onTap = onSpeak, onHold = onHold, onHoldEnd = onHoldEnd)
            .cardSwipe(swipe, canDrag = canDrag, canCommit = canCommit, decide = onDecide),
        drag = { swipe.offset },
        leftStamp = StampSpec(R.drawable.ic_arrow_back, Theme.colors.accent),
        rightStamp = StampSpec(R.drawable.ic_arrow_forward, Theme.colors.accent),
        showsStamps = model.picked == null && !flipped,
        hint = null
    ) {
        FlipFaces(
            angle,
            front = {
                Column(
                    Modifier.fillMaxWidth().heightIn(min = CARD_MIN_HEIGHT_DP.dp).padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    // Pinned to the top corner, not floated above the word.
                    if (!revealed) {
                        Text(
                            promptLabel(model),
                            style = Theme.text.footnote,
                            color = Theme.colors.inkSecondary,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    Spacer12()
                    if (revealed) {
                        // The teaching moment **replaces** the question: VocabFace already carries every form.
                        VocabFace(vocab, onSpeakExample)
                    } else {
                        Text(
                            model.questionFrom.value(vocab),
                            style = promptStyle(model.questionFrom, 44, Theme.text.largeTitle),
                            color = Theme.colors.ink,
                            textAlign = TextAlign.Center
                        )
                    }
                    if (!revealed && model.questionFrom == VForm.Kanji) {
                        // The reading, on request: a kanji prompt is unanswerable to someone who cannot read it yet.
                        Row(
                            Modifier
                                .padding(top = 12.dp)
                                .heightIn(min = 44.dp)
                                .background(Theme.colors.canvas, CircleShape)
                                .clickable(enabled = !showKana, role = Role.Button, onClick = onShowKana)
                                .padding(horizontal = 14.dp, vertical = 7.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            SymbolIcon(
                                if (showKana) R.drawable.ic_list else R.drawable.ic_visibility,
                                Theme.colors.ink,
                                Theme.text.subheadline.fontSize.value.toInt()
                            )
                            Text(
                                if (showKana) vocab.kana else stringResource(R.string.show_kana),
                                style = if (showKana) Theme.jp(18.sp) else Theme.text.subheadline,
                                color = Theme.colors.ink
                            )
                        }
                    }
                    Spacer12()
                    // The gesture is invisible until someone tries it: name what it gets you, not the mechanic.
                    if (!revealed) {
                        Text(
                            stringResource(R.string.long_press_to_see_details),
                            style = Theme.text.caption2,
                            color = Theme.colors.inkTertiary
                        )
                    }
                }
            },
            back = {
                Column(Modifier.fillMaxWidth().heightIn(min = CARD_MIN_HEIGHT_DP.dp).padding(20.dp)) {
                    // Top corner, where the front keeps its caption: the consequence is read on the way in.
                    Text(
                        stringResource(R.string.peeked_this_one_comes_back),
                        style = Theme.text.caption2,
                        color = Theme.colors.inkSecondary
                    )
                    Spacer12()
                    VocabFace(vocab, onSpeakExample)
                }
            }
        )
    }
}

@Composable
private fun Spacer12() = Box(Modifier.size(12.dp))

/** Session progress as a bar and a percentage: answer-weighted, so it moves on every correct answer. */
@Composable
private fun SessionBar(fraction: Double) {
    val percent = "${Math.round(fraction * 100).toInt()}%"
    Row(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = percent },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        CapsuleBar(fraction, Modifier.weight(1f), height = 4)
        Text(percent, style = Theme.text.caption2, color = Theme.colors.inkSecondary)
    }
}

/** Where a word stands on the Practice ladder: three dots and the rung's name. A readout, not a control. */
@Composable
fun StageLadder(stage: WordStage, modifier: Modifier = Modifier) {
    val rung = when (stage) {
        WordStage.Unseen, WordStage.Seen -> 1
        WordStage.Recognized -> 2
        WordStage.Memorized -> 3
    }
    val title = stringResource(
        when (stage) {
            WordStage.Unseen -> R.string.first_time
            WordStage.Seen -> R.string.seen
            WordStage.Recognized -> R.string.recognized
            WordStage.Memorized -> R.string.memorized
        }
    )
    Row(
        modifier.semantics(mergeDescendants = true) { contentDescription = "$title, $rung / 3" },
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            for (i in 1..3) {
                Box(
                    Modifier.size(6.dp).background(
                        if (i <=
                            rung
                        ) {
                            Theme.colors.accent
                        } else {
                            Theme.colors.line
                        },
                        CircleShape
                    )
                )
            }
        }
        Text(title, style = Theme.text.caption, color = Theme.colors.inkSecondary, maxLines = 1)
    }
}

/** The capsule naming the current pair, or the shuffle when mixed. Disabled mid-answer. */
@Composable
private fun PairCapsule(model: PracticeModel, enabled: Boolean, onClick: () -> Unit) {
    PillButton(onClick, enabled = enabled) {
        val tint = if (enabled) Theme.colors.ink else Theme.colors.inkTertiary
        val size = Theme.text.subheadline.fontSize.value.toInt()
        if (model.mixed) {
            SymbolIcon(R.drawable.ic_shuffle, tint, size)
            Text(stringResource(R.string.mixed), style = Theme.text.subheadline, color = tint)
        } else {
            Text(faceName(model.from), style = Theme.text.subheadline, color = tint)
            SymbolIcon(R.drawable.ic_arrow_forward, tint, size)
            Text(faceName(model.to), style = Theme.text.subheadline, color = tint)
        }
        SymbolIcon(R.drawable.ic_expand_more, tint, Theme.text.caption2.fontSize.value.toInt())
    }
}

/**
 * The quiz-pair sheet (design 5a): two rows (what the prompt shows, what the options answer) with the same
 * face greyed on the opposite row, a mixed option, and a live preview. **Every tap commits**: three switches,
 * each instantly reversible, with the whole result already on screen in the preview.
 */
@Composable
private fun PracticePairSheet(model: PracticeModel, lessonNumber: Int) {
    val sample = model.vocab.firstOrNull { it.displaysKanji } ?: model.vocab.firstOrNull()

    fun commit(from: VForm, to: VForm, mixed: Boolean = false) {
        val changed = model.questionFrom != from || model.questionTo != to || model.mixed != mixed
        model.setPair(from, to, mixed)
        // Logged only when something moved: re-tapping the selected chip is a no-op.
        if (changed) {
            Track.event(
                TrackEvents.PRACTICE_PAIR,
                mapOf("from" to from.label, "to" to to.label, "mixed" to mixed, "lesson" to lessonNumber)
            )
        }
    }

    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                stringResource(R.string.how_to_quiz_this_lesson),
                style = Theme.title(Theme.text.title3),
                color = Theme.colors.ink
            )
            Text(
                stringResource(R.string.pick_what_you_see_and_what_you_answer),
                style = Theme.text.subheadline,
                color = Theme.colors.inkSecondary
            )
        }
        FaceRow(stringResource(R.string.you_see), model.from, model.to, model.mixed) { commit(it, model.to) }
        FaceRow(stringResource(R.string.you_answer), model.to, model.from, model.mixed) { commit(model.from, it) }
        MixedCard(model.mixed) { commit(model.from, model.to, mixed = true) }
        if (sample != null) PairPreview(model, sample)
    }
}

/** One row of face chips. The face held by the *other* row is greyed, not swapped. */
@Composable
private fun FaceRow(title: String, selected: VForm, other: VForm, mixed: Boolean, pick: (VForm) -> Unit) {
    Column(
        Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            title,
            style = Theme.text.footnote.copy(fontWeight = FontWeight.SemiBold),
            color = Theme.colors.inkSecondary
        )
        Row(
            // Dimmed rather than hidden while mixed is on: the pair is still what the rows say, it just is not
            // what the next card will use.
            Modifier.fillMaxWidth().alpha(if (mixed) MIXED_DIM else 1f),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            for (f in PracticeModel.QUIZ_FACES) {
                val disabled = f == other
                SegmentChip(
                    faceName(f),
                    selected = !mixed && selected == f,
                    onClick = { if (!disabled) pick(f) },
                    modifier = Modifier.weight(1f).alpha(if (disabled) DISABLED_DIM else 1f)
                )
            }
        }
    }
}

@Composable
private fun MixedCard(mixed: Boolean, onClick: () -> Unit) {
    val shape = Theme.rounded(Theme.Radius.card)
    Row(
        Modifier
            .fillMaxWidth()
            .background(Theme.colors.surface, shape)
            .border(if (mixed) 2.dp else 1.dp, if (mixed) Theme.colors.accent else Theme.colors.line, shape)
            .clickable(role = Role.RadioButton, onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        SymbolIcon(R.drawable.ic_shuffle, Theme.colors.accent, Theme.text.title3.fontSize.value.toInt())
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(stringResource(R.string.mixed), style = Theme.title(Theme.text.headline), color = Theme.colors.ink)
            Text(
                stringResource(R.string.each_card_picks_a_combination_at_random),
                style = Theme.text.caption,
                color = Theme.colors.inkSecondary
            )
            Text(
                stringResource(R.string.words_without_kanji_skip_kanji_questions_automatically),
                style = Theme.text.caption2,
                color = Theme.colors.inkTertiary
            )
        }
    }
}

/** The chosen pair applied to a real word beside a real distractor: what the next quiz card will look like. */
@Composable
private fun PairPreview(model: PracticeModel, sample: Vocab) {
    // Deterministic, unlike the real deal: a re-rolled random distractor would flicker on every render.
    val distractor = model.vocab.firstOrNull {
        it.id != sample.id && model.from.value(it) != model.from.value(sample) &&
            model.to.value(it) != model.to.value(sample)
    }
    val shape = Theme.rounded(Theme.Radius.card)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            stringResource(
                if (model.mixed) R.string.one_example_each_card_varies else R.string.the_card_will_look_like_this
            ),
            style = Theme.text.footnote.copy(fontWeight = FontWeight.SemiBold),
            color = Theme.colors.inkSecondary
        )
        Column(
            Modifier
                .fillMaxWidth()
                .background(Theme.colors.surface, shape)
                .border(1.dp, Theme.colors.line, shape)
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                model.from.value(sample),
                style = promptStyle(model.from, 30, Theme.text.title3),
                color = Theme.colors.ink,
                textAlign = TextAlign.Center
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PreviewChip(model, model.to.value(sample), Modifier.weight(1f))
                if (distractor != null) PreviewChip(model, model.to.value(distractor), Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun PreviewChip(model: PracticeModel, text: String, modifier: Modifier) {
    val shape = Theme.rounded(Theme.Radius.inset)
    Box(
        modifier
            .heightIn(min = 40.dp)
            .border(1.dp, Theme.colors.line, shape)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text,
            style = if (model.to.isJapanese) Theme.jp(15.sp) else Theme.text.footnote,
            color = Theme.colors.ink,
            textAlign = TextAlign.Center,
            maxLines = 2
        )
    }
}
