package com.kfpun.japanesedaily.kana

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.audio.Pronouncer
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.prefs.PrefKey
import kotlinx.coroutines.launch

/** Everything the Kana screens read: the container, the voice ([Pronouncer], FOX-151) and the template rasteriser. */
class KanaEnv(val container: AppContainer, val speaker: Pronouncer, val glyphs: GlyphRasterizer) {
    val data get() = container.kana
}

/** A preference as Compose state, seeded with its default until the store answers. */
@Composable
fun <T : Any> KanaEnv.prefState(pref: PrefKey<T>): State<T> = container.prefs.flow(pref).collectAsState(pref.default)

/** The global sound switch, shared by every kana screen. */
class SoundState(val on: Boolean, val toggle: () -> Unit)

@Composable
fun KanaEnv.rememberSound(): SoundState {
    val on by prefState(Pref.soundOn)
    val scope = rememberCoroutineScope()
    return SoundState(on) {
        scope.launch { container.prefs.set(Pref.soundOn, !on) }
        Track.event(TrackEvents.TOGGLE_SOUND, mapOf("on" to !on))
    }
}

/** Records a kana answer through the repository (duplicate-tolerant, latest wins) on the app scope. */
fun KanaEnv.record(romaji: String, correct: Boolean) {
    container.scope.launch { container.progress.recordKana(romaji, correct) }
}
