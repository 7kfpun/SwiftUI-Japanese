@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.kfpun.japanesedaily.lessons

import androidx.annotation.DrawableRes
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.progress.Bookmark
import com.kfpun.japanesedaily.data.progress.WordStage
import com.kfpun.japanesedaily.data.vocab.ExampleSentence
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.ui.ReadableWidth
import com.kfpun.japanesedaily.ui.ScrollIfShort
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.SoundToggle
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.scaledSize
import kotlinx.coroutines.launch

// region Chrome

/**
 * The pushed-screen frame: a back arrow, a centred title (with an optional line under it) and trailing
 * actions, over the canvas. Material's `TopAppBar` would add chrome the iOS navigation bar does not have.
 */
@Composable
fun LessonScreenFrame(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    center: (@Composable () -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
    showBack: Boolean = true,
    scrollIfShort: Boolean = false,
    content: @Composable () -> Unit
) {
    // The canvas is full-bleed; the bar and the content are capped at the readable width and centred (FOX-166).
    Column(modifier.fillMaxSize().background(Theme.colors.canvas).statusBarsPadding()) {
        ReadableWidth { FrameBody(title, onBack, subtitle, center, actions, showBack, scrollIfShort, content) }
    }
}

@Composable
private fun FrameBody(
    title: String,
    onBack: () -> Unit,
    subtitle: String?,
    center: (@Composable () -> Unit)?,
    actions: @Composable RowScope.() -> Unit,
    showBack: Boolean,
    scrollIfShort: Boolean,
    content: @Composable () -> Unit
) {
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (showBack) {
                ToolbarButton(R.drawable.ic_arrow_back, stringResource(R.string.back), onBack)
            } else {
                Spacer(Modifier.size(48.dp))
            }
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                if (center != null) {
                    center()
                } else {
                    Text(
                        title,
                        style = Theme.title(Theme.text.headline),
                        color = Theme.colors.ink,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                if (subtitle != null) {
                    Text(subtitle, style = Theme.text.caption2, color = Theme.colors.inkSecondary, maxLines = 1)
                }
            }
            Row(Modifier.widthIn(min = 48.dp), horizontalArrangement = Arrangement.End, content = actions)
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (scrollIfShort) ScrollIfShort(content = content) else content()
        }
    }
}

/** A toolbar glyph with a real 48dp target. */
@Composable
fun ToolbarButton(
    @DrawableRes icon: Int,
    description: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = Theme.colors.accent,
    enabled: Boolean = true
) {
    Box(
        modifier
            .size(48.dp)
            .clip(CircleShape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center
    ) {
        SymbolIcon(icon, if (enabled) tint else Theme.colors.inkTertiary, Theme.text.title3.fontSize.value.toInt())
    }
}

/** The small caps label above a group of rows. */
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(),
        style = Theme.text.footnote.copy(fontWeight = FontWeight.SemiBold),
        color = Theme.colors.inkSecondary,
        modifier = modifier
    )
}

/** A capsule progress bar: a track and a proportional fill, the fraction clamped here once. */
@Composable
fun CapsuleBar(
    fraction: Double,
    modifier: Modifier = Modifier,
    height: Int = 6,
    track: Color = Theme.colors.line,
    fill: Color = Theme.colors.accent
) {
    val shape = Theme.rounded(100.dp)
    Box(modifier.fillMaxWidth().height(height.dp).clip(shape).background(track, shape)) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(fraction.toFloat().coerceIn(0f, 1f)).background(fill, shape))
    }
}

/** Three stars, filled to [stars]. Shared by the ladder chips and the retry card. */
@Composable
fun StarRow(stars: Int, sizeSp: Int = 13, modifier: Modifier = Modifier) {
    val description = stringResource(R.string.arg_of_3_stars, stars.toString())
    Row(
        modifier.semantics { contentDescription = description },
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        for (i in 1..3) {
            SymbolIcon(
                if (i <= stars) R.drawable.ic_star else R.drawable.ic_star_outline,
                if (i <= stars) Theme.colors.star else Theme.colors.inkTertiary,
                sizeSp
            )
        }
    }
}

