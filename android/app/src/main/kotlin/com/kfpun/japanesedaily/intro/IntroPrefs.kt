package com.kfpun.japanesedaily.intro

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import com.kfpun.japanesedaily.locale.AppLocale

/**
 * The intro's flag and answers in the `settings` SharedPreferences file (the file [AppLocale] and
 * Track already use), under the iOS `Pref` key names. Device-only: the app has no backup. Once the
 * DataStore `Prefs` of FOX-148 lands, an [IntroStore] over it replaces this and the survey reads
 * through it; the keys do not change.
 */
class IntroPrefs(private val prefs: SharedPreferences) : IntroStore {
    constructor(context: Context) : this(context.getSharedPreferences(AppLocale.PREFS, Context.MODE_PRIVATE))

    override var introAnswered: Boolean
        get() = prefs.getBoolean(INTRO_ANSWERED, false)
        set(value) = prefs.edit { putBoolean(INTRO_ANSWERED, value) }

    override fun putKnowsKana(value: String) = prefs.edit { putString(KNOWS_KANA, value) }

    override fun putTextbookLesson(value: Int) = prefs.edit { putInt(TEXTBOOK_LESSON, value) }

    override fun putGoal(value: String) = prefs.edit { putString(GOAL, value) }

    val knowsKana: String? get() = prefs.getString(KNOWS_KANA, null)
    val goal: String? get() = prefs.getString(GOAL, null)
    val textbookLesson: Int? get() = if (prefs.contains(TEXTBOOK_LESSON)) prefs.getInt(TEXTBOOK_LESSON, 0) else null

    /** The meaning language, or null to follow the device (resolved by the caller). */
    var translationLanguage: String?
        get() = prefs.getString(TRANSLATION_LANGUAGE, null)
        set(value) = prefs.edit { putString(TRANSLATION_LANGUAGE, value) }

    val soundOn: Boolean get() = prefs.getBoolean("isSoundOn", true)
    val analyticsExcluded: Boolean get() = prefs.getBoolean("analyticsExcluded", false)

    /** Which of the four card fields are on, comma-joined in the card's own order. */
    val shownFields: String
        get() = listOf(
            "kanji" to "isKanjiShown",
            "kana" to "isKanaShown",
            "romaji" to "isRomajiShown",
            "translation" to "isTranslationShown"
        ).filter { prefs.getBoolean(it.second, true) }.joinToString(",") { it.first }

    companion object {
        const val INTRO_ANSWERED = "introAnswered"
        const val KNOWS_KANA = "knowsKana"
        const val TEXTBOOK_LESSON = "textbookLesson"
        const val GOAL = "goal"
        const val TRANSLATION_LANGUAGE = "translationLanguage"
    }
}
