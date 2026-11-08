package com.kfpun.japanesedaily.audio

import android.widget.Toast
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.data.vocab.VocabStore
import com.kfpun.japanesedaily.locale.AppLocale

/**
 * Provides the real [Pronouncer] to the tree. It stops when the app leaves the foreground and is
 * released with the host. The no-Japanese-voice hint is a toast, shown once per process.
 */
@Composable
fun ProvidePronouncer(vocab: VocabStore, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val pronouncer = remember(vocab) {
        AudioPronouncer.create(context, vocab) {
            val text = AppLocale.localizedContext(context)
                .getString(R.string.no_japanese_voice_is_installed_on_this_device_add_on_3cd64e5)
            Toast.makeText(context.applicationContext, text, Toast.LENGTH_LONG).show()
        }
    }
    DisposableEffect(pronouncer, owner) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) pronouncer.stop() }
        owner.lifecycle.addObserver(observer)
        onDispose {
            owner.lifecycle.removeObserver(observer)
            pronouncer.release()
        }
    }
    CompositionLocalProvider(LocalPronouncer provides pronouncer, content = content)
}

/** Call from a screen that plays sound: whatever is playing stops when the screen leaves the composition. */
@Composable
fun StopSoundOnExit() {
    val pronouncer = LocalPronouncer.current
    DisposableEffect(pronouncer) { onDispose { pronouncer.stop() } }
}