/** Where a word stands, as one dot: filled memorised, faded met, hollow unseen. */
@Composable
fun StageDot(stage: WordStage, modifier: Modifier = Modifier) {
    val accent = Theme.colors.accent
    val fill = when {
        stage == WordStage.Memorized -> accent
        stage >= WordStage.Seen -> accent.copy(alpha = 0.35f)
        else -> Color.Transparent
    }
    Box(
        modifier
            .size(8.dp)
            .background(fill, CircleShape)
            .then(if (stage == WordStage.Unseen) Modifier.border(1.dp, Theme.colors.line, CircleShape) else Modifier)
    )
}

/** The three bars that dance while Read along plays. Still bars when idle. */
@Composable
fun PlayingBars(active: Boolean, modifier: Modifier = Modifier, color: Color = Theme.colors.accent) {
    val transition = rememberInfiniteTransition(label = "bars")
    val phase by transition.animateFloat(
        0f,
        1f,
        infiniteRepeatable(tween(BARS_MILLIS), RepeatMode.Reverse),
        label = "phase"
    )
    val still = floatArrayOf(0.5f, 0.9f, 0.65f)
    val lo = floatArrayOf(0.4f, 1.0f, 0.55f)
    val hi = floatArrayOf(1.0f, 0.45f, 0.8f)
    Row(
        modifier.height(scaledSize(BARS_SP)).width(scaledSize(BARS_SP)),
        horizontalArrangement = Arrangement.spacedBy(2.5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        for (i in 0..2) {
            val scale = if (active) lo[i] + (hi[i] - lo[i]) * phase else still[i]
            Box(
                Modifier
                    .width(3.dp)
                    .fillMaxHeight()
                    .graphicsLayer { scaleY = scale }
                    .background(color, Theme.rounded(2.dp))
            )
        }
    }
}

private const val BARS_MILLIS = 480
private const val BARS_SP = 20

/** A selectable pill. Selection is an accent border, never a fill (the house rule). */
@Composable
fun SegmentChip(text: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val shape = Theme.rounded(Theme.Radius.inset)
    Box(
        modifier
            .heightIn(min = 44.dp)
            .background(Theme.colors.surface, shape)
            .border(if (selected) 2.dp else 1.dp, if (selected) Theme.colors.accent else Theme.colors.line, shape)
            .clickable(role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text,
            style = Theme.text.subheadline.copy(fontWeight = FontWeight.Medium),
            color = Theme.colors.ink,
            textAlign = TextAlign.Center
        )
    }
}

/** The Ordered / Random control the two deck modes share. [event] is the per-screen analytics name. */
@Composable
fun OrderPicker(ordered: Boolean, onChange: (Boolean) -> Unit, event: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        SegmentChip(stringResource(R.string.ordered), ordered, {
            if (!ordered) {
                onChange(true)
                Track.event(event, mapOf("ordered" to true))
            }
        }, Modifier.weight(1f))
        SegmentChip(stringResource(R.string.random), !ordered, {
            if (ordered) {
                onChange(false)
                Track.event(event, mapOf("ordered" to false))
            }
        }, Modifier.weight(1f))
    }
}

/** The end-of-deck panel: "All done!", one line of summary and a Restart button. */
@Composable
fun DeckDonePanel(summary: String, onRestart: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        SymbolIcon(R.drawable.ic_check_circle, Theme.colors.accent, DONE_ICON_SP)
        Text(
            stringResource(R.string.all_done),
            style = Theme.title(Theme.text.largeTitle, FontWeight.Bold),
            color = Theme.colors.ink,
            modifier = Modifier.padding(top = 16.dp)
        )
        Text(summary, style = Theme.text.body, color = Theme.colors.inkSecondary, textAlign = TextAlign.Center)
        Row(
            Modifier
                .padding(top = 24.dp)
                .heightIn(min = 54.dp)
                .background(Theme.colors.ink, Theme.rounded(Theme.Radius.pill))
                .clickable(role = Role.Button, onClick = onRestart)
                .padding(horizontal = 24.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            SymbolIcon(R.drawable.ic_refresh, Theme.colors.canvas, Theme.text.headline.fontSize.value.toInt())
            Text(
                stringResource(R.string.restart),
                style = Theme.title(Theme.text.headline),
                color = Theme.colors.canvas
            )
        }
    }
}

private const val DONE_ICON_SP = 72

// endregion

// region Word faces

