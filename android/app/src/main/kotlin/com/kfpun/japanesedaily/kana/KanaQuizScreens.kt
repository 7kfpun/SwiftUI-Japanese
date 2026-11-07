package com.kfpun.japanesedaily.kana

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.data.vocab.K
import com.kfpun.japanesedaily.ui.JapaneseFace
import com.kfpun.japanesedaily.ui.KanaForm
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.AnswerBadge
import com.kfpun.japanesedaily.ui.components.AudioPromptGlyph
import com.kfpun.japanesedaily.ui.components.CanvasScreen
import com.kfpun.japanesedaily.ui.components.CardStackPeek
import com.kfpun.japanesedaily.ui.components.FitText
import com.kfpun.japanesedaily.ui.components.FlashcardScreen
import com.kfpun.japanesedaily.ui.components.ModeRow
import com.kfpun.japanesedaily.ui.components.OptionGrid
import com.kfpun.japanesedaily.ui.components.QuizOptionButton
import com.kfpun.japanesedaily.ui.components.QuizPromptPanel
import com.kfpun.japanesedaily.ui.components.ScoreBadge
import com.kfpun.japanesedaily.ui.components.ScreenBar
import com.kfpun.japanesedaily.ui.components.SoundToggle
import com.kfpun.japanesedaily.ui.components.StampSpec
import com.kfpun.japanesedaily.ui.components.SwipeCard
import com.kfpun.japanesedaily.ui.components.SwipeOptionChip
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.cardSwipe
import com.kfpun.japanesedaily.ui.components.rememberCardSwipeState
import com.kfpun.japanesedaily.ui.glyphStyle

/** The five ways to take the kana quiz, operating over whichever chart was showing in the browser. */
enum class KanaMode { Flashcards, Classic, Swipe, Listening, Write }

/** Lets the learner pick how to take the quiz (iOS `KanaQuizModeView`). */
@Composable
fun KanaModeList(onPick: (KanaMode) -> Unit, onBack: () -> Unit, modifier: Modifier = Modifier) {
    LaunchedEffect(Unit) { Track.screen(TrackScreens.KANA_QUIZ_MODE) }
    CanvasScreen(modifier) {
        Column(Modifier.fillMaxSize()) {
            ScreenBar(
                onBack = onBack,
                center = {
                    Text(
                        stringResource(R.string.choose_mode),
                        style = Theme.title(Theme.text.headline),
                        color = Theme.colors.ink
                    )
                }
            )
            Column(Modifier.verticalScroll(rememberScrollState())) {
                ModeRow(
                    R.drawable.ic_view_carousel,
                    stringResource(R.string.flashcards),
                    stringResource(R.string.swipe_right_if_you_know_it),
                    { onPick(KanaMode.Flashcards) }
                )
                ModeRow(
                    R.drawable.ic_touch_app,
                    stringResource(R.string.classic),
                    stringResource(R.string.tap_one_of_4_options),
                    { onPick(KanaMode.Classic) }
                )
                ModeRow(
                    R.drawable.ic_swap_horiz,
                    stringResource(R.string.swipe),
                    stringResource(R.string.swipe_left_right_between_2_options),
                    { onPick(KanaMode.Swipe) }
                )
                ModeRow(
                    R.drawable.ic_volume_up,
                    stringResource(R.string.listening),
                    stringResource(R.string.hear_it_pick_the_word),
                    { onPick(KanaMode.Listening) }
                )
                ModeRow(
                    R.drawable.ic_edit,
                    stringResource(R.string.write),
                    stringResource(R.string.hear_it_draw_it),
                    { onPick(KanaMode.Write) }
                )
            }
        }
    }
}

@Composable
private fun KanaForm.title(): String = stringResource(
    when (this) {
        KanaForm.Hiragana -> R.string.hiragana
        KanaForm.Katakana -> R.string.katakana
        KanaForm.Romaji -> R.string.romaji
    }
)

/** An outlined button for the from/to bar. */
@Composable
private fun FormButton(text: String, enabled: Boolean, onClick: () -> Unit) {
    val shape = Theme.rounded(Theme.Radius.chip)
    Box(
        Modifier
            .heightIn(min = 40.dp)
            .alpha(if (enabled) 1f else DISABLED_ALPHA)
            .border(1.dp, Theme.colors.accent, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center
    ) { Text(text, style = Theme.text.subheadline, color = Theme.colors.accent) }
}

private const val DISABLED_ALPHA = 0.4f

/** The from, to bar both kana quizzes wear. In Listening a speaker stands where the first button would be. */
@Composable
private fun KanaDirectionBar(model: KanaQuizModel, listening: Boolean = false) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val open = model.picked == null
        if (listening) {
            SymbolIcon(R.drawable.ic_volume_up, Theme.colors.accent, Theme.text.subheadline.fontSize.value.toInt())
        } else {
            FormButton(model.from.title(), open) { model.swapFrom() }
        }
        SymbolIcon(R.drawable.ic_arrow_forward, Theme.colors.ink, Theme.text.subheadline.fontSize.value.toInt())
        FormButton(model.to.title(), open) { model.swapTo() }
    }
}

