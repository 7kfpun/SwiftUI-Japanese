package com.kfpun.japanesedaily.settings

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.analytics.AnalyticsExclusionFooter
import com.kfpun.japanesedaily.analytics.PaywallSource
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.analytics.TrackEvents
import com.kfpun.japanesedaily.analytics.TrackScreens
import com.kfpun.japanesedaily.audio.LicensesScreen
import com.kfpun.japanesedaily.data.AppContainer
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.feedback.Feedback
import com.kfpun.japanesedaily.feedback.FeedbackDialog
import com.kfpun.japanesedaily.intro.IntroChip
import com.kfpun.japanesedaily.intro.IntroLauncher
import com.kfpun.japanesedaily.locale.AppLanguage
import com.kfpun.japanesedaily.locale.AppLocale
import com.kfpun.japanesedaily.rating.PlayReview
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.cardChrome
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The same URLs iOS links; hosted on Firebase Hosting (`web/privacy.html`, `web/terms.html`). */
object LegalLinks {
    const val PRIVACY = "https://kf-nihongo.web.app/privacy.html"
    const val TERMS = "https://kf-nihongo.web.app/terms.html"
}

/** The Settings tab (port of `SettingsView.swift`), with Licenses pushed over it and Feedback above it. */
@Composable
fun SettingsTab(modifier: Modifier = Modifier) {
    var licenses by rememberSaveable { mutableStateOf(false) }
    var feedback by rememberSaveable { mutableStateOf(false) }
    BackHandler(licenses) { licenses = false }
    if (licenses) {
        LicensesPage(modifier) { licenses = false }
    } else {
        SettingsList(modifier, onLicenses = { licenses = true }, onFeedback = { feedback = true })
    }
    if (feedback) FeedbackDialog(Feedback.Source.Settings, onClose = { feedback = false })
}

@Composable
private fun LicensesPage(modifier: Modifier, onBack: () -> Unit) {
    LaunchedEffect(Unit) { Track.screen(TrackScreens.LEGAL, mapOf("doc" to "licenses")) }
    Column(modifier.fillMaxSize().background(Theme.colors.canvas).statusBarsPadding()) {
        IconButton(onClick = onBack) {
            Icon(painterResource(R.drawable.ic_arrow_back), contentDescription = stringResource(R.string.done))
        }
        LicensesScreen(Modifier.weight(1f))
    }
}

@Composable
private fun SettingsList(modifier: Modifier, onLicenses: () -> Unit, onFeedback: () -> Unit) {
    val context = LocalContext.current
    val container = remember { AppContainer.from(context) }
    val pro by container.pro.state.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { Track.screen(TrackScreens.SETTINGS) }

    Column(
        modifier
            .fillMaxSize()
            .background(Theme.colors.canvas)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Text(
            stringResource(R.string.settings),
            style = Theme.title(Theme.text.largeTitle, androidx.compose.ui.text.font.FontWeight.Bold),
            color = Theme.colors.ink,
            modifier = Modifier.padding(horizontal = 4.dp)
        )
        PremiumSection(container, pro)
        InterfaceSection(container)
        MeaningsSection(container)
        DisplaySection(context)
        RemindersSection(container)
        FeedbackSection(onFeedback)
        LegalSection(pro, onLicenses)
        // The version line and the hidden developer gestures: seven taps toggle the analytics opt-out, a long
        // press replays the intro. One line, no visible affordance.
        AnalyticsExclusionFooter(
            Modifier.fillMaxWidth().padding(bottom = 16.dp),
            onLongPress = { IntroLauncher.replay() }
        )
    }
}

@Composable
private fun PremiumSection(container: AppContainer, pro: ProState) {
    val context = LocalContext.current
    SettingsGroup(header = stringResource(R.string.premium)) {
        if (pro.isPremium) {
            SettingsRow(stringResource(R.string.premium_active), value = null)
            if (pro.canManageSubscription) {
                RowDivider()
                SettingsRow(stringResource(R.string.manage_subscription), onClick = {
                    Track.event(TrackEvents.MANAGE_SUBSCRIPTION)
                    container.pro.manageSubscription(context)
                })
            }
        } else {
            // The ink card the lesson screen's hero uses: the one offer on this screen.
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(Theme.colors.ink, Theme.rounded(Theme.Radius.card))
                    .clickable(role = Role.Button) { container.pro.openPaywall(PaywallSource.SETTINGS) }
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    stringResource(R.string.unlock_all_lessons),
                    style = Theme.title(Theme.text.headline),
                    color = Theme.colors.canvas
                )
                Text(
                    stringResource(R.string.no_ads_ever),
                    style = Theme.text.footnote,
                    color = Theme.colors.canvas.copy(alpha = INK_CARD_SECONDARY_ALPHA)
                )
            }
        }
    }
    if (!pro.isPremium) {
        SettingsGroup {
            SettingsRow(stringResource(R.string.restore_purchases), onClick = { container.pro.restore("settings") })
        }
    }
}

private const val INK_CARD_SECONDARY_ALPHA = 0.7f