/**
 * An example sentence as aligned columns: reading over kanji over romaji, one column per phrase, wrapping
 * like text (port of `ExampleSentenceView`). The reading is centred over the kanji core, not the phrase.
 */
@Composable
fun ExampleSentenceView(
    example: ExampleSentence,
    modifier: Modifier = Modifier,
    translation: String? = null,
    translationStyle: TextStyle = Theme.text.footnote,
    columnSizeSp: Int = 14
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            // Columns of a line start at the same top, so every reading row and kanji row lines up.
            itemVerticalAlignment = Alignment.Top
        ) {
            for (i in example.kanji.indices) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    val readingSize = (columnSizeSp * READING_RATIO).toInt().sp
                    val a = example.annotated(i)
                    if (a != null) {
                        Row(verticalAlignment = Alignment.Bottom) {
                            // Hidden twins of the prefix and suffix push the reading to the core's span.
                            if (a.prefix.isNotEmpty()) HiddenSpan(a.prefix, columnSizeSp)
                            Text(a.reading, style = Theme.jp(readingSize), color = Theme.colors.inkSecondary)
                            if (a.suffix.isNotEmpty()) HiddenSpan(a.suffix, columnSizeSp)
                        }
                    } else {
                        Text(" ", style = Theme.jp(readingSize))
                    }
                    Text(example.kanji[i], style = Theme.jp(columnSizeSp.sp), color = Theme.colors.ink)
                    if (example.romaji.indices.contains(i)) {
                        Text(
                            example.romaji[i],
                            style = if (columnSizeSp >= 16) Theme.text.caption else Theme.text.caption2,
                            color = Theme.colors.inkTertiary
                        )
                    }
                }
            }
        }
        if (translation != null) {
            Text(translation, style = translationStyle, color = Theme.colors.inkSecondary)
        }
    }
}

private const val READING_RATIO = 0.64f

/**
 * A phrase segment that takes its rendered *width* and nothing else (port of iOS `hiddenSpan`: `.frame(height: 0).hidden()`):
 * the ruler that puts a reading over its kanji core. Zero height and never drawn or placed, so the main-line font does not
 * inflate the small furigana row, every phrase's reading row is exactly one reading line, and the Japanese lines share a
 * baseline whether or not a phrase has furigana.
 */
@Composable
private fun HiddenSpan(text: String, sizeSp: Int) {
    Text(
        text,
        style = Theme.jp(sizeSp.sp),
        softWrap = false,
        maxLines = 1,
        modifier = Modifier
            .clearAndSetSemantics { }
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity))
                layout(placeable.width, 0) { }
            }
    )
}

/**
 * The toggle-driven word face both browse decks show as their card front: the same `Pref` keys as
 * Today, so "what the front shows" is one choice made once. Reading small above the written form.
 */
@Composable
fun VocabFront(vocab: Vocab, container: AppContainer, modifier: Modifier = Modifier) {
    val showKanji = rememberPref(Pref.kanjiShown, container).value
    val showKana = rememberPref(Pref.kanaShown, container).value
    val showRomaji = rememberPref(Pref.romajiShown, container).value
    val showTranslation = rememberPref(Pref.translationShown, container).value
    val hero = if (vocab.displaysKanji && showKanji) vocab.kanji else vocab.kana
    // The hero's size follows the word's length: poster type for two kana, a step down for a compound.
    val heroSize = when {
        hero.length <= 3 -> 62
        hero.length <= 6 -> 50
        hero.length <= 9 -> 40
        else -> 32
    }
    Column(
        modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(9.dp)
    ) {
        if (vocab.displaysKanji && showKanji) {
            if (showKana) {
                Text(
                    vocab.kana,
                    style = Theme.jp(maxOf(13, (heroSize * 0.3).toInt()).sp),
                    color = Theme.colors.inkSecondary
                )
            }
            Text(vocab.kanji, style = Theme.jp(heroSize.sp), color = Theme.colors.ink, textAlign = TextAlign.Center)
        } else if (showKana) {
            Text(vocab.kana, style = Theme.jp(heroSize.sp), color = Theme.colors.ink, textAlign = TextAlign.Center)
        }
        if (showRomaji) {
            Text(vocab.romaji, style = Theme.text.footnote, color = Theme.colors.inkSecondary)
        }
        if (showTranslation) {
            Box(Modifier.width(34.dp).height(1.dp).background(Theme.colors.line))
            Text(
                vocab.translation,
                style = Theme.title(Theme.text.title3),
                color = Theme.colors.accent,
                textAlign = TextAlign.Center
            )
            val note = vocab.dictionary
            if (!note.isNullOrEmpty()) {
                Text(note, style = Theme.text.caption, color = Theme.colors.inkSecondary, textAlign = TextAlign.Center)
            }
        }
    }
}

