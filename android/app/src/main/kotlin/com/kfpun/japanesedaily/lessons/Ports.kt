package com.kfpun.japanesedaily.lessons

import androidx.compose.runtime.staticCompositionLocalOf
import com.kfpun.japanesedaily.audio.NotPremium
import com.kfpun.japanesedaily.audio.PremiumStatus

/**
 * What the Lessons tab needs from the rest of the app, as composition locals with safe defaults, so
 * this feature compiles and runs before the tickets that supply them land:
 *
 * - [LocalPremium]: whether the user has Pro. `MainActivity` provides `ProRepository` (one source); the
 *   default [NotPremium] fails closed.
 * - [LocalOpenPaywall]: opens the paywall. `MainActivity` provides `AppContainer.openPaywall`.
 * - [LocalLessonExits]: the interstitial hooks. `MainActivity` provides the throttled interstitial.
 */
val LocalPremium = staticCompositionLocalOf<PremiumStatus> { NotPremium }

/** `source` is the analytics source (`TrackPaywallSources`), `lesson` the lesson that asked, if any. */
fun interface OpenPaywall {
    fun open(source: String, lesson: Int?)
}

val LocalOpenPaywall = staticCompositionLocalOf { OpenPaywall { _, _ -> } }

/**
 * Called when a practice screen is left. `answered` is whether anything was graded this sitting
 * (`PracticeModel.answered > 0`, `MatchModel.attempts > 0`): the same gate iOS uses for its
 * way-out interstitial, which `MainActivity` wires to the throttled interstitial; only non-premium users see it.
 */
interface LessonExits {
    fun onLeavePractice(answered: Boolean) = Unit

    fun onLeaveMatch(answered: Boolean) = Unit
}

val LocalLessonExits = staticCompositionLocalOf<LessonExits> { object : LessonExits {} }
