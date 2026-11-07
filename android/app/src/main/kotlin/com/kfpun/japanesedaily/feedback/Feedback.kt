package com.kfpun.japanesedaily.feedback

import androidx.annotation.StringRes
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.survey.Survey

/**
 * The in-app feedback survey: what can be reported, from where, and the one rule about when a report is
 * sendable (port of `nihongo/Feedback/Feedback.swift`). View-free so the wire values, the length caps and
 * the validity gate are testable without presenting a screen.
 */
object Feedback {
    /**
     * Where the screen was opened from: the same four values as iOS, because a row cannot be read without
     * knowing which population it came from. `settings` went looking for a way to write in, `rating` was
     * sent after a low star pick, `hidden` is the developer, `card` arrives knowing which word it is about.
     */
    enum class Source(val wire: String) {
        Settings("settings"),
        Rating("rating"),
        Hidden("hidden"),
        Card("card")
    }

    /** The first question. The wire value is the Directus `kind`. */
    enum class Kind(val wire: String, @StringRes val title: Int) {
        Bug("bug", R.string.something_s_broken),
        Idea("idea", R.string.an_idea),
        Content("content", R.string.a_wrong_word_meaning_or_sound),
        Other("other", R.string.something_else)
    }

    /**
     * The follow-up for a bug. iOS also has `watch`; Android has no Wear OS app (FOX-146), so the choice is
     * not offered, and the column simply never receives it from this platform.
     */
    enum class Area(val wire: String, @StringRes val title: Int) {
        Audio("audio", R.string.sound_and_pronunciation),
        Kana("kana", R.string.kana),
        Lesson("lesson", R.string.lessons),
        Challenge("challenge", R.string.challenge),
        Today("today", R.string.today_or_the_widget),
        Purchase("purchase", R.string.buying_or_unlocking),
        Other("other", R.string.another_part_of_the_app)
    }

    /** The word under report, from the flag on a card: lesson 0 is a kana. */
    data class Item(val lesson: Int, val romaji: String) {
        val id: String get() = "$lesson/$romaji"
    }

    const val MESSAGE_LIMIT = 2000
    const val EMAIL_LIMIT = 254
    const val ITEM_LIMIT = 60
}

/** What the screen has collected so far. */
data class FeedbackDraft(
    val kind: Feedback.Kind? = null,
    val area: Feedback.Area? = null,
    val item: Feedback.Item? = null,
    val message: String = "",
    val email: String = "",
    val stars: Int = 0
) {
    val trimmedMessage: String get() = message.trim()

    /** The message is the only required field: a kind, an area and an email are all optional. */
    val isValid: Boolean get() = trimmedMessage.isNotEmpty()

    /** Area travels only for a bug; picking one and then switching the kind must not leak it. */
    val submittedArea: String get() = if (kind == Feedback.Kind.Bug) area?.wire.orEmpty() else ""

    val submittedLesson: Int get() = if (kind == Feedback.Kind.Content) item?.lesson ?: 0 else 0

    val submittedItem: String
        get() = if (kind == Feedback.Kind.Content) item?.romaji.orEmpty().take(Feedback.ITEM_LIMIT) else ""

    private val trimmedEmail: String get() = email.trim()

    /** The row to send, or null while [isValid] is false. No kind chosen is [Feedback.Kind.Other]. */
    fun submission(source: Feedback.Source): Survey.Feedback? {
        if (!isValid) return null
        return Survey.Feedback(
            kind = (kind ?: Feedback.Kind.Other).wire,
            area = submittedArea,
            message = trimmedMessage.take(Feedback.MESSAGE_LIMIT),
            email = trimmedEmail.take(Feedback.EMAIL_LIMIT),
            source = source.wire,
            stars = stars,
            lesson = submittedLesson,
            item = submittedItem
        )
    }

    /** The `feedback_submitted` params: lengths and flags, never the message or the address. */
    fun trackParams(source: Feedback.Source): Map<String, Any> = mapOf(
        "source" to source.wire,
        "kind" to (kind ?: Feedback.Kind.Other).wire,
        "area" to submittedArea,
        "lesson" to submittedLesson,
        "has_item" to submittedItem.isNotEmpty(),
        "message_length" to trimmedMessage.length,
        "has_email" to trimmedEmail.isNotEmpty(),
        "stars" to stars
    )
}
