package com.kfpun.japanesedaily.billing

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.data.Course
import com.kfpun.japanesedaily.ui.Theme
import com.kfpun.japanesedaily.ui.components.PrimaryPillButton
import com.kfpun.japanesedaily.ui.components.SymbolIcon
import com.kfpun.japanesedaily.ui.components.accentPlate
import com.kfpun.japanesedaily.ui.components.cardChrome
import com.kfpun.japanesedaily.ui.components.selectionBorder

/**
 * Shows the paywall for the controller's current request, over whatever is on screen, and closes it
 * the moment Pro turns on (iOS dismisses on `isPremium`). Compose it once, at the root.
 */
@Composable
fun PaywallHost(controller: PaywallController, pro: ProRepository) {
    val request by controller.request.collectAsStateWithLifecycle()
    val entitlement by pro.entitlement.collectAsStateWithLifecycle()
    val current = request ?: return
    LaunchedEffect(entitlement) { if (entitlement == Entitlement.PRO) controller.close() }
    PaywallScreen(pro, current, onClose = controller::close)
}

@Composable
fun PaywallScreen(pro: ProRepository, request: PaywallRequest, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val model = remember(request) { PaywallModel(pro, scope, request) }
    val state by model.state.collectAsStateWithLifecycle()
    var legal by remember { mutableStateOf<LegalDoc?>(null) }
    val activity = LocalContext.current.findActivity()

    LaunchedEffect(model) {
        model.shown()
        model.load()
    }
    // On disappear, not on the Cancel button: back, a tap outside and buying are all exits too.
    DisposableEffect(model) { onDispose { model.dismissed() } }

    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(Theme.colors.canvas).statusBarsPadding()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    stringResource(R.string.premium),
                    style = Theme.text.headline,
                    color = Theme.colors.ink,
                    modifier = Modifier.padding(start = 8.dp)
                )
                TextButton(onClick = onClose) { Text(stringResource(R.string.cancel), color = Theme.colors.accent) }
            }
            Column(
                Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                Header()
                EarnLine()
                Features()
                when {
                    state.isLoading || !state.didAttempt -> CircularProgressIndicator(color = Theme.colors.accent)
                    state.unavailable -> Unavailable(model)
                    else -> Plans(model, state, pro, activity)
                }
                state.message?.let { Message(it) }
                TextButton(onClick = model::restore) {
                    Text(stringResource(R.string.restore_purchases), style = Theme.text.footnote)
                }
                Text(
                    stringResource(R.string.subscriptions_renew_automatically_unless_canceled_at_ebd80c9),
                    style = Theme.text.caption2,
                    color = Theme.colors.inkSecondary,
                    textAlign = TextAlign.Center
                )
                Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    LegalLink(R.string.terms_of_use) { legal = LegalDoc.Terms }
                    LegalLink(R.string.privacy_policy) { legal = LegalDoc.Privacy }
                }
            }
        }
    }
    legal?.let { LegalDialog(it) { legal = null } }
}

@Composable
private fun LegalLink(@StringRes label: Int, onClick: () -> Unit) {
    Text(
        stringResource(label),
        style = Theme.text.caption2,
        color = Theme.colors.accent,
        modifier = Modifier.clickable(role = Role.Button, onClick = onClick).padding(vertical = 8.dp)
    )
}

@Composable
private fun Header() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SymbolIcon(R.drawable.ic_crown, Theme.colors.accent, sizeSp = 44)
        Text(
            stringResource(R.string.unlock_all_lessons),
            style = Theme.text.title,
            color = Theme.colors.ink,
            textAlign = TextAlign.Center
        )
        // Interpolated from the course rather than written out, so the offer on screen can't drift
        // from the rule the app enforces.
        Text(
            stringResource(
                R.string.free_through_lesson_arg_unlock_the_rest_and_remove_ads,
                Course.current.freeLessonLimit
            ),
            style = Theme.text.subheadline,
            color = Theme.colors.inkSecondary,
            textAlign = TextAlign.Center
        )
    }
}

/** The other way through, on the screen that asks for money: it makes the paywall feel like a choice. */
@Composable
private fun EarnLine() {
    val course = Course.current
    val band = course.groups.firstOrNull() ?: return
    Row(
        Modifier.fillMaxWidth().accentPlate(Theme.Radius.row, Theme.colors.streak).padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SymbolIcon(R.drawable.ic_star_circle, Theme.colors.streak, sizeSp = 20)
        Text(
            stringResource(
                R.string.or_earn_it_three_star_every_challenge_in_lessons_1_a_9356737,
                course.freeLessonLimit,
                stringResource(groupName(band.name))
            ),
            style = Theme.text.footnote,
            color = Theme.colors.ink
        )
    }
}

@StringRes
private fun groupName(key: String): Int = when (key) {
    "Beginning 1" -> R.string.beginning_1
    "Beginning 2" -> R.string.beginning_2
    "Advanced 1" -> R.string.advanced_1
    else -> R.string.advanced_2
}

@Composable
private fun Features() {
    val lessons = Course.current.lessonCount
    Column(
        Modifier.fillMaxWidth().cardChrome().padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Counts come from Course, never written out: the iOS paywall once promised 50 lessons of a
        // 201-lesson course on the screen that asks for money.
        Feature(stringResource(R.string.all_arg_lessons_unlocked, lessons))
        Feature(stringResource(R.string.every_challenge_from_lesson_1_to_arg, lessons))
        Feature(stringResource(R.string.no_ads_ever))
        Feature(stringResource(R.string.practice_flashcards_match_learn_and_the_full_ladder))
        Feature(stringResource(R.string.audio_in_every_practice_and_learning_task_to_help_it_stick))
        Feature(stringResource(R.string.study_offline_anywhere))
    }
}

