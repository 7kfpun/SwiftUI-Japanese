package com.kfpun.japanesedaily.catalog

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.kfpun.japanesedaily.data.progress.Streak
import com.kfpun.japanesedaily.data.progress.StudyDay
import com.kfpun.japanesedaily.progress.ProgressContent
import com.kfpun.japanesedaily.progress.ProgressStats
import com.kfpun.japanesedaily.ui.JapaneseDailyTheme

/**
 * Debug-only: the real [ProgressContent] over made-up numbers, for screenshots (`--ez empty true` for the
 * empty state). It writes nothing: no database row is created, so no progress is ever fabricated, and it is
 * not compiled into release builds. A developer-only surface, deliberately unlocalised in its own code.
 */
class ProgressDemoActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val empty = intent.getBooleanExtra("empty", false)
        val today = StudyDay.stamp()
        val stats = if (empty) {
            ProgressStats.from(emptyList(), emptyList(), emptyList(), emptyList(), today, TOTAL_CHALLENGES, TOTAL_KANA)
        } else {
            // A five-day run ending yesterday (today still open), and scattered older days.
            val run = (1..5).map { StudyDay.offset(today, -it) }
            val older = listOf(9, 10, 12, 15, 16, 17, 21, 24, 30, 31, 40, 41, 42, 43, 44, 52).map {
                StudyDay.offset(today, -it)
            }
            val days = (run + older).toSet()
            ProgressStats(Streak(days, today), days.size, 14, TOTAL_CHALLENGES, 23, TOTAL_KANA, 7)
        }
        setContent { JapaneseDailyTheme { ProgressContent(stats, onBookmarks = {}) } }
    }

    private companion object {
        const val TOTAL_CHALLENGES = 417
        const val TOTAL_KANA = 104
    }
}
