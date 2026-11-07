package com.kfpun.japanesedaily.intro

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.survey.AppInfo
import com.kfpun.japanesedaily.survey.Survey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The replay entry point: Settings (FOX-159) calls [replay] from its version-footer long-press, as
 * iOS does. The tour then shows over whatever is on screen and finishes back to it.
 */
object IntroLauncher {
    private var requested by mutableStateOf(false)

    val replaying: Boolean get() = requested

    fun replay() {
        requested = true
    }

    internal fun done() {
        requested = false
    }
}

/**
 * Gates [content] behind the first-launch intro. The tour is shown until `introAnswered` is set (also
 * set by Skip, or it would nag on every launch), then [content] gets the tab to land on.
 */
@Composable
fun IntroHost(content: @Composable (Intro.Tab) -> Unit) {
    val context = LocalContext.current
    val prefs = remember { IntroPrefs(context) }
    var landing by rememberSaveable { mutableStateOf<Intro.Tab?>(if (prefs.introAnswered) Intro.Tab.TODAY else null) }
    val showing by remember { derivedStateOf { landing == null || IntroLauncher.replaying } }

    landing?.let { content(it) }
    if (!showing) return

    // Meaning language: the stored choice, else the device's when the data has it. Card 1 writes it
    // as it changes; the app language is never touched here (it would rebuild the UI mid-tour).
    var language by rememberSaveable { mutableStateOf<String?>(prefs.translationLanguage) }
    val samples by produceState<IntroSamples?>(null, language) {
        val chosen = language
        value = withContext(Dispatchers.IO) {
            val resolved = chosen ?: IntroSamples.defaultLanguage(IntroSamples.load(context, "en").languages)
            IntroSamples.load(context, resolved)
        }
    }
    LaunchedEffect(Unit) { Track.screen(TrackScreens.INTRO) }

    val ready = samples ?: return
    IntroScreen(
        samples = ready,
        language = language ?: IntroSamples.defaultLanguage(ready.languages),
        onLanguage = {
            language = it
            prefs.translationLanguage = it
        },
        onReminders = { /* the streak reminder and its permission arrive with FOX-159 */ },
        onFinish = { answers, tab, completed ->
            answers.save(prefs)
            // Only a fully answered run is submitted. Fire and forget, off the main thread.
            if (completed) {
                answers.submission?.let { Survey.submit(it, AppInfo.surveyContext(context, Track.lastScreen)) }
            }
            if (landing == null) landing = tab
            IntroLauncher.done()
        }
    )
}
