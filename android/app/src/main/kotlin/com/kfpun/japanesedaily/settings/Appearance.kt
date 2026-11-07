package com.kfpun.japanesedaily.settings

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.runtime.mutableFloatStateOf
import androidx.core.content.edit

/**
 * Light, dark or follow the phone. Kept in plain SharedPreferences (the same `settings` file as
 * `AppLocale`) rather than DataStore because it must be applied in `Application.onCreate`, before any
 * activity exists and without waiting on a coroutine, or the first frame flashes the wrong theme.
 */
enum class Appearance(val id: String, val nightMode: Int) {
    System("system", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM),
    Light("light", AppCompatDelegate.MODE_NIGHT_NO),
    Dark("dark", AppCompatDelegate.MODE_NIGHT_YES);

    companion object {
        internal const val PREFS = "settings"
        internal const val KEY = "appearance"

        /** The stored choice; [System] for nothing or an unknown id. */
        fun fromId(id: String?): Appearance = entries.firstOrNull { it.id == id } ?: System

        fun chosen(context: Context): Appearance =
            fromId(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null))

        /** Applies the stored choice to the process. Call once from `Application.onCreate`. */
        fun apply(context: Context) = AppCompatDelegate.setDefaultNightMode(chosen(context).nightMode)

        /** Saves and applies [appearance]; open activities are recreated in it. */
        fun set(context: Context, appearance: Appearance) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit { putString(KEY, appearance.id) }
            AppCompatDelegate.setDefaultNightMode(appearance.nightMode)
        }
    }
}

/**
 * The app's own text scale, multiplied onto the phone's font scale. iOS follows Dynamic Type alone; on
 * Android the phone setting is buried, so Settings also offers four steps. The choice is a percentage so
 * the stored value reads as what it is.
 */
object TextSize {
    internal const val KEY = "textScalePercent"
    const val DEFAULT_PERCENT = 100

    /** The steps Settings offers, smallest first. */
    val steps = listOf(85, DEFAULT_PERCENT, 115, 130)

    /** The stored step; anything that is not one of [steps] reads as the default. */
    fun percent(context: Context): Int {
        val stored = context.getSharedPreferences(Appearance.PREFS, Context.MODE_PRIVATE)
            .getInt(KEY, DEFAULT_PERCENT)
        return if (stored in steps) stored else DEFAULT_PERCENT
    }

    /** The live multiplier the UI reads (a Compose state, so a change redraws at once, with no recreate). */
    private val live = mutableFloatStateOf(1f)

    val liveScale: Float get() = live.floatValue

    /** Reads the stored step into [liveScale]. Call once from `Application.onCreate`. */
    fun load(context: Context) {
        live.floatValue = scale(context)
    }

    fun set(context: Context, percent: Int) {
        val step = if (percent in steps) percent else DEFAULT_PERCENT
        context.getSharedPreferences(Appearance.PREFS, Context.MODE_PRIVATE).edit { putInt(KEY, step) }
        live.floatValue = step / 100f
    }

    /** The multiplier for the chosen step, e.g. 1.15. */
    fun scale(context: Context): Float = percent(context) / 100f
}
