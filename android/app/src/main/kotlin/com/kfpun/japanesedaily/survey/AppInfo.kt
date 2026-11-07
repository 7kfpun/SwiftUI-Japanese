package com.kfpun.japanesedaily.survey

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import com.kfpun.japanesedaily.BuildConfig
import com.kfpun.japanesedaily.analytics.Track
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.prefs.Prefs
import com.kfpun.japanesedaily.intro.IntroAnswers
import com.kfpun.japanesedaily.locale.AppLocale
import kotlinx.coroutines.flow.first

/**
 * Build, OS and device strings for [Survey.Context]: characteristics only, never an identity.
 * Model, OS release, language and region are the same for every unit of a model; nothing here reads
 * Settings.Secure.ANDROID_ID, an advertising id or anything minted by the app.
 */
object AppInfo {
    /** e.g. `"1.0.0 (1)"`: version name plus code, since a bug report is about a build. */
    val version: String get() = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

    /** e.g. `"Android 16"`. */
    val os: String get() = "Android ${Build.VERSION.RELEASE}"

    /** The marketing model name (`Build.MODEL`), e.g. `"Pixel 8"`. */
    val device: String get() = Build.MODEL ?: "unknown"

    /** The phone's own preferred language (not the in-app choice), e.g. `"en-GB"`. */
    val osLanguage: String
        get() = Resources.getSystem().configuration.locales.takeIf { !it.isEmpty }?.get(0)?.toLanguageTag()
            ?: "unknown"

    /** The device region, e.g. `"GB"`: a formatting characteristic, not a location. */
    val region: String
        get() = Resources.getSystem().configuration.locales.takeIf { !it.isEmpty }?.get(0)?.country
            ?.takeIf { it.isNotEmpty() } ?: "unknown"

    /**
     * The font scale as iOS's Dynamic Type short names (`XS`..`XXXL`, `AX1`..`AX5`), so the two
     * platforms' rows group together. The default scale 1.0 is `L`, as on iOS.
     */
    fun textSize(fontScale: Float): String = when {
        fontScale < 0.8f -> "XS"
        fontScale < 0.9f -> "S"
        fontScale < 0.95f -> "M"
        fontScale < 1.1f -> "L"
        fontScale < 1.25f -> "XL"
        fontScale < 1.4f -> "XXL"
        fontScale < 1.6f -> "XXXL"
        fontScale < 1.75f -> "AX1"
        fontScale < 1.9f -> "AX2"
        fontScale < 2.0f -> "AX3"
        fontScale < 2.2f -> "AX4"
        else -> "AX5"
    }

    /** `"light"` or `"dark"`, nothing else. */
    fun appearance(configuration: Configuration): String =
        if (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES) {
            "dark"
        } else {
            "light"
        }

    /**
     * The context a submission is built from, read at submit time so it reports a setting the sender
     * may have changed seconds ago. [vocabFallback] is the device-default meaning language for an unset
     * choice. Premium and the two progress counts come from the billing and progress layers (FOX-158,
     * the screens that submit ratings and feedback); the intro runs before either has anything to say,
     * so they are passed in and default to the free, nothing-done values.
     */
    suspend fun surveyContext(
        context: Context,
        prefs: Prefs,
        vocabFallback: String,
        isPremium: Boolean = false,
        tier: String = "none",
        challengesPassed: Int = 0,
        kanaAnswered: Int = 0
    ): Survey.Context {
        val configuration = context.resources.configuration
        val knows = prefs.get(Pref.knowsKana)
        val goal = prefs.get(Pref.goal)
        val shown = listOf(
            "kanji" to Pref.kanjiShown,
            "kana" to Pref.kanaShown,
            "romaji" to Pref.romajiShown,
            "translation" to Pref.translationShown
        ).filter { prefs.get(it.second) }.joinToString(",") { it.first }
        return Survey.Context(
            appVersion = version,
            os = os,
            device = device,
            osLanguage = osLanguage,
            appLanguage = AppLocale.chosen(context)?.id ?: "en",
            vocabLanguage = prefs.translationLanguage(vocabFallback).first(),
            region = region,
            isPremium = isPremium,
            tier = tier,
            challengesPassed = challengesPassed,
            kanaAnswered = kanaAnswered,
            soundOn = prefs.get(Pref.soundOn),
            analyticsExcluded = Track.isExcluded,
            shownFields = shown,
            textSize = textSize(configuration.fontScale),
            appearance = appearance(configuration),
            lastScreen = Track.lastScreen,
            knowsKana = knows.ifEmpty { IntroAnswers.UNANSWERED },
            goal = goal.ifEmpty { IntroAnswers.UNANSWERED },
            textbookLesson = if (prefs.isSet(Pref.textbookLesson)) {
                prefs.get(Pref.textbookLesson)
            } else {
                IntroAnswers.UNANSWERED_LESSON
            },
            debug = BuildConfig.DEBUG
        )
    }
}
