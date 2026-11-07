package com.kfpun.japanesedaily.audio

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/**
 * The live synthesiser behind [TtsEngine]. Created on first use and shut down after
 * [IDLE_RELEASE_MS] of silence (or on [release]), because an idle `TextToSpeech` keeps a service
 * connection open. All calls come from the main thread.
 */
class AndroidTtsEngine(context: Context) : TtsEngine {
    private class Pending(val request: TtsRequest, val onUnavailable: () -> Unit, val onDone: () -> Unit)

    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ready = false
    private var pending: Pending? = null
    private var current: Pending? = null
    private val releaseLater = Runnable { release() }

    override fun speak(request: TtsRequest, onUnavailable: () -> Unit, onDone: () -> Unit) {
        main.removeCallbacks(releaseLater)
        pending = Pending(request, onUnavailable, onDone)
        val engine = tts
        if (engine == null) {
            start()
        } else if (ready) {
            flush(engine)
        }
    }

    private fun start() {
        // The listener can run before the constructor returns, so it reads the field it assigns.
        tts = TextToSpeech(appContext) { status -> main.post { onInit(status) } }.also {
            it.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit

                override fun onDone(utteranceId: String?) {
                    main.post { finished() }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    main.post { finished() }
                }
            })
        }
    }

    private fun onInit(status: Int) {
        val engine = tts ?: return
        if (status != TextToSpeech.SUCCESS) {
            val failed = pending
            pending = null
            release()
            failed?.onUnavailable?.invoke()
            return
        }
        ready = true
        flush(engine)
    }

    private fun flush(engine: TextToSpeech) {
        val next = pending ?: return
        pending = null
        if (!selectVoice(engine, next.request.languageTag)) {
            next.onUnavailable()
            scheduleRelease()
            return
        }
        engine.setSpeechRate(next.request.rate)
        current = next
        if (engine.speak(next.request.text, TextToSpeech.QUEUE_FLUSH, null, "u") != TextToSpeech.SUCCESS) {
            current = null
            next.onUnavailable()
            scheduleRelease()
        }
    }

    /** The exact locale when installed, otherwise any installed voice of the same language. */
    private fun selectVoice(engine: TextToSpeech, tag: String): Boolean {
        val locale = Locale.forLanguageTag(tag)
        val result = engine.setLanguage(locale)
        if (result >= TextToSpeech.LANG_AVAILABLE) return true
        val voice = runCatching {
            engine.voices.orEmpty().firstOrNull {
                it.locale.language == locale.language &&
                    !it.isNetworkConnectionRequired
            }
        }.getOrNull() ?: return false
        return engine.setVoice(voice) == TextToSpeech.SUCCESS
    }

    private fun finished() {
        val done = current ?: return
        current = null
        scheduleRelease()
        done.onDone()
    }

    override fun stop() {
        pending = null
        current = null
        tts?.stop()
        scheduleRelease()
    }

    override fun release() {
        main.removeCallbacks(releaseLater)
        pending = null
        current = null
        ready = false
        tts?.run {
            stop()
            shutdown()
        }
        tts = null
    }

    private fun scheduleRelease() {
        main.removeCallbacks(releaseLater)
        main.postDelayed(releaseLater, IDLE_RELEASE_MS)
    }

    companion object {
        const val IDLE_RELEASE_MS = 30_000L
    }
}
