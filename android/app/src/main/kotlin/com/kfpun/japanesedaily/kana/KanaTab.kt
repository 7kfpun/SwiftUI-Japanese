package com.kfpun.japanesedaily.kana

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.kfpun.japanesedaily.audio.LocalPronouncer
import com.kfpun.japanesedaily.audio.StopSoundOnExit
import com.kfpun.japanesedaily.data.AppContainer

/** Where the Kana tab is: the browser, the mode list for a chart, or one of the five modes. */
private enum class Route { Browser, Modes, Flashcards, Classic, Swipe, Listening, Write }

private fun KanaMode.route() = when (this) {
    KanaMode.Flashcards -> Route.Flashcards
    KanaMode.Classic -> Route.Classic
    KanaMode.Swipe -> Route.Swipe
    KanaMode.Listening -> Route.Listening
    KanaMode.Write -> Route.Write
}

/**
 * The Kana tab (iOS `KanaBrowserView` and the quiz screens it pushes). A tiny state-based stack rather than a
 * navigation library: browser, then the mode list, then a mode. Back pops one level. The chart the quiz runs
 * over is the one the browser was showing when Quiz was tapped. All of it is free: nothing here is gated.
 */
@Composable
fun KanaTab(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val pronouncer = LocalPronouncer.current
    val env = remember(pronouncer) {
        KanaEnv(AppContainer.from(context), pronouncer, AndroidGlyphRasterizer(context.applicationContext))
    }
    var route by rememberSaveable { mutableStateOf(Route.Browser) }
    var table by rememberSaveable { mutableStateOf(KanaTable.Seion) }

    BackHandler(enabled = route != Route.Browser) {
        route = if (route == Route.Modes) Route.Browser else Route.Modes
    }
    // Whatever is playing stops when a screen leaves.
    StopSoundOnExit()

    val back = { route = Route.Modes }
    when (route) {
        Route.Browser -> KanaBrowser(env, onQuiz = {
            table = it
            route = Route.Modes
        }, modifier)

        Route.Modes -> KanaModeList(onPick = { route = it.route() }, onBack = { route = Route.Browser }, modifier)

        Route.Flashcards -> KanaFlashcardScreen(env, table, back, modifier)

        Route.Classic -> KanaQuizScreen(env, table, listening = false, onBack = back, modifier = modifier)

        Route.Listening -> KanaQuizScreen(env, table, listening = true, onBack = back, modifier = modifier)

        Route.Swipe -> KanaSwipeQuizScreen(env, table, back, modifier)

        Route.Write -> KanaWriteScreen(env, table, back, modifier)
    }
}
