package com.kfpun.japanesedaily

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import com.kfpun.japanesedaily.audio.ProvidePronouncer
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.intro.Intro
import com.kfpun.japanesedaily.intro.IntroHost
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
        setContent {
            JapaneseDailyTheme {
                ProvidePronouncer(container.vocab) {
                    IntroHost { landing ->
                        AppScaffold(if (landing == Intro.Tab.KANA) Tab.Kana else Tab.Today)
                    }
                }
            }
        }
    }
}
