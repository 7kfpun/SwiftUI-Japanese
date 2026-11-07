package com.kfpun.japanesedaily

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.kfpun.japanesedaily.ui.AppScaffold
import com.kfpun.japanesedaily.ui.JapaneseDailyTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            JapaneseDailyTheme {
                AppScaffold()
            }
        }
    }
}
