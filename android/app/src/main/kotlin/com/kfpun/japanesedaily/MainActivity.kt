package com.kfpun.japanesedaily

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import com.kfpun.japanesedaily.ads.AdBanner
import com.kfpun.japanesedaily.ads.AdConsent
import com.kfpun.japanesedaily.ads.AdSlot
import com.kfpun.japanesedaily.ads.LocalBannerSlot
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.audio.PremiumStatus
import com.kfpun.japanesedaily.audio.ProvidePronouncer
import com.kfpun.japanesedaily.billing.Entitlement
import com.kfpun.japanesedaily.billing.LocalPro
import com.kfpun.japanesedaily.billing.PaywallHost
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.intro.Intro
import com.kfpun.japanesedaily.intro.IntroHost
import com.kfpun.japanesedaily.lessons.LessonExits
import com.kfpun.japanesedaily.lessons.LocalLessonExits
import com.kfpun.japanesedaily.lessons.LocalOpenPaywall
import com.kfpun.japanesedaily.lessons.LocalPremium
import com.kfpun.japanesedaily.lessons.OpenPaywall
import com.kfpun.japanesedaily.rating.RatingHost
import com.kfpun.japanesedaily.settings.ProvideTextScale
import com.kfpun.japanesedaily.settings.Reminders
import com.kfpun.japanesedaily.settings.SystemReminderNotifier
import com.kfpun.japanesedaily.today.TodayWidgetUpdater
import com.kfpun.japanesedaily.ui.AppScaffold
import com.kfpun.japanesedaily.ui.JapaneseDailyTheme
import com.kfpun.japanesedaily.ui.Tab
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {
    /** A tab a deep link asked for (the widget), consumed by `AppScaffold`. */
    private val tabRequest = mutableStateOf<Tab?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handleDeepLink(intent)
        enableEdgeToEdge()
        // Debug builds only: `--ez demo_billing true` sells made-up plans without Play (screenshots, emulators).
        if (intent.getBooleanExtra(EXTRA_DEMO_BILLING, false)) AppContainer.useDemoBilling()
        // Decode the course data and load Practice stages off the main thread.
        val container = AppContainer.from(this)
        container.preload()
        // Redraw the widget if the language changed while the app wasn't running, and keep its hourly redraw armed.
        lifecycleScope.launch(Dispatchers.Default) { TodayWidgetUpdater.onAppStart(applicationContext) }
        container.interstitials.attach(this)
        // Debug builds only: `--es open_paywall settings` opens the paywall at launch (screenshots, UI checks).
        if (BuildConfig.DEBUG) intent.getStringExtra(EXTRA_OPEN_PAYWALL)?.let { container.openPaywall(it) }
        // A launch re-plans the streak reminder (and restarts its week): the learner is evidently still here.
        Reminders.reschedule(this)
        if (intent?.getBooleanExtra(SystemReminderNotifier.EXTRA_FROM_REMINDER, false) == true) {
            Track.event(TrackEvents.NOTIFICATION_OPENED, mapOf("source" to "streak_reminder"))
        }
        setContent {
            ProvideTextScale {
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
                    // The Lessons seams (lessons/Ports.kt), wired to the real pieces. LocalPremium is a view of
                    // ProRepository (one source) that changes identity with the entitlement, so readers recompose.
                    val premium = remember(entitlement) {
                        object : PremiumStatus {
                            override val isPremium get() = container.pro.isPremium
                        }
                    }
                    val openPaywall =
                        remember { OpenPaywall { source, lesson -> container.openPaywall(source, lesson) } }
                    val exits = remember {
                        object : LessonExits {
                            override fun onLeavePractice(answered: Boolean) = container.onLeavePractice(answered)

                            override fun onLeaveMatch(answered: Boolean) = container.onLeavePractice(answered)
                        }
                    }
                    CompositionLocalProvider(
                        LocalPro provides container.pro,
                        LocalPremium provides premium,
                        LocalOpenPaywall provides openPaywall,
                        LocalLessonExits provides exits
                    ) {
                        ProvidePronouncer(container.vocab) {
                            IntroHost { landing ->
                                AppScaffold(
                                    startTab = if (landing == Intro.Tab.KANA) Tab.Kana else Tab.Today,
                                    banner = { tab -> AdBanner(LocalBannerSlot.current?.override ?: tab.adSlot) },
                                    tabRequest = tabRequest.value,
                                    onTabRequestHandled = { tabRequest.value = null }
                                )
                            }
                            PaywallHost(container.paywall, container.pro)
                            // The star row, over the whole app: the ladder raises it after a passed rung.
                            RatingHost()
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    /** The widget's tap: opens Today, and counts as a `widget_open` (a launch is otherwise just a cold start). */
    private fun handleDeepLink(intent: Intent?) {
        if (intent?.action != ACTION_OPEN_TODAY) return
        Track.event(TrackEvents.WIDGET_OPEN, mapOf("lesson" to intent.getIntExtra(EXTRA_WIDGET_LESSON, 0)))
        tabRequest.value = Tab.Today
    }

    companion object {
        const val ACTION_OPEN_TODAY = "com.kfpun.japanesedaily.action.OPEN_TODAY"
        const val EXTRA_WIDGET_LESSON = "widget_lesson"
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
