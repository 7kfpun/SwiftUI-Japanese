package com.kfpun.japanesedaily.audio

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.ui.Theme

/** One credit line a third-party licence requires to be visible in the app. */
data class Credit(val line: String, val voice: String)

/**
 * Licences the app must show. VOICEVOX is free for commercial use, but each character needs its
 * credit line visible wherever the audio plays (minna submodule, `generate-audio/SKILL.md`,
 * "Licensing"). [voice] is the generator's voice name, so the pairing with the bundled clips is
 * checkable. Settings (FOX-159) links to [LicensesScreen].
 */
object Licenses {
    /** A bundled font and where its licence text lives in the assets. */
    data class FontLicense(val name: String, val asset: String)

    /** Noto Serif JP (OFL, `assets/licenses`) and KanjiStrokeOrders (BSD, packaged from `nihongo/Fonts`). */
    val fonts = listOf(
        FontLicense("Noto Serif JP", "licenses/NotoSerifJP-OFL.txt"),
        FontLicense("KanjiStrokeOrders", "KanjiStrokeOrders-LICENSE.txt")
    )

    val voicevox = listOf(
        Credit(line = "VOICEVOX:WhiteCUL", voice = "whitecul"),
        Credit(line = "VOICEVOX:剣崎雌雄", voice = "kenzaki")
    )
}

/** The Licenses page body: a heading, one line on where the audio comes from, then every credit. */
@Composable
fun LicensesScreen(modifier: Modifier = Modifier) {
    Column(
        modifier.background(Theme.colors.canvas).verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            stringResource(R.string.licenses),
            style = Theme.title(Theme.text.title2),
            color = Theme.colors.ink
        )
        Text(
            stringResource(R.string.the_spoken_audio_in_this_app_is_synthesised_with_voicevox),
            style = Theme.text.body,
            color = Theme.colors.inkSecondary
        )
        Licenses.voicevox.forEach {
            Text(it.line, style = Theme.jp(Theme.text.headline), color = Theme.colors.ink)
        }
        // The bundled faces. Their licences ship in the APK (the BSD one requires it).
        val assets = LocalContext.current.assets
        Licenses.fonts.forEach { font ->
            val text = remember(font.asset) {
                runCatching { assets.open(font.asset).bufferedReader().use { it.readText() } }.getOrDefault("")
            }
            Text(font.name, style = Theme.title(Theme.text.headline), color = Theme.colors.ink)
            Text(text, style = Theme.text.footnote, color = Theme.colors.inkSecondary)
        }
    }
}
