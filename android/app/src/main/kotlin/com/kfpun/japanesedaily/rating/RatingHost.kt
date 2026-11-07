package com.kfpun.japanesedaily.rating

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.feedback.Feedback
import com.kfpun.japanesedaily.feedback.FeedbackDialog
import com.kfpun.japanesedaily.survey.Survey
import com.kfpun.japanesedaily.survey.surveyContext
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Shows the star row when [RatingCoordinator] raises an offer, and routes the answer. Mounted once, over
 * the whole app, so it works whichever screen the passed rung ended on.
 *
 * Routing happens **after the row has gone**, not in the star tap, so the destination (the store listing or the
 * feedback screen) is never asked to appear over a sheet that is still animating away.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RatingHost() {
    val context = LocalContext.current
    val container = remember { AppContainer.from(context) }
    val offer by container.rating.offer.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var feedbackStars by remember { mutableIntStateOf(0) }

    offer?.let { current ->
        val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        var picked by remember { mutableIntStateOf(0) }
        var handled by remember { mutableStateOf(false) }

        // "Not now" and a swipe-away are the same non-answer: nothing follows, and it is counted as dismissed.
        fun dismissWithoutAnswer() {
            if (handled) return
            handled = true
            Track.event(TrackEvents.RATING_DISMISSED, mapOf("source" to "challenge"))
            container.rating.consume()
        }

        fun answer(stars: Int) {
            if (handled) return
            handled = true
            picked = stars
            scope.launch {
                // A beat on the filled star, so the tap registers as an answer rather than as closing something.
                delay(PICK_BEAT_MILLIS)
                sheet.hide()
                container.rating.consume()
                Track.event(
                    TrackEvents.RATING_GIVEN,
                    mapOf("stars" to stars, "passed_total" to current.passedTotal, "source" to "challenge")
                )
                // Every star tap writes a rating row before branching: the star row is the app's own survey.
                Survey.submit(Survey.Rating(stars), container.surveyContext(context))
                if (RatingPrompt.opensStorePage(stars)) {
                    // The listing, never Play In-App Review: Google forbids asking an opinion question
                    // before that card, and the star row is one. Same path as Settings -> Rate the app.
                    PlayReview.openStorePage(context, source = "rating")
                } else {
                    feedbackStars = stars
                }
            }
        }

        ModalBottomSheet(
            onDismissRequest = ::dismissWithoutAnswer,
            sheetState = sheet,
            containerColor = Theme.colors.surface
        ) {
            RatingRow(
                picked = picked,
                onStar = ::answer,
                onNotNow = {
                    scope.launch {
                        sheet.hide()
                        dismissWithoutAnswer()
                    }
                }
            )
        }
    }

    if (feedbackStars > 0) {
        FeedbackDialog(
            source = Feedback.Source.Rating,
            stars = feedbackStars,
            onClose = { feedbackStars = 0 }
        )
    }
}

private const val PICK_BEAT_MILLIS = 350L

/**
 * The star row itself. Deliberately not an `AlertDialog`, which cannot hold a tappable row: the rating is
 * chosen here, in the app's own question.
 */
@Composable
internal fun RatingRow(picked: Int, onStar: (Int) -> Unit, onNotNow: () -> Unit, scrollable: Boolean = true) {
    Column(
        Modifier
            .fillMaxWidth()
            .let { if (scrollable) it.verticalScroll(rememberScrollState()) else it }
            .navigationBarsPadding()
            .padding(horizontal = 28.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Text(
            stringResource(R.string.enjoying_arg, stringResource(R.string.app_name)),
            style = Theme.title(Theme.text.title2, androidx.compose.ui.text.font.FontWeight.Bold),
            color = Theme.colors.ink,
            textAlign = TextAlign.Center
        )
        Text(
            stringResource(R.string.tap_a_star_to_tell_us_how_it_s_going),
            style = Theme.text.subheadline,
            color = Theme.colors.inkSecondary,
            textAlign = TextAlign.Center
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (i in 1..5) {
                val label = stringResource(R.string.arg_stars, i.toString())
                SymbolIcon(
                    if (i <= picked) R.drawable.ic_star_filled else R.drawable.ic_star_outline,
                    if (i <= picked) Theme.colors.accent else Theme.colors.inkTertiary,
                    STAR_SP,
                    Modifier
                        .semantics { contentDescription = label }
                        .clickable { onStar(i) }
                        .padding(4.dp)
                )
            }
        }
        // Leaves the rating unanswered, which is how "no answer" is told apart from a low one.
        Text(
            stringResource(R.string.not_now),
            style = Theme.text.subheadline,
            color = Theme.colors.inkSecondary,
            modifier = Modifier
                .defaultMinSize(minWidth = 160.dp, minHeight = 48.dp)
                .clickable(onClick = onNotNow)
                .padding(vertical = 14.dp),
            textAlign = TextAlign.Center
        )
    }
}

private const val STAR_SP = 32
