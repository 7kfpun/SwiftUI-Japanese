package com.kfpun.japanesedaily.analytics

import androidx.compose.foundation.clickable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import com.kfpun.japanesedaily.BuildConfig

/**
 * Counts consecutive taps: [threshold] within [windowMillis] of each other fires once, then resets. A
 * pause longer than the window starts over, so a stray tap never adds up across a session.
 */
class TapCounter(private val threshold: Int = 7, private val windowMillis: Long = 1500) {
    private var count = 0
    private var lastTap = Long.MIN_VALUE

    /** True on the tap that reaches the threshold. [nowMillis] is injectable for tests. */
    fun tap(nowMillis: Long): Boolean {
        count = if (lastTap != Long.MIN_VALUE && nowMillis - lastTap <= windowMillis) count + 1 else 1
        lastTap = nowMillis
        if (count < threshold) return false
        count = 0
        lastTap = Long.MIN_VALUE
        return true
    }
}

/**
 * The version line at the foot of Settings, and the hidden developer affordance: seven quick taps flip the
 * per-device analytics opt-out ([Track.setExcluded]). The suffix is the only at-a-glance cue, as on iOS.
 * A developer-only surface, so the text is deliberately unlocalised.
 */
@Composable
fun AnalyticsExclusionFooter(modifier: Modifier = Modifier) {
    val counter = remember { TapCounter() }
    val haptics = LocalHapticFeedback.current
    var excluded by remember { mutableStateOf(Track.isExcluded) }
    Text(
        text = BuildConfig.VERSION_NAME + if (excluded) " • Analytics off" else "",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.clickable {
            if (counter.tap(System.currentTimeMillis())) {
                Track.setExcluded(!Track.isExcluded)
                excluded = Track.isExcluded
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            }
        }
    )
}
