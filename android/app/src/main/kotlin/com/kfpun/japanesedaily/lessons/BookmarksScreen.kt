package com.kfpun.japanesedaily.lessons

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.data.Course
import com.kfpun.japanesedaily.data.progress.Bookmark
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.EmptyStatePanel
import com.kfpun.japanesedaily.ui.components.SymbolIcon

/**
 * The saved-words shelf in three groups, highest tier first. Headers are literal star glyphs rather than
 * words: what each tier means is the user's own decision, so naming them would impose a meaning. Saved ids are
 * resolved back to words in the *current* meaning language, one lesson at a time rather than the whole corpus.
 */
@Composable
fun BookmarksScreen(env: LessonsEnv, nav: LessonsNav, modifier: Modifier = Modifier) {
    val container = env.container
    val saved by remember { container.progress.observeBookmarks() }.collectAsState(emptyList())
    val tiers = remember(saved) { saved.associate { it.word to Bookmark.clamp(it.stars) } }
    val groups = remember(saved, env.language) {
        val byId = HashMap<String, Vocab>()
        for (lesson in saved.map { it.lesson }.toSet().filter { Course.current.hasLesson(it) }) {
            for (word in env.lesson(lesson).entries) byId[word.id] = word
        }
        // A row whose word no longer resolves is skipped rather than rendered blank.
        saved.mapNotNull { row -> byId[row.word]?.let { Bookmark.clamp(row.stars) to it } }
            .groupBy({ it.first }, { it.second })
    }
    LaunchedEffect(Unit) { Track.screen(TrackScreens.BOOKMARKS) }

    LessonScreenFrame(stringResource(R.string.bookmarks), onBack = { nav.pop() }, modifier = modifier) {
        if (groups.values.all { it.isEmpty() }) {
            Box(Modifier.fillMaxSize()) {
                EmptyStatePanel(
                    stringResource(R.string.tap_the_star_beside_any_word_to_save_it_here),
                    Modifier.fillMaxSize()
                ) {
                    SymbolIcon(R.drawable.ic_star_outline, Theme.colors.accent, EMPTY_ICON_SP)
                }
            }
        } else {
            LazyColumn(Modifier.fillMaxSize()) {
                for (tier in listOf(3, 2, 1)) {
                    val words = groups[tier].orEmpty()
                    if (words.isEmpty()) continue
                    item(key = "h$tier") {
                        Text(
                            "★".repeat(tier),
                            style = Theme.title(Theme.text.footnote),
                            color = Theme.colors.accent,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
                        )
                    }
                    items(words, key = { "$tier/${it.id}" }) { v ->
                        VocabRow(v, container, tiers, surface = "bookmarks", showLesson = true)
                        HorizontalDivider(color = Theme.colors.line)
                    }
                }
            }
        }
    }
}

private const val EMPTY_ICON_SP = 34
