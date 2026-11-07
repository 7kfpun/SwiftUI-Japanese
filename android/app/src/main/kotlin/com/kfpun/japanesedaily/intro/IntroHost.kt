package com.kfpun.japanesedaily.intro

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.settings.rememberReminderOptIn
import com.kfpun.japanesedaily.survey.AppInfo
import com.kfpun.japanesedaily.survey.Survey
import com.kfpun.japanesedaily.ui.ReadableWidth
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
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
    val container = remember { AppContainer.from(context) }
    val prefs = container.prefs
    val scope = rememberCoroutineScope()
    // The intro's reminders "yes": the same opt-in as Settings (system permission on 13+, then plan it).
    val optInReminders = rememberReminderOptIn()

    // null while the flag is being read: nothing is drawn for a few milliseconds rather than a
    // flash of the tabs that the tour then covers.
    val answered by produceState<Boolean?>(null) { value = prefs.get(Pref.introAnswered) }
    var landing by rememberSaveable { mutableStateOf<Intro.Tab?>(null) }
    val current = landing ?: if (answered == true) Intro.Tab.TODAY else null
    val showing by remember { derivedStateOf { (answered == false && landing == null) || IntroLauncher.replaying } }

    current?.let { content(it) }
    if (!showing) return

    // Meaning language: the stored choice, else the device's. Card 1 writes it as it changes; the app
    // language is never touched here (it would rebuild the UI under the tour).
    val language by produceState<String?>(null) {
        value = withContext(Dispatchers.IO) {
            prefs.translationLanguage(container.vocab.deviceDefaultLanguage()).first()
        }
    }
    var chosen by rememberSaveable { mutableStateOf<String?>(null) }
    val shown = chosen ?: language ?: return
    val samples by produceState<IntroSamples?>(null, shown) {
        value = withContext(Dispatchers.IO) { IntroSamples.from(container.vocab, shown) }
    }
    LaunchedEffect(Unit) { Track.screen(TrackScreens.INTRO) }

    val ready = samples ?: return
    // The cards are capped at the readable width on a large screen (FOX-166); the background stays full-bleed.
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        ReadableWidth {
            IntroScreen(
                samples = ready,
                language = shown,
                onLanguage = {
                    chosen = it
                    scope.launch { prefs.setTranslationLanguage(it) }
                },
                onReminders = { wants ->
                    scope.launch { prefs.set(Pref.notificationAskedAt, System.currentTimeMillis()) }
                    // Only a yes ever reaches the system permission; "Not now" must never be followed by it.
                    if (wants) optInReminders()
                },
                onFinish = { answers, tab, completed ->
                    if (landing == null) landing = tab
                    IntroLauncher.done()
                    // Written and sent from the application scope, so it outlives this composition. Only a
                    // fully answered run is submitted: fire and forget, never blocking the tap.
                    container.scope.launch(Dispatchers.IO) {
                        answers.save(prefs)
                        val row = answers.submission?.takeIf { completed } ?: return@launch
                        val survey = AppInfo.surveyContext(
                            context.applicationContext,
                            prefs,
                            container.vocab.deviceDefaultLanguage()
                        )
                        Survey.submit(row, survey)
                    }
                }
            )
        }
    }
}
