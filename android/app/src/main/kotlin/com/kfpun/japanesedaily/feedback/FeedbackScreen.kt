package com.kfpun.japanesedaily.feedback

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.intro.IntroChip
import com.kfpun.japanesedaily.survey.Survey
import com.kfpun.japanesedaily.survey.surveyContext
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The feedback screen over everything (port of `FeedbackView.swift`), reached from Settings, from a low
 * star pick and from a word's flag. Writes one `japanese_survey_feedback` row through [Survey].
 */
@Composable
fun FeedbackDialog(source: Feedback.Source, onClose: () -> Unit, stars: Int = 0, item: Feedback.Item? = null) {
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
    ) {
        Box(Modifier.fillMaxSize().background(Theme.colors.canvas).statusBarsPadding().imePadding()) {
            FeedbackScreen(source, stars, item, onClose)
        }
    }
}

@Composable
private fun FeedbackScreen(source: Feedback.Source, stars: Int, item: Feedback.Item?, onClose: () -> Unit) {
    val context = LocalContext.current
    val container = remember { AppContainer.from(context) }
    val scope = rememberCoroutineScope()
    // Arriving from the flag: the bucket and the word are known, so the form opens with them filled in.
    var draft by rememberSaveable(stateSaver = FeedbackDraftSaver) {
        mutableStateOf(
            FeedbackDraft(
                kind = item?.let { Feedback.Kind.Content },
                item = item,
                stars = stars
            )
        )
    }
    var sent by remember { mutableStateOf(false) }
    val sentNow by rememberUpdatedState(sent)
    val latest by rememberUpdatedState(draft)
    val message = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        Track.event(TrackEvents.FEEDBACK_OPENED, mapOf("source" to source.wire))
        runCatching { message.requestFocus() }
    }
    // On dispose rather than on Cancel, so a back press counts as an abandon too: an open-to-send funnel
    // where one of the two ways out is invisible measures the wrong thing.
    DisposableEffect(Unit) {
        onDispose {
            if (sentNow) return@onDispose
            val d = latest
            val params = buildMap<String, Any> {
                put("source", source.wire)
                put("message_length", d.trimmedMessage.length)
                d.kind?.let { put("kind", it.wire) }
                d.area?.let { put("area", it.wire) }
                if (d.stars > 0) put("stars", d.stars)
            }
            Track.event(TrackEvents.FEEDBACK_DISMISSED, params)
        }
    }

    fun send() {
        val submission = draft.submission(source) ?: return
        sent = true
        scope.launch {
            Survey.submit(submission, container.surveyContext(context))
            Track.event(TrackEvents.FEEDBACK_SUBMITTED, draft.trackParams(source))
            // Long enough to read, short enough that nobody reaches for the close button.
            delay(CONFIRMATION_MILLIS)
            onClose()
        }
    }

    Column(Modifier.fillMaxSize()) {
        if (!sent) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = onClose) { Text(stringResource(R.string.cancel)) }
                Text(
                    stringResource(R.string.send_feedback),
                    modifier = Modifier.weight(1f),
                    style = Theme.title(Theme.text.headline),
                    color = Theme.colors.ink,
                    textAlign = TextAlign.Center
                )
                TextButton(onClick = ::send, enabled = draft.isValid) {
                    Text(stringResource(R.string.send), fontWeight = FontWeight.SemiBold)
                }
            }
            Form(draft, source, message) { draft = it }
        } else {
            Confirmation()
        }
    }
}

@Composable
private fun Form(
    draft: FeedbackDraft,
    source: Feedback.Source,
    message: FocusRequester,
    update: (FeedbackDraft) -> Unit
) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        // From the star row a rating already exists and is shown as a fact; anywhere else it is an invitation.
        if (source == Feedback.Source.Rating) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Stars(draft.stars, onPick = null)
                Text(
                    stringResource(R.string.your_rating_comes_with_this_message),
                    style = Theme.text.footnote,
                    color = Theme.colors.inkSecondary
                )
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Heading(stringResource(R.string.how_would_you_rate_it))
                Stars(draft.stars) { update(draft.copy(stars = it)) }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Heading(stringResource(R.string.what_s_this_about))
            Feedback.Kind.entries.forEach {
                IntroChip(stringResource(it.title), draft.kind == it) { update(draft.copy(kind = it)) }
            }
        }

        when (draft.kind) {
            Feedback.Kind.Bug -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Heading(stringResource(R.string.which_part_isn_t_working))
                Feedback.Area.entries.forEach {
                    IntroChip(stringResource(it.title), draft.area == it) { update(draft.copy(area = it)) }
                }
            }

            Feedback.Kind.Content -> ReportedItem(draft.item)

            else -> Unit
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Heading(stringResource(R.string.what_happened))
            Field(
                value = draft.message,
                hint = stringResource(R.string.the_more_detail_the_better_which_word_which_screen_w_29470b8),
                modifier = Modifier.focusRequester(message),
                minLines = 4,
                maxLines = 12
            ) { update(draft.copy(message = it)) }
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Heading(stringResource(R.string.email))
            Field(
                value = draft.email,
                hint = stringResource(R.string.you_example_com),
                keyboardType = KeyboardType.Email
            ) { update(draft.copy(email = it)) }
            Text(
                stringResource(R.string.optional_only_if_you_d_like_a_reply),
                style = Theme.text.footnote,
                color = Theme.colors.inkSecondary
            )
        }
    }
}

