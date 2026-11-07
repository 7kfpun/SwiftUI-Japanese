package com.kfpun.japanesedaily.lessons

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.kfpun.japanesedaily.R
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
    when (val route = nav.current) {
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

/** What the placeholder paywall was opened for. */
private class PaywallRequest(val source: String, val lesson: Int?)

/**
 * Hosts [LocalOpenPaywall] with a **placeholder** dialog until the Pro ticket (FOX-158) lands: it shows the
 * PRO label and a way out, so every gate is reachable and testable. FOX-158 replaces the dialog body with the
 * real paywall and keeps this seam.
 */
@Composable
fun PaywallHost(content: @Composable () -> Unit) {
    var request by remember { mutableStateOf<PaywallRequest?>(null) }
    CompositionLocalProvider(
        LocalOpenPaywall provides OpenPaywall { source, lesson ->
            request = PaywallRequest(source, lesson)
        }
    ) {
        content()
    }
    request?.let {
        AlertDialog(
            onDismissRequest = { request = null },
            title = { Text(stringResource(R.string.pro)) },
            text = { Text(it.source) },
            confirmButton = { TextButton(onClick = { request = null }) { Text(stringResource(R.string.cancel)) } },
            containerColor = Theme.colors.surface
        )
    }
}
