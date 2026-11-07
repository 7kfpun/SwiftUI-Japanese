package com.kfpun.japanesedaily.rating

import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.prefs.Prefs
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * Asks for a rating, but only from people who have earned the right to be asked, and no more than once
 * every couple of months (port of `RatingPrompt.swift`; `context/06-monetization.md`).
 *
 * The shape is deliberate: **the app's own star row first**, and only a 4- or 5-star pick hands off to Play
 * In-App Review. A lower pick opens the feedback screen with the stars attached. Play gives no signal about
 * what was submitted and rations how often its sheet shows, so spending one on someone about to leave two
 * stars wastes the only asks the app gets.
 *
 * This is **not a rating gate**: the stores prohibit making a review path conditional on sentiment, and
 * nothing here blocks anyone. The star row is the app's own question, every answer leads somewhere, and the
 * store page stays reachable from Settings ("Rate the app") whatever was answered.
 */
object RatingPrompt {
    /**
     * Rungs that must be passed before the app asks anything: several lessons of real use, so the ask
     * lands on people who stayed rather than people who looked. Three times the share nudge's bar.
     */
    const val CHALLENGES_REQUIRED = 21

    /** How long the app waits before it may ask again: two months, inside Play's own rationing. */
    val askAgainAfter: Duration = Duration.ofDays(60)

    /** Whether enough time has passed since [lastAskedAt] (epoch millis, 0 for never). */
    fun mayAskAgain(lastAskedAt: Long, now: Instant): Boolean =
        lastAskedAt <= 0L || Duration.between(Instant.ofEpochMilli(lastAskedAt), now) >= askAgainAfter

    /**
     * Whether to ask after this rung. **Everyone, not just subscribers**: a rung they just *passed* (asking
     * straight after a failure asks how they feel about failing), enough rungs cleared to have an opinion,
     * and the window. [passedCount] is `ProgressRepository.totalPassed()`, deduplicated by id so a later
     * merge cannot fire it early.
     */
    fun shouldAsk(passed: Boolean, passedCount: Int, lastAskedAt: Long, now: Instant): Boolean =
        passed && passedCount >= CHALLENGES_REQUIRED && mayAskAgain(lastAskedAt, now)

    /** 4 stars and up goes to Play's sheet; anything lower to feedback. Never conditions *access* to a review. */
    fun handsOffToStore(stars: Int): Boolean = stars >= STORE_MINIMUM

    private const val STORE_MINIMUM = 4
}

/** A star row waiting to be shown. [passedTotal] rides along for the events. */
data class RatingOffer(val passedTotal: Int)

/**
 * The seam the Challenge ladder (FOX-154) calls. [onRungPassed] is only for a rung the learner just
 * passed; it decides, stamps the ask, logs `rating_shown` and raises [offer], which `RatingHost` shows.
 * The ask is stamped when it is *shown*, not when answered, so a dismissed row also waits two months.
 */
class RatingCoordinator(
    private val prefs: Prefs,
    private val scope: CoroutineScope,
    private val clock: () -> Instant = { Instant.now() },
    /** A beat so the result screen is on screen behind the row rather than under it. */
    private val deferMillis: Long = 800
) {
    private val pending = MutableStateFlow<RatingOffer?>(null)

    /** The row to show, or null. */
    val offer: StateFlow<RatingOffer?> = pending

    fun onRungPassed(totalPassed: Int) {
        scope.launch {
            val now = clock()
            if (pending.value != null) return@launch
            if (!RatingPrompt.shouldAsk(true, totalPassed, prefs.get(Pref.ratingAskedAt), now)) return@launch
            prefs.set(Pref.ratingAskedAt, now.toEpochMilli())
            Track.event(TrackEvents.RATING_SHOWN, mapOf("passed_total" to totalPassed, "source" to "challenge"))
            delay(deferMillis)
            pending.value = RatingOffer(totalPassed)
        }
    }

    /** The row has been answered or dismissed. */
    fun consume() {
        pending.value = null
    }
}
