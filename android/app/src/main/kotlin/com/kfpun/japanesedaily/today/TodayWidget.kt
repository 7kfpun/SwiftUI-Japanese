package com.kfpun.japanesedaily.today

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import com.kfpun.japanesedaily.MainActivity
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.locale.AppLocale
import com.kfpun.japanesedaily.ui.DarkThemeColors
import com.kfpun.japanesedaily.ui.LightThemeColors
import java.time.Instant

/**
 * The home-screen widget (iOS `TodayWidget`): today's word, the one the deck's hourly rotation says
 * ([TodayShared.rotationIndex], the same function the app uses), over the lesson and, when wide, a "Ready for Challenge
 * N?" capsule. Text is read through [AppLocale.localizedContext], because a widget has no activity and would otherwise
 * show the phone's language below Android 13. A tap anywhere opens the app on Today.
 *
 * Draws from the published snapshot (or the sample deck before the app ever published); [TodayWidgetWorker] redraws it
 * on the hour. Nothing is fetched, so nothing needs the network.
 */
class TodayWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Responsive(setOf(SMALL, WIDE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = TodayWidgetUpdater.read(context) ?: TodayShared.sampleSnapshot
        provideContent { TodayWidgetContent(context, snapshot, Instant.now()) }
    }

    @androidx.glance.ExperimentalGlanceApi
    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        // The picker shows the sample deck's third word (the iOS gallery's), in the app's language.
        provideContent { TodayWidgetContent(context, TodayShared.sampleSnapshot, PREVIEW_MOMENT, preview = true) }
    }

    companion object {
        val SMALL = DpSize(110.dp, 110.dp)
        val WIDE = DpSize(250.dp, 110.dp)

        /** An instant whose rotation index on the 7-word sample deck is 2 (がくせい). */
        private val PREVIEW_MOMENT: Instant = Instant.ofEpochSecond(2 * 3600L)
    }
}

class TodayWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodayWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        kotlinx.coroutines.runBlocking { TodayWidgetUpdater.syncSchedule(context) }
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        kotlinx.coroutines.runBlocking { TodayWidgetUpdater.syncSchedule(context) }
    }
}

/** The word to show now, with everything the widget text needs. Pure, so it is unit tested. */
data class TodayWidgetState(val word: TodayShared.Word, val lesson: Int, val challenge: Int?, val deckSize: Int) {
    companion object {
        fun of(snapshot: TodayShared.Snapshot, now: Instant): TodayWidgetState {
            val deck = snapshot.words.ifEmpty { TodayShared.sampleWords }
            val word = deck[TodayShared.rotationIndex(deck.size, at = now)]
            return TodayWidgetState(word, snapshot.lesson, snapshot.challenge, deck.size)
        }
    }
}

private val inkColor = ColorProvider(day = LightThemeColors.ink, night = DarkThemeColors.ink)
private val inkSecondary = ColorProvider(day = LightThemeColors.inkSecondary, night = DarkThemeColors.inkSecondary)
private val accentColor = ColorProvider(day = LightThemeColors.accent, night = DarkThemeColors.accent)
private val surfaceColor = ColorProvider(day = LightThemeColors.surface, night = DarkThemeColors.surface)
private val washColor = ColorProvider(
    day = LightThemeColors.wash(LightThemeColors.accent),
    night = DarkThemeColors.wash(DarkThemeColors.accent)
)

@Composable
private fun TodayWidgetContent(
    context: Context,
    snapshot: TodayShared.Snapshot,
    now: Instant,
    preview: Boolean = false
) {
    val text = AppLocale.localizedContext(context)
    val state = TodayWidgetState.of(snapshot, now)
    val wide = LocalSize.current.width >= TodayWidget.WIDE.width
    val lesson = text.getString(R.string.lesson_arg, state.lesson.toString())
    val challenge = state.challenge?.let { text.getString(R.string.ready_for_challenge_arg, it.toString()) }
    val label = buildString {
        append(text.getString(R.string.today)).append(": ").append(state.word.kana)
        append(", ").append(state.word.meaning).append(". ").append(lesson)
        if (wide && challenge != null) append(". ").append(challenge)
    }
    Box(
        GlanceModifier
            .fillMaxSize()
            .background(surfaceColor)
            .cornerRadius(20.dp)
            .padding(12.dp)
            .semantics { contentDescription = label }
            .clickable(actionStartActivity(openTodayIntent(context, state.lesson, preview))),
        contentAlignment = Alignment.Center
    ) {
        Column(GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(lesson, style = TextStyle(color = inkSecondary, fontSize = 11.sp), maxLines = 1)
                Spacer(GlanceModifier.defaultWeight())
                if (wide && challenge != null) {
                    Text(
                        challenge,
                        style = TextStyle(color = accentColor, fontSize = 11.sp, fontWeight = FontWeight.Medium),
                        maxLines = 1,
                        modifier = GlanceModifier.background(
                            washColor
                        ).cornerRadius(12.dp).padding(horizontal = 8.dp, vertical = 3.dp)
                    )
                }
            }
            Spacer(GlanceModifier.defaultWeight())
            Text(
                state.word.kana,
                style = TextStyle(
                    color = inkColor,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center
                ),
                maxLines = 1
            )
            if (state.word.romaji.isNotEmpty()) {
                Text(
                    state.word.romaji,
                    style = TextStyle(color = inkSecondary, fontSize = 12.sp, textAlign = TextAlign.Center),
                    maxLines = 1
                )
            }
            Text(
                state.word.meaning,
                style = TextStyle(color = accentColor, fontSize = 14.sp, textAlign = TextAlign.Center),
                maxLines = 2
            )
            Spacer(GlanceModifier.defaultWeight())
        }
    }
}

/** What a tap on the widget starts: the app on Today, counted as a `widget_open` by [MainActivity]. */
internal fun openTodayIntent(context: Context, lesson: Int, preview: Boolean = false): Intent =
    Intent(context, MainActivity::class.java)
        .setAction(MainActivity.ACTION_OPEN_TODAY)
        .putExtra(MainActivity.EXTRA_WIDGET_LESSON, if (preview) 0 else lesson)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
