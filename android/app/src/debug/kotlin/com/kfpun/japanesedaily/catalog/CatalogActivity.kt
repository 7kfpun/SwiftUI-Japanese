package com.kfpun.japanesedaily.catalog

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.ui.JapaneseDailyTheme
import com.kfpun.japanesedaily.ui.JapaneseFace
import com.kfpun.japanesedaily.ui.KanaForm
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.VocabForm
import com.kfpun.japanesedaily.ui.components.CardStackPeek
import com.kfpun.japanesedaily.ui.components.EmptyStatePanel
import com.kfpun.japanesedaily.ui.components.IconWell
import com.kfpun.japanesedaily.ui.components.Illustration
import com.kfpun.japanesedaily.ui.components.OptionGrid
import com.kfpun.japanesedaily.ui.components.PrimaryPillButton
import com.kfpun.japanesedaily.ui.components.QuizOptionButton
import com.kfpun.japanesedaily.ui.components.StampSpec
import com.kfpun.japanesedaily.ui.components.SwipeCard
import com.kfpun.japanesedaily.ui.components.SwipeOptionChip
import com.kfpun.japanesedaily.ui.components.accentPlate
import com.kfpun.japanesedaily.ui.components.cardChrome
import com.kfpun.japanesedaily.ui.components.cardPager
import com.kfpun.japanesedaily.ui.components.cardSwipe
import com.kfpun.japanesedaily.ui.components.rememberCardPagerState
import com.kfpun.japanesedaily.ui.components.rememberCardSwipeState
import com.kfpun.japanesedaily.ui.components.selectionBorder
import com.kfpun.japanesedaily.ui.glyphStyle

/**
 * Debug-only components catalog: every token and component in one scrolling screen. It renders in
 * whichever appearance and font scale the device is set to, which is how the screenshots at light,
 * dark and font scale 2.0 are taken (adb shell cmd uimode night yes; settings put system font_scale 2.0).
 *
 * A developer-only surface, deliberately unlocalised (like Diagnostics on iOS): its labels are
 * literals, not `UIStrings.json` entries, and it is not compiled into release builds.
 */
class CatalogActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val section = intent.getStringExtra(EXTRA_SECTION)
        setContent { JapaneseDailyTheme { Catalog(section) } }
    }

    companion object {
        /** Optional: scroll the catalog to one of [SECTIONS] first (adb ... --es section cards). */
        const val EXTRA_SECTION = "section"
        val SECTIONS = listOf("tokens", "type", "cards", "options", "empty", "rating")
    }
}

@Composable
private fun Catalog(section: String?) {
    val scroll = rememberScrollState()
    val colors = Theme.colors
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.canvas)
            .safeDrawingPadding()
            .verticalScroll(scroll)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        val show = { name: String -> section == null || section == name }
        Text("Components catalog", style = Theme.title(Theme.text.largeTitle), color = colors.ink)
        if (show("tokens")) {
            ColorTokens()
            Radii()
        }
        if (show("type")) TypeAndFaces()
        if (show("cards")) Cards()
        if (show("options")) {
            QuizOptions()
            Chrome()
        }
        if (show("empty")) {
            EmptyState()
            TabBar()
        }
        if (show("rating")) RatingStarRow()
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = Theme.title(Theme.text.title3), color = Theme.colors.ink)
        content()
    }
}

@Composable
private fun ColorTokens() = Section("Colour tokens") {
    val c = Theme.colors
    val tokens = listOf(
        "accent" to c.accent, "correct" to c.correct, "wrong" to c.wrong, "surface" to c.surface,
        "canvas" to c.canvas, "line" to c.line, "shadow" to c.shadow, "streak" to c.streak,
        "star" to c.star, "onAccent" to c.onAccent, "ink" to c.ink, "inkSecondary" to c.inkSecondary,
        "inkTertiary" to c.inkTertiary
    )
    Column(Modifier.cardChrome().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        tokens.forEach { (name, color) ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(
                    Modifier.size(
                        32.dp
                    ).background(color, Theme.rounded(Theme.Radius.inset)).cardChrome(Theme.Radius.inset)
                )
                Text(name, style = Theme.text.callout, color = c.ink)
            }
        }
        Text(
            "Green and red are answer feedback only. Cards (surface) sit lighter than the screen (canvas).",
            style = Theme.text.footnote,
            color = c.inkSecondary
        )
    }
}