/** A prominent action button (Next). An action, not a selection, so a filled accent is right. */
@Composable
private fun NextButton(enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .alpha(if (enabled) 1f else DISABLED_ALPHA)
            .background(Theme.colors.accent, Theme.rounded(Theme.Radius.row))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(
            stringResource(R.string.next),
            style = Theme.title(Theme.text.headline),
            color = Theme.colors.onAccent,
            textAlign = TextAlign.Center
        )
    }
}

/** Both faces follow their content's script: kana on the stroke-order face, romaji on the Latin one. */
private const val CLASSIC_PROMPT = 120
private const val SWIPE_PROMPT = 150
private const val OPTION_GLYPH = 26
private const val CHIP_GLYPH = 30
private const val SWIPE_THRESHOLD = 90f
private const val VERDICT_MILLIS = 500

/** Classic (4 options) and Listening (the prompt is audio, not a glyph). iOS `KanaQuizView`. */
@Composable
fun KanaQuizScreen(
    env: KanaEnv,
    table: KanaTable,
    listening: Boolean,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val model = remember(table) { KanaQuizModel(table.pool(env.data), record = env::record) }
    val sound = env.rememberSound()
    var playTick by remember { mutableIntStateOf(0) }

    // Kana audio can never reveal the answer: hiragana, katakana and romaji share one sound. In Listening the
    // sound IS the question, so the toggle cannot silence it.
    LaunchedEffect(playTick) {
        if (listening || sound.on) env.speaker.speak(model.answer)
    }
    LaunchedEffect(listening) {
        Track.screen(if (listening) TrackScreens.KANA_QUIZ_LISTENING else TrackScreens.KANA_QUIZ_CLASSIC)
    }

    CanvasScreen(modifier) {
        Column(Modifier.fillMaxSize()) {
            ScreenBar(
                onBack = onBack,
                center = { ScoreBadge(model.correct, model.total) },
                actions = { SoundToggle(sound.on, sound.toggle) }
            )
            Column(
                Modifier.weight(1f).fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                KanaDirectionBar(model, listening)
                QuizPromptPanel(onTap = { env.speaker.speak(model.answer) }, Modifier.weight(1f)) {
                    if (listening) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            AudioPromptGlyph()
                            Text(
                                stringResource(R.string.hear_it_pick_the_word),
                                style = Theme.text.subheadline,
                                color = Theme.colors.inkSecondary
                            )
                        }
                    } else {
                        FitText(
                            model.answer.value(model.from),
                            glyphStyle(
                                model.from.isJapanese,
                                CLASSIC_PROMPT,
                                JapaneseFace.Strokes,
                                FontWeight.SemiBold
                            ),
                            Modifier.padding(horizontal = 16.dp)
                        )
                    }
                }
                OptionGrid(count = model.options.size) { i ->
                    QuizOptionButton(
                        text = model.options[i].value(model.to),
                        index = i,
                        picked = model.picked,
                        isAnswer = model.isCorrectOption(i),
                        onClick = {
                            val right = model.choose(i)
                            // One event name per quiz: reading it and hearing it are different exercises.
                            if (right != null) {
                                val name = if (listening) {
                                    TrackEvents.KANA_LISTENING_ANSWER
                                } else {
                                    TrackEvents.KANA_CLASSIC_ANSWER
                                }
                                Track.event(name, mapOf("correct" to right))
                            }
                        },
                        textStyle = glyphStyle(
                            model.to.isJapanese,
                            OPTION_GLYPH,
                            JapaneseFace.Bold,
                            FontWeight.SemiBold
                        )
                    )
                }
                NextButton(enabled = model.picked != null) {
                    model.next()
                    playTick++
                }
            }
        }
    }
}