@Composable
private fun ReportedItem(item: Feedback.Item?) {
    if (item == null) {
        Text(
            stringResource(R.string.open_the_word_and_tap_the_flag_to_report_it_exactly),
            style = Theme.text.footnote,
            color = Theme.colors.inkSecondary
        )
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        // The identifier is what travels with the message, so it is what is shown.
        Text(
            item.romaji,
            style = Theme.title(Theme.text.headline),
            color = Theme.colors.ink,
            modifier = Modifier
                .fillMaxWidth()
                .background(Theme.colors.surface, Theme.rounded(Theme.Radius.row))
                .border(1.dp, Theme.colors.line, Theme.rounded(Theme.Radius.row))
                .padding(12.dp)
        )
        Text(
            stringResource(R.string.this_word_comes_with_your_message),
            style = Theme.text.footnote,
            color = Theme.colors.inkSecondary
        )
    }
}

@Composable
private fun Heading(text: String) = Text(text, style = Theme.title(Theme.text.headline), color = Theme.colors.ink)

/** A text box on a card, four lines tall at every text size (`minLines`, never a fixed height). */
@Composable
private fun Field(
    value: String,
    hint: String,
    modifier: Modifier = Modifier,
    minLines: Int = 1,
    maxLines: Int = 1,
    keyboardType: KeyboardType = KeyboardType.Text,
    onChange: (String) -> Unit
) {
    val shape = Theme.rounded(Theme.Radius.row)
    androidx.compose.foundation.text.BasicTextField(
        value = value,
        onValueChange = onChange,
        modifier = modifier
            .fillMaxWidth()
            .background(Theme.colors.surface, shape)
            .border(1.dp, Theme.colors.line, shape),
        textStyle = Theme.text.body.copy(color = Theme.colors.ink),
        cursorBrush = androidx.compose.ui.graphics.SolidColor(Theme.colors.accent),
        minLines = minLines,
        maxLines = maxLines,
        singleLine = maxLines == 1,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        decorationBox = { inner ->
            Box(Modifier.padding(12.dp)) {
                if (value.isEmpty()) Text(hint, style = Theme.text.body, color = Theme.colors.inkTertiary)
                inner()
            }
        }
    )
}

/** Five stars; [onPick] null shows them as a fact. Each target is 48 dp, the gaps between take taps too. */
@Composable
private fun Stars(stars: Int, onPick: ((Int) -> Unit)?) {
    Row {
        for (i in 1..5) {
            val label = stringResource(R.string.arg_stars, i.toString())
            Box(
                Modifier
                    .semantics { contentDescription = label }
                    .let { if (onPick != null) it.clickable { onPick(i) } else it }
                    .padding(8.dp)
            ) {
                SymbolIcon(
                    if (i <= stars) R.drawable.ic_star_filled else R.drawable.ic_star_outline,
                    if (i <= stars) Theme.colors.accent else Theme.colors.inkTertiary,
                    STAR_SP
                )
            }
        }
    }
}

@Composable
private fun Confirmation() {
    Column(
        Modifier.fillMaxSize().padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            stringResource(R.string.thanks_it_s_on_its_way),
            style = Theme.title(Theme.text.title2, FontWeight.Bold),
            color = Theme.colors.ink,
            textAlign = TextAlign.Center
        )
        Text(
            stringResource(R.string.we_read_every_one_of_these),
            style = Theme.text.subheadline,
            color = Theme.colors.inkSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}

private const val CONFIRMATION_MILLIS = 1400L
private const val STAR_SP = 24

/** Keeps a half-written report across rotation and a language change, which recreate the activity. */
private val FeedbackDraftSaver = listSaver<FeedbackDraft, Any>(
    save = {
        listOf(
            it.kind?.name.orEmpty(),
            it.area?.name.orEmpty(),
            it.item?.lesson ?: -1,
            it.item?.romaji.orEmpty(),
            it.message,
            it.email,
            it.stars
        )
    },
    restore = {
        val lesson = it[2] as Int
        FeedbackDraft(
            kind = Feedback.Kind.entries.firstOrNull { k -> k.name == it[0] },
            area = Feedback.Area.entries.firstOrNull { a -> a.name == it[1] },
            item = if (lesson >= 0) Feedback.Item(lesson, it[3] as String) else null,
            message = it[4] as String,
            email = it[5] as String,
            stars = it[6] as Int
        )
    }
)
