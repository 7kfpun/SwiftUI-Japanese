package com.kfpun.japanesedaily.audio

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R

/** One credit line a third-party licence requires to be visible in the app. */
data class Credit(val line: String, val voice: String)

/**
 * Licences the app must show. VOICEVOX is free for commercial use, but each character needs its
 * credit line visible wherever the audio plays (minna submodule, `generate-audio/SKILL.md`,
 * "Licensing"). [voice] is the generator's voice name, so the pairing with the bundled clips is
 * checkable. Settings (FOX-159) links to [LicensesScreen].
 */
object Licenses {
    val voicevox = listOf(
        Credit(line = "VOICEVOX:WhiteCUL", voice = "whitecul"),
        Credit(line = "VOICEVOX:剣崎雌雄", voice = "kenzaki")
    )
}

/** The Licenses page body: a heading, one line on where the audio comes from, then every credit. */
@Composable
fun LicensesScreen(modifier: Modifier = Modifier) {
    Column(
        modifier.verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp)
    ) {
        Text(stringResource(R.string.licenses), style = MaterialTheme.typography.headlineSmall)
        Text(
            stringResource(R.string.the_spoken_audio_in_this_app_is_synthesised_with_voicevox),
            style = MaterialTheme.typography.bodyLarge
        )
        Licenses.voicevox.forEach { Text(it.line, style = MaterialTheme.typography.titleMedium) }
    }
}