@Composable
private fun Feature(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        // Accent, not green: green is an answer verdict, and this list is a promise.
        SymbolIcon(R.drawable.ic_check_circle, Theme.colors.accent, sizeSp = 20)
        Text(text, style = Theme.text.subheadline, color = Theme.colors.ink, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun Unavailable(model: PaywallModel) {
    LaunchedEffect(model) { model.unavailableShown() }
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            stringResource(R.string.plans_couldn_t_load_check_your_connection_and_try_again),
            style = Theme.text.subheadline,
            color = Theme.colors.inkSecondary,
            textAlign = TextAlign.Center
        )
        OutlinedButton(onClick = model::retry) { Text(stringResource(R.string.try_again), color = Theme.colors.accent) }
    }
}

@Composable
private fun Plans(model: PaywallModel, state: PaywallState, pro: ProRepository, activity: Activity?) {
    val best = PaywallPricing.bestValue(state.offers)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        state.subscriptions.forEach { offer ->
            SubscriptionRow(offer, state, isBest = offer.plan == best?.plan, onSelect = { model.select(offer.plan) })
        }
    }
    state.lifetime?.let { offer ->
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                HorizontalDivider(Modifier.weight(1f), color = Theme.colors.line)
                Text(stringResource(R.string.or), style = Theme.text.caption, color = Theme.colors.inkSecondary)
                HorizontalDivider(Modifier.weight(1f), color = Theme.colors.line)
            }
            LifetimeRow(offer, state, onSelect = { model.select(offer.plan) })
        }
    }
    PrimaryPillButton(
        onClick = {
            val launcher = activity?.let(pro::launcher) ?: return@PrimaryPillButton
            model.purchase(launcher)
        },
        modifier = Modifier.padding(top = 4.dp)
    ) {
        if (state.isPurchasing) {
            CircularProgressIndicator(color = Theme.colors.canvas, modifier = Modifier.width(24.dp))
        } else {
            Text(stringResource(R.string.s_continue), style = Theme.text.headline)
        }
    }
}

/** The radio and the border are the selection, never a fill. */
@Composable
private fun PlanChrome(
    selected: Boolean,
    enabled: Boolean,
    onSelect: () -> Unit,
    content: @Composable RowScope.() -> Unit
) {
    val shape = Theme.rounded(Theme.Radius.row)
    Row(
        Modifier
            .fillMaxWidth()
            .background(Theme.colors.surface, shape)
            .border(1.dp, Theme.colors.line, shape)
            .selectionBorder(selected, Theme.Radius.row)
            .clickable(enabled = enabled, role = Role.RadioButton, onClick = onSelect)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SymbolIcon(
            if (selected) R.drawable.ic_check_circle else R.drawable.ic_circle_outline,
            if (selected) Theme.colors.accent else Theme.colors.inkSecondary,
            sizeSp = 22
        )
        content()
    }
}

@Composable
private fun SubscriptionRow(offer: PlanOffer, state: PaywallState, isBest: Boolean, onSelect: () -> Unit) {
    PlanChrome(offer.plan == state.selected, !state.isPurchasing, onSelect) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.SpaceBetween) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(periodLabel(offer.plan), style = Theme.text.headline, color = Theme.colors.ink)
                    if (isBest) {
                        Box(
                            Modifier
                                .background(Theme.colors.accent, Theme.rounded(Theme.Radius.pill))
                                .padding(horizontal = 7.dp, vertical = 3.dp)
                        ) {
                            Text(
                                stringResource(R.string.best_value),
                                style = Theme.text.caption2,
                                color = Theme.colors.onAccent
                            )
                        }
                    }
                }
                PaywallPricing.savingsPercent(offer, state.offers)?.let {
                    Text(
                        stringResource(R.string.save_arg_pct, it),
                        style = Theme.text.caption,
                        color = Theme.colors.accent
                    )
                }
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(offer.formattedPrice, style = Theme.text.headline, color = Theme.colors.accent)
                if (offer.plan.months > 1) {
                    PaywallPricing.perMonthDisplay(offer)?.let {
                        Text(
                            stringResource(R.string.arg_month, it),
                            style = Theme.text.caption,
                            color = Theme.colors.inkSecondary
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LifetimeRow(offer: PlanOffer, state: PaywallState, onSelect: () -> Unit) {
    PlanChrome(offer.plan == state.selected, !state.isPurchasing, onSelect) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.SpaceBetween) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(stringResource(R.string.lifetime), style = Theme.text.headline, color = Theme.colors.ink)
                Text(
                    stringResource(R.string.pay_once_yours_forever),
                    style = Theme.text.caption,
                    color = Theme.colors.inkSecondary
                )
            }
            Text(offer.formattedPrice, style = Theme.text.headline, color = Theme.colors.accent)
        }
    }
}

/** Plan names come from the app's own strings, never from Play (see [PaywallPricing]). */
@Composable
private fun periodLabel(plan: ProPlan): String = when (plan.months) {
    0 -> stringResource(R.string.lifetime)
    1 -> stringResource(R.string.s_1_month)
    else -> stringResource(R.string.arg_months, plan.months)
}

@Composable
private fun Message(message: PaywallMessage) {
    val text = when (message) {
        PaywallMessage.PENDING -> R.string.your_payment_is_pending_premium_turns_on_once_it_completes
        PaywallMessage.FAILED -> R.string.the_purchase_didn_t_go_through_please_try_again
        PaywallMessage.NOTHING_FOUND -> R.string.no_purchases_found_for_this_google_account
    }
    Text(
        stringResource(text),
        style = Theme.text.footnote,
        color = Theme.colors.inkSecondary,
        textAlign = TextAlign.Center
    )
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