@Composable
private fun Radii() = Section("Radius scale") {
    val radii = listOf(
        "tick" to Theme.Radius.tick,
        "inset" to Theme.Radius.inset,
        "chip" to Theme.Radius.chip,
        "row" to Theme.Radius.row,
        "card" to Theme.Radius.card,
        "pill" to Theme.Radius.pill,
        "deck" to Theme.Radius.deck,
        "hero" to Theme.Radius.hero
    )
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        radii.forEach { (_, r: Dp) -> Box(Modifier.weight(1f).height(36.dp).cardChrome(r)) }
    }
    Text(
        radii.joinToString(" / ") { "${it.first} ${it.second.value.toInt()}" },
        style = Theme.text.caption,
        color = Theme.colors.inkSecondary
    )
}

@Composable
private fun TypeAndFaces() = Section("Type scale and faces") {
    val c = Theme.colors
    val t = Theme.text
    Column(Modifier.fillMaxWidth().cardChrome().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf(
            "largeTitle 34" to t.largeTitle, "title 28" to t.title, "title2 22" to t.title2,
            "title3 20" to t.title3, "headline 17" to t.headline, "body 17" to t.body,
            "callout 16" to t.callout, "subheadline 15" to t.subheadline, "footnote 13" to t.footnote,
            "caption 12" to t.caption, "caption2 11" to t.caption2
        ).forEach { (name, style) -> Text(name, style = style, color = c.ink) }
        Text("Longest: Übergangsmäßig, Thiết bị, ကွန်ပျူတာ", style = t.body, color = c.ink)
    }
    Column(Modifier.fillMaxWidth().cardChrome().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        val sample = "日本語 にほんご ひらがな"
        Text("jp  $sample", style = Theme.jp(Theme.text.title2.fontSize), color = c.ink)
        Text("jpBold  あいうえお カキクケコ", style = Theme.jpBold(Theme.text.title2.fontSize), color = c.ink)
        Text("jpStrokes  あいうえお", style = Theme.jpStrokes(Theme.text.title.fontSize), color = c.ink)
        Text("display 26  Aa 123", style = Theme.display(26), color = c.ink)
        Text("Content script decides the face, not the screen:", style = t.footnote, color = c.inkSecondary)
        KanaForm.entries.forEach { form ->
            val value = when (form) {
                KanaForm.Hiragana -> "あ"
                KanaForm.Katakana -> "ア"
                KanaForm.Romaji -> "a"
            }
            Text("$form → $value", style = glyphStyle(form.isJapanese, 28, JapaneseFace.Bold), color = c.ink)
        }
        VocabForm.entries.forEach { form ->
            Text("$form isJapanese=${form.isJapanese}", style = t.footnote, color = c.inkSecondary)
        }
    }
}

@Composable
private fun Cards() = Section("Swipe card, CardPager and peeks") {
    var page by remember { mutableIntStateOf(0) }
    val words = listOf("学生" to "student", "先生" to "teacher", "会社員" to "company employee")
    val pager = rememberCardPagerState(canPage = { true }) { dir -> page = (page + dir).mod(words.size) }
    // The peek layers sit outside the card, so they do not move with it; cardPager is on the card.
    Box(Modifier.fillMaxWidth().height(230.dp)) {
        CardStackPeek(count = 2, modifier = Modifier.fillMaxSize())
        SwipeCard(Modifier.fillMaxSize().cardPager(pager), hint = "Swipe") {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(words[page].first, style = Theme.jp(Theme.text.largeTitle.fontSize), color = Theme.colors.ink)
                Text(words[page].second, style = Theme.text.callout, color = Theme.colors.inkSecondary)
            }
        }
    }
    Text("Drag the card left or right to page.", style = Theme.text.footnote, color = Theme.colors.inkSecondary)

    val swipe = rememberCardSwipeState()
    val left = StampSpec(R.drawable.ic_close, Theme.colors.wrong)
    val right = StampSpec(R.drawable.ic_check, Theme.colors.correct)
    Box(Modifier.fillMaxWidth().height(230.dp)) {
        SwipeCard(
            Modifier.fillMaxSize().cardSwipe(swipe) { toRight -> swipe.fling(toRight) { swipe.reset() } },
            drag = { swipe.offset },
            leftStamp = left,
            rightStamp = right,
            hint = "Swipe"
        ) { Text("Swipe to decide (stamps)", style = Theme.text.callout, color = Theme.colors.ink) }
    }
}

