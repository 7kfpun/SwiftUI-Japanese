package com.kfpun.japanesedaily.lessons

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import com.kfpun.japanesedaily.ladder.ChallengeScreen
import com.kfpun.japanesedaily.ui.Theme

/** The Lessons tab: the list, and the screens pushed from it, as a hoisted [LessonsNav] stack. */
@Composable
fun LessonsTab(nav: LessonsNav, modifier: Modifier = Modifier) {
    val env = rememberLessonsEnv()
    // The canvas first, so a cold start never blocks on the course data (it decodes off the main thread).
    if (env == null) {
        Box(modifier.fillMaxSize().background(Theme.colors.canvas))
        return
    }
    BackHandler(enabled = nav.stack.isNotEmpty()) { nav.pop() }
    // FOX-154: every tap on an open rung pushes the run.
    CompositionLocalProvider(
        LocalOpenChallenge provides OpenChallenge { lesson, index -> nav.push(LessonRoute.Challenge(lesson, index)) }
    ) {
        LessonsRoutes(env, nav, modifier)
    }
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
