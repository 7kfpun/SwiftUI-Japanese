package com.kfpun.japanesedaily.ads

import android.util.Log
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.LoadAdError
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.billing.LocalPro
import com.kfpun.japanesedaily.billing.ProRepository

/**
 * An AdMob banner for a screen slot (iOS `AdBannerView`), for [AppScaffold]'s banner slot. It takes
 * no space at all for Pro, until consent allows ads ([AdsPolicy]), and until an ad has actually
 * arrived: the view keeps its full size internally (the SDK refuses to load into a zero-sized view)
 * while the visible box is 0 high, so there is no blank gap. A no-fill logs `ad_failed` with the slot.
 */
@Composable
fun AdBanner(slot: AdSlot, modifier: Modifier = Modifier, pro: ProRepository? = LocalPro.current) {
    if (pro == null) return
    val entitlement by pro.entitlement.collectAsStateWithLifecycle()
    val canRequestAds by AdConsent.canRequestAds.collectAsStateWithLifecycle()
    if (!AdsPolicy.showBanner(entitlement, canRequestAds)) return

    val context = LocalContext.current
    BoxWithConstraints(modifier = modifier.fillMaxWidth()) {
        val width = maxWidth.value.toInt()
        key(slot, width) {
            val adSize = remember(width) { AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(context, width) }
            BannerView(slot, adSize)
        }
    }
}

@Composable
private fun BannerView(slot: AdSlot, adSize: AdSize) {
    var adView by remember { mutableStateOf<AdView?>(null) }
    var loadedHeight by remember { mutableIntStateOf(0) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, adView) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_PAUSE -> adView?.pause()
                Lifecycle.Event.ON_RESUME -> adView?.resume()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    AndroidView(
        modifier = Modifier
            .fillMaxWidth()
            .height(loadedHeight.dp)
            .clipToBounds()
            .wrapContentHeight(align = Alignment.Top, unbounded = true),
        factory = { viewContext ->
            AdView(viewContext).apply {
                setAdSize(adSize)
                adUnitId = slot.unitId
                adListener = object : AdListener() {
                    override fun onAdLoaded() {
                        loadedHeight = adSize.height
                    }

                    override fun onAdFailedToLoad(error: LoadAdError) {
                        loadedHeight = 0
                        Log.w("JDAds", "Banner ${slot.analyticsName} failed: ${error.code} ${error.message}")
                        // `slot` is the point of the event: one broken unit must not read as every ad failing.
                        Track.event(
                            TrackEvents.AD_FAILED,
                            mapOf("error" to error.message, "slot" to slot.analyticsName)
                        )
                    }
                }
                loadAd(AdConsent.request())
                adView = this
            }
        },
        onRelease = { it.destroy() }
    )
}