@Composable
private fun InterfaceSection(container: AppContainer) {
    val context = LocalContext.current
    var picking by remember { mutableStateOf(false) }
    // What the app shows now: the choice, else the phone's language if the app has it, else English.
    val current = AppLocale.chosen(context)
        ?: AppLanguage.fromLocaleTag(Locale.getDefault().toLanguageTag())
        ?: AppLanguage.ENGLISH
    SettingsGroup(
        header = stringResource(R.string.s_interface),
        footer = { FooterText(stringResource(R.string.the_language_used_for_the_app_s_own_text_tabs_buttons_labels)) }
    ) {
        SettingsRow(stringResource(R.string.app_language), value = nativeName(current.localeTag)) { picking = true }
    }
    if (picking) {
        ChoiceDialog(
            title = stringResource(R.string.app_language),
            options = AppLanguage.entries,
            selected = current,
            label = { nativeName(it.localeTag) },
            onDismiss = { picking = false }
        ) {
            picking = false
            if (it != current) {
                Track.event(TrackEvents.SET_APP_LANGUAGE, mapOf("code" to it.id))
                // Saves, applies and recreates the activity in the new language.
                AppLocale.set(context, it)
            }
        }
    }
}

@Composable
private fun MeaningsSection(container: AppContainer) {
    val scope = rememberCoroutineScope()
    var picking by remember { mutableStateOf(false) }
    val vocab = container.vocab
    // The language list and the device default come from the decoded course data: read off the main thread.
    val languages by produceState<Pair<List<String>, String>?>(null) {
        value = withContext(Dispatchers.IO) { vocab.availableLanguages to vocab.deviceDefaultLanguage() }
    }
    val (available, fallback) = languages ?: (emptyList<String>() to "en")
    val current by container.prefs.translationLanguage(fallback).collectAsStateWithLifecycle(fallback)
    SettingsGroup(
        header = stringResource(R.string.meanings),
        footer = { FooterText(stringResource(R.string.the_language_japanese_words_are_translated_into_voca_feff1b1)) }
    ) {
        SettingsRow(stringResource(R.string.vocabulary_language), value = nativeName(current)) {
            if (available.isNotEmpty()) picking = true
        }
    }
    if (picking) {
        ChoiceDialog(
            title = stringResource(R.string.vocabulary_language),
            options = available,
            selected = current,
            label = { nativeName(it) },
            onDismiss = { picking = false }
        ) {
            picking = false
            if (it != current) {
                Track.event(TrackEvents.SET_VOCAB_LANGUAGE, mapOf("code" to it))
                scope.launch { container.prefs.setTranslationLanguage(it) }
            }
        }
    }
}

@Composable
private fun DisplaySection(context: Context) {
    var appearance by remember { mutableStateOf(Appearance.chosen(context)) }
    var percent by remember { mutableIntStateOf(TextSize.percent(context)) }
    SettingsGroup(header = stringResource(R.string.appearance)) {
        SettingsChoiceRow(
            title = stringResource(R.string.appearance),
            options = Appearance.entries,
            selected = appearance,
            label = {
                stringResource(
                    when (it) {
                        Appearance.System -> R.string.system
                        Appearance.Light -> R.string.light
                        Appearance.Dark -> R.string.dark
                    }
                )
            },
            onSelect = {
                appearance = it
                // Recreates the activity in the new night mode (AppCompat).
                Appearance.set(context, it)
            }
        )
        RowDivider()
        SettingsChoiceRow(
            title = stringResource(R.string.text_size),
            options = TextSize.steps,
            selected = percent,
            label = { "$it%" },
            onSelect = {
                percent = it
                TextSize.set(context, it)
            }
        )
    }
}

