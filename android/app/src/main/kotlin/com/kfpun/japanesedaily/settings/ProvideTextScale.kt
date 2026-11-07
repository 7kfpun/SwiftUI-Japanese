package com.kfpun.japanesedaily.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density

/**
 * Multiplies the learner's own text-size step ([TextSize]) onto the phone's font scale for everything
 * below it. Every text style is in `sp`, so the whole app follows; `Theme.display`, which divides the
 * font scale out, stays the same size, as designed.
 */
@Composable
fun ProvideTextScale(content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val scaled = Density(density.density, density.fontScale * TextSize.liveScale)
    CompositionLocalProvider(LocalDensity provides scaled, content = content)
}
