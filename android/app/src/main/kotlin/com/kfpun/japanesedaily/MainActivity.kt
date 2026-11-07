package com.kfpun.japanesedaily

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.audio.ProvidePronouncer
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.intro.Intro
import com.kfpun.japanesedaily.intro.IntroHost
import com.kfpun.japanesedaily.rating.RatingHost
import com.kfpun.japanesedaily.settings.ProvideTextScale
import com.kfpun.japanesedaily.settings.Reminders
import com.kfpun.japanesedaily.settings.SystemReminderNotifier
import com.kfpun.japanesedaily.ui.AppScaffold
import com.kfpun.japanesedaily.ui.JapaneseDailyTheme
import com.kfpun.japanesedaily.ui.Tab

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Decode the course data and load Practice stages off the main thread.
        val container = AppContainer.from(this)
        container.preload()
        // A launch re-plans the streak reminder (and restarts its week): the learner is evidently still here.
        Reminders.reschedule(this)
        if (intent?.getBooleanExtra(SystemReminderNotifier.EXTRA_FROM_REMINDER, false) == true) {
            Track.event(TrackEvents.NOTIFICATION_OPENED, mapOf("source" to "streak_reminder"))
        }
        setContent {
            ProvideTextScale {
                JapaneseDailyTheme {
                    ProvidePronouncer(container.vocab) {
                        IntroHost { landing ->
                            AppScaffold(if (landing == Intro.Tab.KANA) Tab.Kana else Tab.Today)
                        }
                    }
                    // The star row, over the whole app: the ladder raises it after a passed rung.
                    RatingHost()
                }
            }
        }
    }
}
