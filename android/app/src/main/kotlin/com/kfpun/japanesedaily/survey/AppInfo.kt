package com.kfpun.japanesedaily.survey

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import com.kfpun.japanesedaily.BuildConfig
import com.kfpun.japanesedaily.intro.IntroAnswers
import com.kfpun.japanesedaily.intro.IntroPrefs
import com.kfpun.japanesedaily.locale.AppLocale

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
     * may have changed seconds ago. Premium, the two progress counts and the last screen come from
     * the data and analytics layers (FOX-148, FOX-158, FOX-160); until those are wired they report
     * the free, nothing-done defaults.
     */
    fun surveyContext(context: Context, lastScreen: String = ""): Survey.Context {
        val prefs = IntroPrefs(context)
        val configuration = context.resources.configuration
        return Survey.Context(
            appVersion = version,
            os = os,
            device = device,
            osLanguage = osLanguage,
            appLanguage = AppLocale.chosen(context)?.id ?: "en",
            vocabLanguage = prefs.translationLanguage ?: "en",
            region = region,
            soundOn = prefs.soundOn,
            analyticsExcluded = prefs.analyticsExcluded,
            shownFields = prefs.shownFields,
            textSize = textSize(configuration.fontScale),
            appearance = appearance(configuration),
            lastScreen = lastScreen,
            knowsKana = prefs.knowsKana ?: IntroAnswers.UNANSWERED,
            goal = prefs.goal ?: IntroAnswers.UNANSWERED,
            textbookLesson = prefs.textbookLesson ?: IntroAnswers.UNANSWERED_LESSON,
            debug = BuildConfig.DEBUG
        )
    }
}