@Composable
private fun QuizOptions() = Section("Quiz options (answer feedback)") {
    val c = Theme.colors
    Text(
        "Open, then answered: correct pick, wrong pick, untouched",
        style = Theme.text.footnote,
        color = c.inkSecondary
    )
    val gloss = listOf("student", "teacher", "company employee, long gloss wraps", "doctor")
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.weight(1f)) { QuizOptionButton("student", 0, null, true, {}) }
        Box(Modifier.weight(1f)) { QuizOptionButton("teacher", 1, null, false, {}) }
    }
    OptionGrid(count = 4) { i -> QuizOptionButton(gloss[i], i, picked = 1, isAnswer = i == 0, onClick = {}) }
    Text("Swipe chips", style = Theme.text.footnote, color = c.inkSecondary)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.weight(1f)) { SwipeOptionChip("student", 0, null, true, {}, hint = "Swipe left") }
        Box(Modifier.weight(1f)) { SwipeOptionChip("teacher", 1, null, false, {}, hint = "Swipe right") }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.weight(1f)) { SwipeOptionChip("student", 0, 1, true, {}) }
        Box(Modifier.weight(1f)) { SwipeOptionChip("teacher", 1, 1, false, {}) }
    }
}

@Composable
private fun Chrome() = Section("Selection, plates, pills") {
    val c = Theme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.weight(1f).cardChrome().selectionBorder(true).padding(16.dp)) {
            Text("Selected: accent border", style = Theme.text.callout, color = c.ink)
        }
        Box(Modifier.weight(1f).cardChrome().padding(16.dp)) {
            Text("Not selected", style = Theme.text.callout, color = c.ink)
        }
    }
    Row(Modifier.fillMaxWidth().accentPlate().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        IconWell(R.drawable.ic_tab_lessons)
        IconWell(R.drawable.ic_tab_progress, active = false)
        Text("Accent plate: wash and hairline", style = Theme.text.callout, color = c.ink)
    }
    Row(Modifier.fillMaxWidth().accentPlate(tint = c.streak).padding(12.dp)) {
        Text("Streak plate: amber, never green or red", style = Theme.text.callout, color = c.ink)
    }
    PrimaryPillButton(onClick = {}) { Text("Next", style = Theme.text.headline) }
}

@Composable
private fun EmptyState() = Section("Empty state (koboyo illustration, tinted)") {
    Column(Modifier.fillMaxWidth().cardChrome(Theme.Radius.deck).heightIn(min = 120.dp)) {
        EmptyStatePanel("Nothing here yet. Finish a challenge and your progress shows up.") {
            Illustration(R.drawable.ill_skill_tree)
        }
    }
}

@Composable
private fun TabBar() = Section("Tab bar with a banner slot") {
    val c = Theme.colors
    Column(Modifier.fillMaxWidth().cardChrome(Theme.Radius.chip)) {
        Box(
            Modifier.fillMaxWidth().height(50.dp).background(c.canvas),
            contentAlignment = Alignment.Center
        ) { Text("banner slot", style = Theme.text.caption, color = c.inkSecondary, textAlign = TextAlign.Center) }
        NavigationBar(containerColor = c.surface) {
            listOf(R.drawable.ic_tab_today to "Today", R.drawable.ic_tab_lessons to "Lessons").forEachIndexed {
                    i,
                    (icon, label)
                ->
                NavigationBarItem(
                    selected = i == 0,
                    onClick = {},
                    icon = { Icon(painterResource(icon), contentDescription = null) },
                    label = { Text(label) }
                )
            }
        }
    }
}

/** The rating prompt's own star row (FOX-159), as the bottom sheet shows it; nothing is recorded here. */
@Composable
private fun RatingStarRow() = Section("Rating star row") {
    Column(Modifier.fillMaxWidth().cardChrome(Theme.Radius.deck)) {
        com.kfpun.japanesedaily.rating.RatingRow(picked = 4, onStar = {}, onNotNow = {})
    }
}
