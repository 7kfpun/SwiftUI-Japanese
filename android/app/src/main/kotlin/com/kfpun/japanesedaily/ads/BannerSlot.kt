package com.kfpun.japanesedaily.ads

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * Which banner unit the scaffold's one banner uses right now. A tab has a default slot; a pushed screen
 * with its own slot (select-mode, vocab-list, search) declares it with [UseBannerSlot], so the screen
 * keeps a single banner above the tab bar but reports and earns on its own unit.
 */
class BannerSlotState {
    var override by mutableStateOf<AdSlot?>(null)
}

val LocalBannerSlot = staticCompositionLocalOf<BannerSlotState?> { null }

/** For as long as this is in the composition, the banner uses [slot] (null keeps the tab's own). */
@Composable
fun UseBannerSlot(slot: AdSlot?) {
    val state = LocalBannerSlot.current
    DisposableEffect(state, slot) {
        state?.override = slot
        onDispose { if (state != null && state.override == slot) state.override = null }
    }
}