/**
 * The details face: Practice's reveal and the Flashcards back. A dictionary entry, not a poster:
 * left-aligned headword with its reading and romaji, the meaning and usage note, and the example in a
 * canvas inset pane (the biggest thing on the face, because flipping means "help me understand this").
 */
@Composable
fun VocabFace(vocab: Vocab, onSpeakExample: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
                Text(
                    if (vocab.displaysKanji) vocab.kanji else vocab.kana,
                    style = Theme.jp(30.sp),
                    color = Theme.colors.ink
                )
                if (vocab.displaysKanji) {
                    Text(vocab.kana, style = Theme.jp(15.sp), color = Theme.colors.inkSecondary)
                }
            }
            if (vocab.romaji.isNotEmpty()) {
                Text(vocab.romaji, style = Theme.text.caption2, color = Theme.colors.inkTertiary)
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(vocab.translation, style = Theme.title(Theme.text.title3), color = Theme.colors.accent)
            val note = vocab.dictionary
            if (!note.isNullOrEmpty()) {
                Text(note, style = Theme.text.caption, color = Theme.colors.inkSecondary)
            }
        }
        val example = vocab.example
        if (example != null) {
            ExampleSentenceView(
                example,
                Modifier
                    .fillMaxWidth()
                    .background(Theme.colors.canvas, Theme.rounded(Theme.Radius.chip))
                    .clickable(role = Role.Button, onClick = onSpeakExample)
                    .padding(12.dp),
                translation = vocab.exampleTranslation,
                translationStyle = Theme.text.subheadline,
                columnSizeSp = 21
            )
        }
    }
}

/** The ★ / ★2 control: one tap cycles none, 1, 2, 3, none. One glyph plus a numeral: fixed width at every tier. */
@Composable
fun BookmarkStars(vocab: Vocab, tiers: Map<String, Int>, container: AppContainer, modifier: Modifier = Modifier) {
    val stars = tiers[vocab.id]
    val scope = rememberCoroutineScope()
    val description = stringResource(R.string.bookmark)
    Row(
        modifier
            .widthIn(min = 48.dp)
            .heightIn(min = 40.dp)
            .clickable(role = Role.Button) {
                val next = Bookmark.next(stars)
                scope.launch { container.progress.setBookmark(next, vocab) }
                Track.event(TrackEvents.BOOKMARK, mapOf("lesson" to vocab.lesson, "stars" to (next ?: 0)))
            }
            .semantics { contentDescription = description },
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        SymbolIcon(
            if (stars == null) R.drawable.ic_star_outline else R.drawable.ic_star,
            if (stars == null) Theme.colors.inkTertiary else Theme.colors.accent,
            Theme.text.callout.fontSize.value.toInt()
        )
        if (stars != null) {
            Text(
                stars.toString(),
                style = Theme.text.caption2.copy(fontWeight = FontWeight.SemiBold),
                color = Theme.colors.accent
            )
        }
    }
}

/**
 * One vocabulary row (Vocab List, search results, Bookmarks): kana and kanji, the meaning under the word,
 * a speaker and the star. Tapping the text or the speaker speaks the word.
 */
