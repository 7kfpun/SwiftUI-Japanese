package com.kfpun.japanesedaily.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * Colours and type for the whole app, the Android side of nihongo/Theme.swift. Call sites read
 * `MaterialTheme` (which this fills in) and never name a literal colour or font. The palette is
 * a placeholder until FOX-149 ports the design system: near-monochrome plus Minna's teal accent
 * (Shared/Course.swift), cards lighter than the screen in both appearances.
 */
private val AccentLight = Color(0xFF0FB0BF)
private val AccentDark = Color(0xFF40C7D6)

private val LightColors = lightColorScheme(
    primary = AccentLight,
    onPrimary = Color.White,
    background = Color(0xFFF2F2F7),
    surface = Color.White,
    surfaceContainer = Color.White
)

private val DarkColors = darkColorScheme(
    primary = AccentDark,
    onPrimary = Color.Black,
    background = Color.Black,
    surface = Color(0xFF1C1C1E),
    surfaceContainer = Color(0xFF1C1C1E)
)

@Composable
fun JapaneseDailyTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content
    )
}
