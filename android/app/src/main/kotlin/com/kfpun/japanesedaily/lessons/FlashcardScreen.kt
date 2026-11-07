package com.kfpun.japanesedaily.lessons

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.audio.LocalPronouncer
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.ui.Adaptive
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.CardStackPeek
import com.kfpun.japanesedaily.ui.components.SwipeCard
import com.kfpun.japanesedaily.ui.components.cardPager
import com.kfpun.japanesedaily.ui.components.rememberCardPagerState

/**
 * Flashcards (port of `FlashcardView`): a lesson's words as a deck to page through, and nothing else.
 *
 * **It writes nothing.** No Practice stage, no `ChallengeResult`, no streak day: browsing a lesson is not
 * evidence of anything, and the graded deck this replaced measured confidence, not recall. Swipe to turn
 * (`cardPager`, on the card, never the enclosing box); ordered or random; two flips that coexist: hold to
 * peek (release turns back) and double-tap to flip *and stay* for reading.
 */
@Composable
fun FlashcardScreen(lessonNumber: Int, env: LessonsEnv, nav: LessonsNav, modifier: Modifier = Modifier) {
    val container = env.container
    val pronouncer = LocalPronouncer.current
    val isPremium = LocalPremium.current.isPremium
    val scope = rememberCoroutineScope()
    val entries = remember(lessonNumber, env.language) { env.lesson(lessonNumber).entries }
    val ordered = rememberPref(Pref.flashcardsOrdered, container)
    val soundOn = rememberPref(Pref.soundOn, container).value
    var index by rememberSaveable { mutableIntStateOf(0) }
    var flipped by remember { mutableStateOf(false) }

    // The flip came from a hold, so releasing turns it back; a double-tap flip is sticky.
    var holdPeek by remember { mutableStateOf(false) }

    // `flashcard_flip` counts cards peeked, not presses, so it stays comparable with `practice_peek`.
    var flippedThisCard by remember { mutableStateOf(false) }

    // Distinct cards reached: `flashcard_swipe` reports depth, and only a *new* card logs.
    val cardsSeen = remember { mutableSetOf(0) }
    val detailPlayer = remember(pronouncer) { LessonPlayer(pronouncer, scope) }
    val angle = rememberFlip(flipped)
    val word: Vocab? = entries.getOrNull(index)

    /** Reads the flipped entry aloud. The spoken meaning is Read along's paid feature: free users get the word. */
    fun readDetails(w: Vocab) {
        if (!soundOn) return
        pronouncer.stop()
        detailPlayer.stop()
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
                Track.event(TrackEvents.FLASHCARD_FLIP, mapOf("lesson" to lessonNumber))
            }
            readDetails(w)
        } else {
            detailPlayer.stop()
        }
    }

    fun autoPlay() {
        val w = entries.getOrNull(index) ?: return
        if (soundOn) pronouncer.speak(w)
    }

    /**
     * Ordered walks the lesson and wraps; random jumps. Speaks explicitly rather than reacting to the index,
     * because a random jump can land on the card already showing and would silently skip the word.
     */
    fun turnPage(dir: Int) {
        if (entries.isEmpty()) return
        detailPlayer.stop()
        flipped = false
        holdPeek = false
        flippedThisCard = false
        if (ordered.value) {
            index = (index + (if (dir > 0) 1 else -1) + entries.size) % entries.size
        } else if (entries.size > 1) {
            var next = index
            while (next == index) next = entries.indices.random()
            index = next
        }
        if (cardsSeen.add(index)) {
            Track.event(TrackEvents.FLASHCARD_SWIPE, mapOf("lesson" to lessonNumber, "depth" to cardsSeen.size))
        }
        autoPlay()
    }

    val pager = rememberCardPagerState(canPage = { entries.size > 1 }, page = ::turnPage)

    LaunchedEffect(lessonNumber) {
        Track.screen(TrackScreens.FLASHCARDS, mapOf("lesson" to lessonNumber))
        container.prefs.markModeVisit(lessonNumber, LessonMode.FLASHCARDS)
        autoPlay()
    }
    DisposableEffect(detailPlayer) { onDispose { detailPlayer.release() } }

    LessonScreenFrame(
        "${index + 1} / ${entries.size}",
        onBack = { nav.pop() },
        modifier = modifier,
        scrollIfShort = true,
        actions = { CardShowMenu(container, sound = true) }
    ) {
        Column(
            Modifier.fillMaxSize().padding(16.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            OrderPicker(ordered.value, ordered.set, TrackEvents.FLASHCARD_ORDER_MODE)
            if (word != null) {
                Box(
                    Modifier.weight(1f, fill = false).fillMaxWidth()
                        .heightIn(max = Adaptive.CARD_MAX_HEIGHT_DP.dp).padding(vertical = 12.dp)
                ) {
                    CardStackPeek(minOf(2, maxOf(0, entries.size - 1)), Modifier.fillMaxSize())
                    // On the card, **not** on this Box: `cardPager` offsets and rotates whatever it modifies, so
                    // outside the card it flings the peek layers too and the deck leaves as one slab.
                    SwipeCard(
                        Modifier
                            .fillMaxSize()
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
                        hint = if (entries.size > 1 && !flipped) stringResource(R.string.swipe) else null
                    ) {
                        Box(Modifier.padding(24.dp)) {
                            FlipFaces(
                                angle,
                                front = { VocabFront(word, container, Modifier.fillMaxWidth()) },
                                back = {
                                    VocabFace(word, onSpeakExample = {
                                        pronouncer.speakExample(word)
                                        Track.event(
                                            TrackEvents.PLAY_EXAMPLE,
                                            mapOf("lesson" to lessonNumber, "surface" to "flashcards")
                                        )
                                    })
                                }
                            )
                        }
                    }
                }
                Text(
                    stringResource(R.string.double_tap_for_details),
                    style = Theme.text.caption2,
                    color = Theme.colors.inkTertiary
                )
            }
        }
    }
}