@Composable
private fun RemindersSection(container: AppContainer) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val prefs = container.prefs
    val on by prefs.flow(Pref.streakReminderOn).collectAsStateWithLifecycle(false)
    val storedHour by prefs.flow(Pref.streakReminderHour).collectAsStateWithLifecycle(Pref.DEFAULT_REMINDER_HOUR)
    val hour = StreakReminder.resolvedHour(storedHour)
    var confirmOff by remember { mutableStateOf(false) }
    var pickingHour by remember { mutableStateOf(false) }
    var refused by remember { mutableStateOf(false) }
    // Re-read when coming back from system settings: the answer may have changed there.
    var enabled by remember { mutableStateOf(NotificationOptIn.enabled(context)) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { enabled = NotificationOptIn.enabled(context) }
    // On with nothing able to fire is the state the footer must own up to, as iOS does.
    val blocked = refused || (on && !enabled)

    val optIn = rememberReminderOptIn { granted ->
        refused = !granted
        enabled = NotificationOptIn.enabled(context)
    }

    SettingsGroup(
        header = stringResource(R.string.reminders),
        footer = {
            if (blocked) {
                FooterText(
                    stringResource(R.string.notifications_are_turned_off_for_this_app_in_system_settings),
                    Modifier.clickable {
                        runCatching { context.startActivity(NotificationOptIn.systemSettingsIntent(context)) }
                    }
                )
            } else {
                FooterText(stringResource(R.string.a_nudge_on_any_day_you_haven_t_studied_yet_nothing_i_af38cc6))
            }
        }
    ) {
        SettingsSwitchRow(stringResource(R.string.daily_reminder), checked = on, onToggle = {
            // Permission is requested here, on an explicit "yes, remind me", and nowhere else. A refusal
            // leaves the switch off rather than on over a reminder that can never fire.
            if (on) confirmOff = true else optIn()
        })
        if (on) {
            RowDivider()
            SettingsRow(stringResource(R.string.reminder_time), value = hourLabel(context, hour)) { pickingHour = true }
        }
    }

    if (confirmOff) {
        // Turning it off asks first: switching it off is usually a reaction to one badly timed alert, and the
        // thing worth saying (it stays quiet on days you have studied) is what that person does not know yet.
        AlertDialog(
            onDismissRequest = { confirmOff = false },
            title = { Text(stringResource(R.string.turn_off_the_daily_reminder)) },
            text = { Text(stringResource(R.string.most_people_who_lose_a_streak_simply_forgot_the_remi_d65b7b7)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmOff = false
                    scope.launch {
                        prefs.set(Pref.streakReminderOn, false)
                        Reminders.engine(context).reschedule()
                        Track.event(TrackEvents.STREAK_REMINDER, mapOf("on" to false, "hour" to hour))
                    }
                }) { Text(stringResource(R.string.turn_off)) }
            },
            dismissButton = {
                TextButton(onClick = {
                    confirmOff = false
                    Track.event(TrackEvents.STREAK_REMINDER_KEPT)
                }) { Text(stringResource(R.string.keep_it_on)) }
            }
        )
    }
    if (pickingHour) {
        ChoiceDialog(
            title = stringResource(R.string.reminder_time),
            options = StreakReminder.hours.toList(),
            selected = hour,
            label = { hourLabel(context, it) },
            onDismiss = { pickingHour = false }
        ) {
            pickingHour = false
            if (it != hour) {
                scope.launch {
                    prefs.set(Pref.streakReminderHour, it)
                    Reminders.engine(context).reschedule()
                    Track.event(TrackEvents.STREAK_REMINDER_HOUR, mapOf("hour" to it))
                }
            }
        }
    }
}

@Composable
private fun FeedbackSection(onFeedback: () -> Unit) {
    val context = LocalContext.current
    SettingsGroup(
        header = stringResource(R.string.feedback),
        footer = { FooterText(stringResource(R.string.something_wrong_or_missing_feel_free_to_reach_out)) }
    ) {
        SettingsRow(stringResource(R.string.send_feedback), onClick = onFeedback)
        RowDivider()
        // The store page is reachable from here whatever the star row was answered: this is not a rating gate.
        SettingsRow(stringResource(R.string.rate_the_app), onClick = { PlayReview.openStorePage(context) })
    }
}

@Composable
private fun LegalSection(pro: ProState, onLicenses: () -> Unit) {
    val context = LocalContext.current
    val container = remember { AppContainer.from(context) }
    SettingsGroup(header = stringResource(R.string.legal)) {
        if (pro.privacyOptionsRequired) {
            SettingsRow(stringResource(R.string.privacy_options), onClick = {
                context.findActivity()?.let { container.pro.showPrivacyOptions(it) }
            })
            RowDivider()
        }
        SettingsRow(stringResource(R.string.privacy_policy), onClick = {
            openUrl(context, LegalLinks.PRIVACY, "privacy")
        })
        RowDivider()
        SettingsRow(stringResource(R.string.terms_of_use), onClick = { openUrl(context, LegalLinks.TERMS, "terms") })
        RowDivider()
        SettingsRow(stringResource(R.string.licenses), onClick = onLicenses)
    }
}

internal fun openUrl(context: Context, url: String, doc: String) {
    Track.screen(TrackScreens.LEGAL, mapOf("doc" to doc))
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        // No browser installed: nothing to open, and nothing worth a dialog.
    }
}

/** A language's own name for itself, capitalised: "Deutsch", "中文 (繁體)". */
internal fun nativeName(tag: String): String =
    Locale.forLanguageTag(tag).let { it.getDisplayName(it) }.replaceFirstChar { it.uppercase() }

/** The hour as the learner's locale writes it ("8:00 PM" or "20:00"), not a bare number. */
internal fun hourLabel(context: Context, hour: Int): String = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
    .withLocale(AppLocale.locale(context))
    .format(LocalTime.of(hour, 0))

/** A pick-one dialog: stacked chips, the chosen one with the accent border. Tapping one picks and closes. */
@Composable
private fun <T> ChoiceDialog(
    title: String,
    options: List<T>,
    selected: T,
    label: @Composable (T) -> String,
    onDismiss: () -> Unit,
    onPick: (T) -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                options.forEach { IntroChip(label(it), it == selected) { onPick(it) } }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } }
    )
}