@Composable
fun VocabRow(
    vocab: Vocab,
    container: AppContainer,
    tiers: Map<String, Int>,
    surface: String,
    modifier: Modifier = Modifier,
    showLesson: Boolean = false,
    showExample: Boolean = false,
    stage: WordStage? = null
) {
    val pronouncer = com.kfpun.japanesedaily.audio.LocalPronouncer.current
    val speak = {
        pronouncer.speak(vocab)
        Track.event(TrackEvents.PLAY_VOCAB, mapOf("lesson" to vocab.lesson, "surface" to surface))
    }
    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier.weight(1f).clickable(role = Role.Button) { speak() },
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (stage != null) StageDot(stage)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
                    Text(vocab.kana, style = Theme.jp(Theme.text.headline), color = Theme.colors.ink)
                    if (vocab.displaysKanji) {
                        Text(vocab.kanji, style = Theme.jp(Theme.text.subheadline), color = Theme.colors.inkSecondary)
                    }
                }
            }
            Box(
                Modifier.size(width = 48.dp, height = 40.dp).clickable(role = Role.Button) { speak() },
                contentAlignment = Alignment.Center
            ) {
                SymbolIcon(R.drawable.ic_volume_up, Theme.colors.accent, Theme.text.body.fontSize.value.toInt())
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier.weight(1f).padding(start = if (stage != null) 18.dp else 0.dp).clickable { speak() },
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    vocab.translation,
                    style = Theme.text.subheadline,
                    color = Theme.colors.accent,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (showLesson) {
                    Text("L${vocab.lesson}", style = Theme.text.caption2, color = Theme.colors.inkTertiary)
                }
            }
            BookmarkStars(vocab, tiers, container, Modifier.width(48.dp))
        }
        val example = vocab.example
        if (showExample && example != null) {
            ExampleSentenceView(
                example,
                Modifier
                    .padding(top = 6.dp)
                    .fillMaxWidth()
                    .background(Theme.colors.canvas, Theme.rounded(Theme.Radius.inset))
                    .clickable(role = Role.Button) {
                        pronouncer.speakExample(vocab)
                        Track.event(
                            TrackEvents.PLAY_EXAMPLE,
                            mapOf("lesson" to vocab.lesson, "surface" to "vocab_list")
                        )
                    }
                    .padding(10.dp),
                translation = vocab.exampleTranslation,
                translationStyle = Theme.text.caption
            )
        }
    }
}

// endregion

/** The shared sound toggle (`ui/components`) bound to the one global `soundOn` preference. */
@Composable
fun LessonSoundToggle(container: AppContainer) {
    val sound = rememberPref(Pref.soundOn, container)
    SoundToggle(sound.value, {
        sound.set(!sound.value)
        Track.event(TrackEvents.TOGGLE_SOUND, mapOf("on" to !sound.value))
    })
}

/**
 * The "Show" toolbar menu that drives [VocabFront]'s toggles: the same `Pref` keys as Learn's option bar and
 * the same `toggle_field` event, so no surface can disagree about what a card shows.
 */
@Composable
fun CardShowMenu(container: AppContainer, sound: Boolean = true) {
    var open by remember { mutableStateOf(false) }
    val kana = rememberPref(Pref.kanaShown, container)
    val kanji = rememberPref(Pref.kanjiShown, container)
    val romaji = rememberPref(Pref.romajiShown, container)
    val meaning = rememberPref(Pref.translationShown, container)
    val soundOn = rememberPref(Pref.soundOn, container)
    Box {
        ToolbarButton(R.drawable.ic_visibility, stringResource(R.string.show), { open = true })
        DropdownMenu(open, { open = false }, containerColor = Theme.colors.surface) {
            Text(
                stringResource(R.string.shown_on_the_card),
                style = Theme.text.caption,
                color = Theme.colors.inkSecondary,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
            )
            ShowItem(stringResource(R.string.kana), "kana", kana)
            ShowItem(stringResource(R.string.kanji), "kanji", kanji)
            ShowItem(stringResource(R.string.romaji), "romaji", romaji)
            ShowItem(stringResource(R.string.meaning_19cd7d1), "meaning", meaning)
            if (sound) ShowItem(stringResource(R.string.read_automatically), "sound", soundOn)
        }
    }
}

@Composable
private fun ShowItem(title: String, name: String, pref: PrefValue<Boolean>) {
    DropdownMenuItem(
        text = { Text(title, style = Theme.text.body, color = Theme.colors.ink) },
        leadingIcon = {
            if (pref.value) SymbolIcon(R.drawable.ic_check, Theme.colors.accent, Theme.text.body.fontSize.value.toInt())
        },
        onClick = {
            pref.set(!pref.value)
            Track.event(TrackEvents.TOGGLE_FIELD, mapOf("field" to name, "shown" to !pref.value))
        }
    )
}
