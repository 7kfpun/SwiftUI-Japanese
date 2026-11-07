package com.kfpun.japanesedaily.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * The font-follows-script rule (07-ux-ui.md): every Japanese face also draws Latin, so romaji set
 * in one looks merely plain, never broken. The face therefore follows the *content's* script at
 * runtime, not the screen. These two enums own the switchable slots, as `KForm` and `VForm` do on iOS.
 */
enum class KanaForm {
    Hiragana,
    Katakana,
    Romaji;

    val isJapanese: Boolean get() = this != Romaji
}

enum class VocabForm {
    Kana,
    Kanji,
    Romaji,
    Translation;

    /** Kana and kanji are Japanese; romaji and a translation are Latin or UI-language prose. */
    val isJapanese: Boolean get() = this == Kana || this == Kanji
}

/** Which face a glyph slot asks for when its content is Japanese. */
enum class JapaneseFace { Regular, Bold, Strokes }

/** What a slot resolves to once the content's script is known. */
enum class ResolvedFace { Jp, JpBold, JpStrokes, Display }

/** Pure rule behind [glyphStyle]: Japanese content takes its Japanese face, anything else [ResolvedFace.Display]. */
fun resolveFace(isJapanese: Boolean, japanese: JapaneseFace): ResolvedFace = when {
    !isJapanese -> ResolvedFace.Display
    japanese == JapaneseFace.Bold -> ResolvedFace.JpBold
    japanese == JapaneseFace.Strokes -> ResolvedFace.JpStrokes
    else -> ResolvedFace.Jp
}

/**
 * Style for a script-switchable slot. [size] is the one size both halves share, so switching
 * script never resizes the card. A translation is prose in the UI language and does not come
 * through here: it takes a plain [Theme.text] style.
 */
@Composable
fun glyphStyle(
    isJapanese: Boolean,
    size: Int,
    japanese: JapaneseFace = JapaneseFace.Regular,
    latinWeight: FontWeight = FontWeight.Bold
): TextStyle {
    val sp = size.sp
    return when (resolveFace(isJapanese, japanese)) {
        ResolvedFace.Jp -> Theme.jp(sp)
        ResolvedFace.JpBold -> Theme.jpBold(sp)
        ResolvedFace.JpStrokes -> Theme.jpStrokes(sp)
        ResolvedFace.Display -> Theme.display(size, latinWeight)
    }
}
