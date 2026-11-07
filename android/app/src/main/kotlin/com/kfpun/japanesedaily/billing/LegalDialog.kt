package com.kfpun.japanesedaily.billing

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.ui.Theme

/**
 * The bundled legal documents (iOS `LegalDoc`). The text is the same `.txt` file iOS ships, packaged
 * from `nihongo/Legal` in place; App Review required both on the paywall (the iOS 3.0.0 rejection).
 */
enum class LegalDoc(val asset: String, @StringRes val title: Int) {
    Terms("TermsOfUse.txt", R.string.terms_of_use),
    Privacy("PrivacyPolicy.txt", R.string.privacy_policy)
}

/** A full-screen, scrollable view of [doc], for the paywall (and Settings) to show. */
@Composable
fun LegalDialog(doc: LegalDoc, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val text = remember(doc) {
        runCatching { context.assets.open(doc.asset).bufferedReader().use { it.readText() } }.getOrDefault("")
    }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(Theme.colors.canvas).statusBarsPadding()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    stringResource(doc.title),
                    style = Theme.text.headline,
                    color = Theme.colors.ink,
                    modifier = Modifier.padding(start = 8.dp)
                )
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = Theme.colors.accent) }
            }
            Text(
                text,
                style = Theme.text.callout,
                color = Theme.colors.ink,
                modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp)
            )
        }
    }
}
