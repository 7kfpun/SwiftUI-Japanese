package com.kfpun.japanesedaily.audio

import android.content.Context
import android.content.res.AssetManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.util.Log

private const val TAG = "MediaClipPlayer"

internal val speechAttributes: AudioAttributes = AudioAttributes.Builder()
    .setUsage(AudioAttributes.USAGE_MEDIA)
    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
    .build()

/**
 * Plays the bundled `.m4a` clips straight from the APK with the framework [MediaPlayer] (no extra
 * dependency; the clips are short AAC). Assets are stored uncompressed (`noCompress`), which is
 * what [AssetManager.openFd] needs. One clip at a time: [play] replaces the current one.
 */
class MediaClipPlayer(private val assets: AssetManager) : ClipPlayer {
    private var player: MediaPlayer? = null

    override fun play(path: String, rate: Float, onDone: () -> Unit): Boolean {
        stop()
        val p = MediaPlayer()
        return try {
            p.setAudioAttributes(speechAttributes)
            assets.openFd(path).use { p.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
            p.prepare()
            if (rate != 1f) {
                // Some API levels start playback when the speed is set; start() below is then a no-op.
                runCatching { p.playbackParams = p.playbackParams.setSpeed(rate) }
            }
            p.setOnCompletionListener {
                if (player === p) player = null
                p.release()
                onDone()
            }
            p.setOnErrorListener { _, what, extra ->
                Log.w(TAG, "clip $path failed: $what/$extra")
                if (player === p) player = null
                p.release()
                onDone()
                true
            }
            player = p
            p.start()
            true
        } catch (e: Exception) {
            Log.w(TAG, "clip $path could not play", e)
            p.release()
            false
        }
    }

    override fun stop() {
        val p = player ?: return
        player = null
        p.setOnCompletionListener(null)
        p.setOnErrorListener(null)
        runCatching { p.stop() }
        p.release()
    }

    override fun release() = stop()
}

/** Transient focus with ducking: music dips while a word plays and comes back after. */
class SystemAudioFocus(context: Context) : AudioFocus {
    private val manager = context.applicationContext.getSystemService(AudioManager::class.java)
    private var request: AudioFocusRequest? = null

    override fun request(onLost: () -> Unit): Boolean {
        abandon()
        val r = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(speechAttributes)
            .setWillPauseWhenDucked(false)
            .setOnAudioFocusChangeListener { change ->
                if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) onLost()
            }
            .build()
        val granted = manager.requestAudioFocus(r) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (granted) request = r
        return granted
    }

    override fun abandon() {
        val r = request ?: return
        request = null
        manager.abandonAudioFocusRequest(r)
    }
}