/** Tinder-style quiz: one prompt card and two candidate readings. Swipe it toward the one you choose. */
@Composable
fun KanaSwipeQuizScreen(env: KanaEnv, table: KanaTable, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val model = remember(table) { KanaQuizModel(table.pool(env.data), optionCount = 2, record = env::record) }
    val sound = env.rememberSound()
    val swipe = rememberCardSwipeState()
    var playTick by remember { mutableIntStateOf(0) }
    var lastCorrect by remember { mutableStateOf<Boolean?>(null) }

    LaunchedEffect(playTick) { if (sound.on) env.speaker.speak(model.answer) }
    LaunchedEffect(Unit) { Track.screen(TrackScreens.KANA_QUIZ_SWIPE) }

    fun decide(side: Int) {
        val right = model.choose(side) ?: return
        // Its own name: a swipe between two options is a different exercise from picking one of four.
        Track.event(TrackEvents.KANA_SWIPE_ANSWER, mapOf("correct" to right))
        lastCorrect = right
        // A longer wait than the exit itself, so the verdict badge reads first.
        swipe.fling(toRight = side == 1, delayMillis = VERDICT_MILLIS) {
            model.next()
            lastCorrect = null
            swipe.reset()
            playTick++ // explicit: every new card speaks (the answer may repeat, so no change to observe)
        }
    }

    CanvasScreen(modifier) {
        Column(Modifier.fillMaxSize()) {
            ScreenBar(
                onBack = onBack,
                center = { ScoreBadge(model.correct, model.total) },
                actions = { SoundToggle(sound.on, sound.toggle) }
            )
            Column(
                Modifier.weight(1f).fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                KanaDirectionBar(model)
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    CardStackPeek(modifier = Modifier.fillMaxSize())
                    SwipeCard(
                        Modifier
                            .fillMaxSize()
                            .cardSwipe(
                                swipe,
                                SWIPE_THRESHOLD,
                                canDrag = { model.picked == null },
                                canCommit = { model.picked == null }
                            ) { decide(if (it) 1 else 0) }
                            .clickable(role = Role.Button) { env.speaker.speak(model.answer) },
                        drag = { swipe.offset },
                        thresholdDp = SWIPE_THRESHOLD,
                        leftStamp = StampSpec(R.drawable.ic_arrow_back, Theme.colors.accent),
                        rightStamp = StampSpec(R.drawable.ic_arrow_forward, Theme.colors.accent),
                        showsStamps = model.picked == null
                    ) {
                        FitText(
                            model.answer.value(model.from),
                            glyphStyle(model.from.isJapanese, SWIPE_PROMPT, JapaneseFace.Strokes, FontWeight.SemiBold),
                            Modifier.padding(horizontal = 16.dp),
                            minScale = 0.3f
                        )
                    }
                }
                Row(
                    Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    for (side in 0..1) {
                        val opt = model.options.getOrNull(side)
                        // Kana readings are one to three characters, so they take a much larger face than vocab glosses.
                        Box(Modifier.weight(1f).fillMaxHeight()) {
                            SwipeOptionChip(
                                modifier = Modifier.fillMaxHeight(),
                                text = opt?.value(model.to).orEmpty(),
                                side = side,
                                picked = model.picked,
                                isAnswer = opt?.romaji == model.answer.romaji,
                                onClick = { decide(side) },
                                textStyle = glyphStyle(
                                    model.to.isJapanese,
                                    CHIP_GLYPH,
                                    JapaneseFace.Bold,
                                    FontWeight.SemiBold
                                )
                            )
                        }
                    }
                }
            }
        }
        lastCorrect?.let { Box(Modifier.fillMaxSize(), Alignment.Center) { AnswerBadge(it) } }
    }
}

private const val FLASH_GLYPH = 160
private const val FLASH_ROMAJI = 20

/** Kana flashcards on the shared [FlashcardScreen]: see the kana, decide if you know it; reveal shows romaji. */
@Composable
fun KanaFlashcardScreen(env: KanaEnv, table: KanaTable, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val deck = remember(table) { FlashDeck(table.pool(env.data)) }
    val sound = env.rememberSound()
    LaunchedEffect(Unit) { Track.screen(TrackScreens.KANA_FLASHCARD) }
    CanvasScreen(modifier) {
        FlashcardScreen(
            deck = deck,
            id = K::id,
            speak = { env.speaker.speak(it) },
            soundOn = sound.on,
            onToggleSound = sound.toggle,
            onBack = onBack,
            summary = { stringResource(R.string.you_reviewed_arg_kana, it.toString()) },
            trackName = "kana_flashcard"
        ) { kana, revealed -> KanaFace(kana, revealed) }
    }
}

/** The kana card face: hiragana, revealing romaji and katakana. */
@Composable
private fun KanaFace(kana: K, revealed: Boolean) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // Combos (びゃ) shrink to fit instead of truncating.
        FitText(kana.hiragana, glyphStyle(true, FLASH_GLYPH, JapaneseFace.Strokes))
        if (revealed) {
            HorizontalDivider(Modifier.padding(horizontal = 40.dp), color = Theme.colors.line)
            Text(
                kana.romaji,
                style = Theme.title(Theme.text.title),
                color = Theme.colors.accent
            )
            Text(
                kana.katakana,
                style = glyphStyle(true, FLASH_ROMAJI, JapaneseFace.Bold),
                color = Theme.colors.inkSecondary
            )
        }
    }
}
