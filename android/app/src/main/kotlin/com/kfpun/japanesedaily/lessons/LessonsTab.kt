package com.kfpun.japanesedaily.lessons

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.movableContentOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.ladder.ChallengeScreen
import com.kfpun.japanesedaily.ui.Adaptive
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.isRegularWidth
import kotlinx.coroutines.flow.first

/** True inside the right pane of the two-pane Lessons tab (regular width): its root screen has no Back. */
val LocalTwoPane = compositionLocalOf { false }

/**
 * The Lessons tab: the list, and the screens pushed from it, as a hoisted [LessonsNav] stack. At regular width
 * (600 dp and up) it is two panes instead: the list on the left (a third of the window) and the stack on the right,
 * so a lesson and the modes it opens never cover the list. Both layouts read the one stack, so moving between
 * widths keeps the selected lesson and the screen open in it.
 */
@Composable
fun LessonsTab(nav: LessonsNav, modifier: Modifier = Modifier) {
    val env = rememberLessonsEnv()
    // The canvas first, so a cold start never blocks on the course data (it decodes off the main thread).
    if (env == null) {
        Box(modifier.fillMaxSize().background(Theme.colors.canvas))
        return
    }
    val twoPane = isRegularWidth()
    // In two panes the root of the right pane is a lesson's mode picker, which has no screen behind it to pop to.
    BackHandler(enabled = nav.stack.size > if (twoPane) 1 else 0) { nav.pop() }
    // FOX-154: every tap on an open rung pushes the run.
    CompositionLocalProvider(
        LocalOpenChallenge provides OpenChallenge { lesson, index -> nav.push(LessonRoute.Challenge(lesson, index)) },
        LocalTwoPane provides twoPane
    ) {
        // One movable instance of the routes: crossing 600 dp (fold, unfold, split-screen) moves it between the full-width
        // slot and the right pane without disposing it, so a Practice queue, a Match board or a Challenge rung survives.
        val routes = remember(env, nav) { movableContentOf { LessonsRoutes(env, nav, Modifier) } }
        if (twoPane) {
            TwoPaneLessons(env, nav, modifier, routes)
        } else {
            Box(modifier.fillMaxSize()) { routes() }
        }
    }
}

@Composable
private fun TwoPaneLessons(env: LessonsEnv, nav: LessonsNav, modifier: Modifier, routes: @Composable () -> Unit) {
    // Never an empty right pane: with nothing open, select the "up next" lesson (once, then it is part of the stack).
    LaunchedEffect(nav.stack.isEmpty()) {
        if (nav.stack.isEmpty()) {
            val passed = LessonStanding.passedByLesson(env.container.progress.observeChallenges().first().values)
            nav.openLesson(LessonStanding.continueLesson(passed, env::wordCount) ?: 1)
        }
    }
    val selected = nav.stack.firstOrNull()?.lessonOrNull()
    BoxWithConstraints(modifier.fillMaxSize().background(Theme.colors.canvas)) {
        val listWidth = Adaptive.listPaneWidthDp(this.maxWidth.value).dp
        Row(Modifier.fillMaxSize()) {
            Box(Modifier.width(listWidth).fillMaxHeight()) {
                LessonListScreen(env, nav, selected = selected, onOpen = { nav.openLesson(it) })
            }
            Box(Modifier.width(1.dp).fillMaxHeight().background(Theme.colors.line))
            Box(Modifier.weight(1f).fillMaxHeight()) {
                if (nav.stack.isNotEmpty()) routes()
            }
        }
    }
}

private fun LessonRoute.lessonOrNull(): Int? = when (this) {
    is LessonRoute.Select -> lesson
    is LessonRoute.Practice -> lesson
    is LessonRoute.VocabList -> lesson
    is LessonRoute.ReadAlong -> lesson
    is LessonRoute.Flashcards -> lesson
    is LessonRoute.Match -> lesson
    is LessonRoute.Learn -> lesson
    is LessonRoute.Challenge -> lesson
    LessonRoute.Bookmarks -> null
}

@Composable
private fun LessonsRoutes(env: LessonsEnv, nav: LessonsNav, modifier: Modifier) {
    when (val route = nav.current) {
        is LessonRoute.Challenge -> ChallengeScreen(route.lesson, route.index, env, nav, modifier)
        null -> LessonListScreen(env, nav, modifier)
        is LessonRoute.Select -> SelectModeScreen(route.lesson, env, nav, modifier)
        is LessonRoute.Practice -> PracticeScreen(route.lesson, env, nav, modifier)
        is LessonRoute.VocabList -> VocabListScreen(route.lesson, env, nav, modifier)
        is LessonRoute.ReadAlong -> ReadAlongScreen(route.lesson, route.cut, env, nav, modifier)
        is LessonRoute.Flashcards -> FlashcardScreen(route.lesson, env, nav, modifier)
        is LessonRoute.Match -> MatchScreen(route.lesson, env, nav, modifier)
        is LessonRoute.Learn -> LearnScreen(route.lesson, env, nav, modifier)
        LessonRoute.Bookmarks -> BookmarksScreen(env, nav, modifier)
    }
}
