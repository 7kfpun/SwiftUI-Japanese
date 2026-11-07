package com.kfpun.japanesedaily.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import com.kfpun.japanesedaily.kana.KanaSpeaker
import com.kfpun.japanesedaily.data.prefs.Prefs
import com.kfpun.japanesedaily.data.progress.PracticeProgress
import com.kfpun.japanesedaily.data.progress.ProgressDatabase
import com.kfpun.japanesedaily.data.progress.ProgressRepository
import com.kfpun.japanesedaily.data.progress.Streak
import com.kfpun.japanesedaily.data.vocab.AndroidAssetSource
import com.kfpun.japanesedaily.data.vocab.AssetSource
import com.kfpun.japanesedaily.data.vocab.KanaData
import com.kfpun.japanesedaily.data.vocab.VocabStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * The one entry point other features inject from: bundled content ([vocab], [kana]), progress
 * ([progress], [practice]) and preferences ([prefs]). Get it with [from]; tests build one directly
 * with an in-memory database and a file-backed [AssetSource].
 *
 * Everything lives on the device: the database and the preferences file are excluded from every
 * backup (`data_extraction_rules.xml`) and `allowBackup` is false.
 */
class AppContainer(
    assets: AssetSource,
    database: ProgressDatabase,
    preferences: DataStore<Preferences>,
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    val course: Course = Course.current,
    onFirstAnswerToday: (Streak) -> Unit = {}
) {
    val vocab = VocabStore(assets, course)
    val kana = KanaData(assets)
    val progress = ProgressRepository(database, vocab, course, onFirstAnswerToday = onFirstAnswerToday)
    val practice = PracticeProgress(database.practice(), scope)
    val prefs = Prefs(preferences)

    /** The voice the Kana tab speaks through. Silent until the audio player (FOX-151) is wired in. */
    @Volatile
    var kanaSpeaker: KanaSpeaker = KanaSpeaker.Silent

    /** Decodes the course data and loads Practice stages off the main thread, at launch. */
    fun preload() {
        scope.launch {
            vocab.preload()
            practice.load()
        }
    }

    companion object {
        @Volatile
        private var instance: AppContainer? = null

        fun from(context: Context): AppContainer = instance ?: synchronized(this) {
            instance ?: create(context.applicationContext).also { instance = it }
        }

        private fun create(context: Context): AppContainer = AppContainer(
            assets = AndroidAssetSource(context.assets),
            database = ProgressDatabase.open(context),
            preferences = PreferenceDataStoreFactory.create {
                context.filesDir.resolve("datastore/prefs.preferences_pb")
            }
        )
    }
}
