package com.kfpun.japanesedaily.ui

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.AnalyticsExclusionFooter
import com.kfpun.japanesedaily.kana.KanaTab
import com.kfpun.japanesedaily.lessons.LessonsTab
import com.kfpun.japanesedaily.lessons.PaywallHost
import com.kfpun.japanesedaily.lessons.rememberLessonsNav

/** The five tabs, in the iOS app's order. Icons are Material Symbols (outlined). */
enum class Tab(@StringRes val label: Int, @DrawableRes val icon: Int) {
    Today(R.string.today, R.drawable.ic_tab_today),
    Kana(R.string.kana, R.drawable.ic_tab_translate),
    Lessons(R.string.lessons, R.drawable.ic_tab_lessons),
    Progress(R.string.progress, R.drawable.ic_tab_progress),
    Settings(R.string.settings, R.drawable.ic_tab_settings)
}

@Composable
fun AppScaffold(startTab: Tab = Tab.Today, banner: @Composable () -> Unit = {}) {
    var selected by rememberSaveable { mutableStateOf(startTab) }
    val lessonsNav = rememberLessonsNav()
    PaywallHost {
        Scaffold(
            bottomBar = {
                Column {
                    // The per-tab ad banner slot (FOX-158 fills it): above the tab bar, in a column rather
                    // than a safe-area inset, so a pushed screen's bottom button never renders under it.
                    banner()
                    TabBar(selected) { selected = it }
                }
            }
        ) { padding ->
            when (selected) {
                Tab.Kana -> KanaTab(Modifier.padding(padding))
                Tab.Lessons -> LessonsTab(lessonsNav, Modifier.padding(padding))
                else -> PlaceholderScreen(selected, Modifier.padding(padding))
            }
        }
    }
}

/** Every tab is empty until its ticket lands (Kana FOX-151, Lessons FOX-152, Today FOX-155, ...). */
@Composable
private fun PlaceholderScreen(tab: Tab, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(stringResource(tab.label), style = MaterialTheme.typography.headlineMedium)
        // The hidden analytics opt-out (FOX-160); the real Settings screen keeps this footer.
        if (tab == Tab.Settings) {
            AnalyticsExclusionFooter(Modifier.align(Alignment.BottomCenter).padding(16.dp))
        }
    }
}

@Composable
private fun TabBar(selected: Tab, onSelect: (Tab) -> Unit) {
    NavigationBar(containerColor = Theme.colors.surface) {
        Tab.entries.forEach { tab ->
            NavigationBarItem(
                selected = tab == selected,
                onClick = { onSelect(tab) },
                icon = { Icon(painterResource(tab.icon), contentDescription = null) },
                label = { Text(stringResource(tab.label)) }
            )
        }
    }
}
