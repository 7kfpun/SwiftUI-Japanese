package com.kfpun.japanesedaily

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.kfpun.japanesedaily.ads.AdBanner
import com.kfpun.japanesedaily.ads.AdConsent
import com.kfpun.japanesedaily.ads.AdSlot
import com.kfpun.japanesedaily.audio.ProvidePronouncer
import com.kfpun.japanesedaily.billing.Entitlement
import com.kfpun.japanesedaily.billing.LocalPro
import com.kfpun.japanesedaily.billing.PaywallHost
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.ui.AppScaffold
import com.kfpun.japanesedaily.ui.JapaneseDailyTheme
import com.kfpun.japanesedaily.ui.Tab

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Debug builds only: `--ez demo_billing true` sells made-up plans without Play (screenshots, emulators).
        if (intent.getBooleanExtra(EXTRA_DEMO_BILLING, false)) AppContainer.useDemoBilling()
        // Decode the course data and load Practice stages off the main thread.
        val container = AppContainer.from(this)
        container.preload()
        container.interstitials.attach(this)
        // Debug builds only: `--es open_paywall settings` opens the paywall at launch (screenshots, UI checks).
        if (BuildConfig.DEBUG) intent.getStringExtra(EXTRA_OPEN_PAYWALL)?.let { container.openPaywall(it) }
        setContent {
            JapaneseDailyTheme {
                val entitlement by container.pro.entitlement.collectAsStateWithLifecycle()
                // Consent first, then ads: for free users only, once Pro has been read (a Pro user never
                // sees the consent form). Banners and interstitials wait on AdConsent.canRequestAds.
                LaunchedEffect(entitlement) {
                    if (entitlement == Entitlement.FREE || entitlement == Entitlement.PENDING) {
                        AdConsent.gather(this@MainActivity)
                        container.interstitials.preload()
                    }
                }
                CompositionLocalProvider(LocalPro provides container.pro) {
                    ProvidePronouncer(container.vocab) {
                        AppScaffold(banner = { tab -> AdBanner(tab.adSlot) })
                        PaywallHost(container.paywall, container.pro)
                    }
                }
            }
        }
    }

    companion object {
        const val EXTRA_DEMO_BILLING = "demo_billing"
        const val EXTRA_OPEN_PAYWALL = "open_paywall"
    }
}

/** The banner slot of each tab: iOS `RootView` gives Today, Kana, Lessons and Progress their own and Settings `about`. */
private val Tab.adSlot: AdSlot
    get() = when (this) {
        Tab.Today -> AdSlot.Today
        Tab.Kana -> AdSlot.Kana
        Tab.Lessons -> AdSlot.Lessons
        Tab.Progress -> AdSlot.Progress
        Tab.Settings -> AdSlot.About
    }
