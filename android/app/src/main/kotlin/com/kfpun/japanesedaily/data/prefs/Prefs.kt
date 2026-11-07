package com.kfpun.japanesedaily.data.prefs

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/** A typed preference with its default: the one registry, so a typo cannot make a second setting. */
class PrefKey<T : Any>(val key: Preferences.Key<T>, val default: T)

/** Central registry of preference keys (port of `Pref`). Stored names match the iOS keys. */
object Pref {
    val soundOn = PrefKey(booleanPreferencesKey("isSoundOn"), true)
    val ordered = PrefKey(booleanPreferencesKey("isOrdered"), true)
    val flashcardsOrdered = PrefKey(booleanPreferencesKey("flashcardsOrdered"), true)
    val kanjiShown = PrefKey(booleanPreferencesKey("isKanjiShown"), true)
    val kanaShown = PrefKey(booleanPreferencesKey("isKanaShown"), true)
    val romajiShown = PrefKey(booleanPreferencesKey("isRomajiShown"), true)
    val translationShown = PrefKey(booleanPreferencesKey("isTranslationShown"), true)

    /** Index into the kana browser's script table: 0 hiragana, 1 katakana, 2 romaji. */
    val kanaTileScript = PrefKey(intPreferencesKey("kanaTileScript"), 0)
    val examplesShown = PrefKey(booleanPreferencesKey("examplesShown"), false)

    /** Practice's quiz pair as `VForm.label` strings; empty reads as the default kana -> meaning. */
    val practiceFrom = PrefKey(stringPreferencesKey("practiceFrom"), "")
    val practiceTo = PrefKey(stringPreferencesKey("practiceTo"), "")
    val practiceMixed = PrefKey(booleanPreferencesKey("practiceMixed"), false)

    /** Read-along speed multiplier (0.8, 1.0, 1.2, 1.5). */
    val playbackRate = PrefKey(doublePreferencesKey("playbackRate"), 1.0)

    /** `"lesson/mode"` strings: which practice modes each lesson has opened. */
    val modeVisits = PrefKey(stringSetPreferencesKey("modeVisits"), emptySet())
    val analyticsExcluded = PrefKey(booleanPreferencesKey("analyticsExcluded"), false)

    /** Epoch millis; 0 means never. A timestamp so the ask can repeat. */
    val ratingAskedAt = PrefKey(longPreferencesKey("ratingAskedAt"), 0L)
    val shareAskedAt = PrefKey(longPreferencesKey("shareAskedAt"), 0L)
    val notificationAskedAt = PrefKey(longPreferencesKey("notificationAskedAt"), 0L)
    val streakReminderOn = PrefKey(booleanPreferencesKey("streakReminderOn"), false)
    const val DEFAULT_REMINDER_HOUR = 20
    val streakReminderHour = PrefKey(intPreferencesKey("streakReminderHour"), DEFAULT_REMINDER_HOUR)

    val introAnswered = PrefKey(booleanPreferencesKey("introAnswered"), false)

    /** "none" / "hiragana" / "both"; the only intro answer anything acts on. Empty until answered. */
    val knowsKana = PrefKey(stringPreferencesKey("knowsKana"), "")

    /** Recorded only (a later survey segments by it); nothing reads it to change behaviour. */
    val textbookLesson = PrefKey(intPreferencesKey("textbookLesson"), 0)
    val goal = PrefKey(stringPreferencesKey("goal"), "")

    // Nullable on purpose: unset means "follow the device", which is resolved by the caller.
    val appLanguage = stringPreferencesKey("appLanguage")
    val translationLanguage = stringPreferencesKey("translationLanguage")
}

/** Preferences over DataStore. Device-only: DataStore's file is excluded from every backup. */
class Prefs(private val store: DataStore<Preferences>) {
    fun <T : Any> flow(pref: PrefKey<T>): Flow<T> = store.data.map { it[pref.key] ?: pref.default }

    suspend fun <T : Any> get(pref: PrefKey<T>): T = flow(pref).first()

    suspend fun <T : Any> set(pref: PrefKey<T>, value: T) {
        store.edit { it[pref.key] = value }
    }

    /** The UI language the learner chose, or null to follow the device. */
    val appLanguage: Flow<String?> = store.data.map { it[Pref.appLanguage] }

    suspend fun setAppLanguage(code: String?) {
        store.edit { if (code == null) it.remove(Pref.appLanguage) else it[Pref.appLanguage] = code }
    }

    /** The meaning language; [fallback] (the device default, resolved by `VocabStore`) when unset. */
    fun translationLanguage(fallback: String): Flow<String> =
        store.data.map { it[Pref.translationLanguage] ?: fallback }

    suspend fun setTranslationLanguage(code: String) {
        store.edit { it[Pref.translationLanguage] = code }
    }

    // region Mode visits (port of `ModeVisits`)

    /** Marks that [mode] was opened in [lesson]; idempotent. */
    suspend fun markModeVisit(lesson: Int, mode: String) {
        store.edit { it[Pref.modeVisits.key] = (it[Pref.modeVisits.key] ?: emptySet()) + "$lesson/$mode" }
    }

    /** The modes [lesson] has visited, as bare mode keys. */
    suspend fun modeVisits(lesson: Int): Set<String> {
        val prefix = "$lesson/"
        return get(Pref.modeVisits).filter { it.startsWith(prefix) }.map { it.removePrefix(prefix) }.toSet()
    }

    // endregion
}
