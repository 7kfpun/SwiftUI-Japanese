package com.kfpun.japanesedaily

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.lifecycleScope
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.audio.ProvidePronouncer
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.intro.Intro
import com.kfpun.japanesedaily.intro.IntroHost
import com.kfpun.japanesedaily.today.TodayWidgetUpdater
import com.kfpun.japanesedaily.ui.AppScaffold
import com.kfpun.japanesedaily.ui.JapaneseDailyTheme
import com.kfpun.japanesedaily.ui.Tab
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {
    /** A tab a deep link asked for (the widget), consumed by `AppScaffold`. */
    private val tabRequest = mutableStateOf<Tab?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handleDeepLink(intent)
        enableEdgeToEdge()
        // Decode the course data and load Practice stages off the main thread.
        val container = AppContainer.from(this)
        container.preload()
        // Redraw the widget if the language changed while the app wasn't running, and keep its hourly redraw armed.
        lifecycleScope.launch(Dispatchers.Default) { TodayWidgetUpdater.onAppStart(applicationContext) }
        setContent {
            JapaneseDailyTheme {
                ProvidePronouncer(container.vocab) {
                    IntroHost { landing ->
                        AppScaffold(
                            startTab = if (landing == Intro.Tab.KANA) Tab.Kana else Tab.Today,
                            tabRequest = tabRequest.value,
                            onTabRequestHandled = { tabRequest.value = null }
                        )
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    /** The widget's tap: opens Today, and counts as a `widget_open` (a launch is otherwise just a cold start). */
    private fun handleDeepLink(intent: Intent?) {
        if (intent?.action != ACTION_OPEN_TODAY) return
        Track.event(TrackEvents.WIDGET_OPEN, mapOf("lesson" to intent.getIntExtra(EXTRA_WIDGET_LESSON, 0)))
        tabRequest.value = Tab.Today
    }

    companion object {
        const val ACTION_OPEN_TODAY = "com.kfpun.japanesedaily.action.OPEN_TODAY"
        const val EXTRA_WIDGET_LESSON = "widget_lesson"
    }
}
