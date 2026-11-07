package com.kfpun.japanesedaily.ui

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.ads.BannerSlotState
import com.kfpun.japanesedaily.ads.LocalBannerSlot
import com.kfpun.japanesedaily.kana.KanaTab
import com.kfpun.japanesedaily.lessons.LessonsNav
import com.kfpun.japanesedaily.lessons.LessonsTab
import com.kfpun.japanesedaily.lessons.rememberLessonsNav
import com.kfpun.japanesedaily.progress.ProgressTab
import com.kfpun.japanesedaily.settings.SettingsTab
import com.kfpun.japanesedaily.today.TodayNav
import com.kfpun.japanesedaily.today.TodayTab

/** The five tabs, in the iOS app's order. Icons are Material Symbols (outlined). */
enum class Tab(@StringRes val label: Int, @DrawableRes val icon: Int) {
    Today(R.string.today, R.drawable.ic_tab_today),
    Kana(R.string.kana, R.drawable.ic_tab_translate),
    Lessons(R.string.lessons, R.drawable.ic_tab_lessons),
    Progress(R.string.progress, R.drawable.ic_tab_progress),
    Settings(R.string.settings, R.drawable.ic_tab_settings)
}

@Composable
fun AppScaffold(
    startTab: Tab = Tab.Today,
    banner: @Composable (Tab) -> Unit = {},
    tabRequest: Tab? = null,
    onTabRequestHandled: () -> Unit = {}
) {
    var selected by rememberSaveable { mutableStateOf(startTab) }
    val lessonsNav = rememberLessonsNav()
    // A deep link (the widget) asks for a tab while the app is already running.
    LaunchedEffect(tabRequest) {
        if (tabRequest != null) {
            selected = tabRequest
            onTabRequestHandled()
        }
    }
    val progressNav = rememberLessonsNav()
    val bannerSlot = remember { BannerSlotState() }
    ProvideWindowLayout {
        val regular = isRegularWidth()
        CompositionLocalProvider(LocalBannerSlot provides bannerSlot) {
            // The window size class picks the bar (compact) or the rail (regular, 600 dp and up). The suite lays the
            // rail beside the content, so the ad banner below sits above the content's bottom edge, never under it.
            NavigationSuiteScaffold(
                navigationSuiteItems = {
                    Tab.entries.forEach { tab ->
                        item(
                            selected = tab == selected,
                            onClick = { selected = tab },
                            icon = { Icon(painterResource(tab.icon), contentDescription = null) },
                            label = { Text(stringResource(tab.label)) }
                        )
                    }
                },
                layoutType = if (regular) NavigationSuiteType.NavigationRail else NavigationSuiteType.NavigationBar,
                navigationSuiteColors = NavigationSuiteDefaults.colors(
                    navigationBarContainerColor = Theme.colors.surface,
                    navigationRailContainerColor = Theme.colors.surface
                ),
                containerColor = Theme.colors.canvas
            ) {
                // Tabs draw their own status-bar inset (`statusBarsPadding` on each screen and `LessonScreenFrame`),
                // and this host adds none, so the gap above a title is counted once. Kana, which has none of its
                // own, gets it below. Beside a rail the bar and the far edge are this column's to pad.
                val edges = if (regular) {
                    Modifier.windowInsetsPadding(
                        WindowInsets.systemBars.only(WindowInsetsSides.End + WindowInsetsSides.Bottom)
                    )
                } else {
                    Modifier
                }
                Column(Modifier.fillMaxSize().then(edges)) {
                    Box(Modifier.weight(1f).fillMaxWidth()) {
                        TabContent(selected, lessonsNav, progressNav) { selected = it }
                    }
                    banner(selected)
                }
            }
        }
    }
}

@Composable
private fun TabContent(selected: Tab, lessonsNav: LessonsNav, progressNav: LessonsNav, select: (Tab) -> Unit) {
    val modifier = Modifier
    when (selected) {
        Tab.Today -> ReadableWidth {
            ScrollIfShort {
                TodayTab(
                    TodayNav(
                        openLesson = { lesson ->
                            lessonsNav.openLesson(lesson)
                            select(Tab.Lessons)
                        },
                        openLessonList = {
                            lessonsNav.openList()
                            select(Tab.Lessons)
                        },
                        openProgress = { select(Tab.Progress) }
                    ),
                    modifier
                )
            }
        }

        Tab.Kana -> ReadableWidth { KanaTab(Modifier.statusBarsPadding()) }

        // Two panes at regular width draw their own widths; the list and the right pane cap themselves.
        Tab.Lessons -> LessonsTab(lessonsNav, modifier)

        Tab.Progress -> ReadableWidth { ProgressTab(progressNav, modifier) }

        Tab.Settings -> ReadableWidth { SettingsTab(modifier) }
    }
}
