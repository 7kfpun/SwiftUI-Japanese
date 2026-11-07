package com.kfpun.japanesedaily.intro

import androidx.annotation.StringRes
import com.kfpun.japanesedaily.R
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.prefs.Prefs
import com.kfpun.japanesedaily.survey.Survey

/**
 * The first-launch intro: six cards that show what the app does and ask the three questions worth
 * asking before anyone has used anything. Port of `nihongo/Intro/Intro.swift`; view-free on purpose,
 * so the answer-to-preference mapping and the landing-tab decision are testable on the JVM.
 */
object Intro {
    /**
     * The cards in paging order, shallow to deep. [number] is the 1-based card number that the
     * `intro_card` / `intro_skip` analytics events carry. `REMINDERS` is last on purpose: it is the
     * only card that asks for something rather than showing something.
     */
    enum class Card(val number: Int) {
        MEANINGS(1),
        KANA(2),
        MODES(3),
        CHALLENGE(4),
        TODAY(5),
        REMINDERS(6)
    }

    /**
     * How much kana the learner says they already read. [id] is the wire format of both the stored
     * preference and the survey field (`none`, not `not_yet`), so it must not be renamed.
     */
    enum class KanaLevel(val id: String, val titleKey: String, @StringRes val title: Int) {
        NOT_YET("none", "Not yet", R.string.not_yet),
        HIRAGANA("hiragana", "Hiragana only", R.string.hiragana_only),
        BOTH("both", "Both, comfortably", R.string.both_comfortably)
    }

    /** Why they are learning. Recorded only; nothing in the app reads it. */
    enum class Goal(val id: String, val titleKey: String, @StringRes val title: Int) {
        TRAVEL("travel", "Travel", R.string.travel),
        JLPT("jlpt", "JLPT", R.string.jlpt),
        WORK("work", "Work", R.string.work),
        CULTURE("culture", "Culture", R.string.culture),
        OTHER("other", "Other", R.string.other)
    }

    /**
     * The five ways through a lesson that card 3 previews, shallow to deep. Titles and subtitles are
     * the same strings the lesson screen's mode rows use, so the tour teaches the labels the learner
     * meets again a tap later; [titleKey] is the canonical English key `intro_mode_peek` reports.
     */
    enum class Mode(
        val id: String,
        val titleKey: String,
        val subtitleKey: String,
        @StringRes val title: Int,
        @StringRes val subtitle: Int
    ) {
        VOCAB_LIST(
            "vocabList",
            "Vocab List",
            "Browse & hear all words",
            R.string.vocab_list,
            R.string.browse_hear_all_words
        ),
        FLASHCARDS(
            "flashcards",
            "Flashcards",
            "Swipe through the words",
            R.string.flashcards,
            R.string.swipe_through_the_words
        ),
        PRACTICE(
            "practice",
            "Practice",
            "Cards first, then a quick quiz",
            R.string.practice,
            R.string.cards_first_then_a_quick_quiz
        ),
        MATCH(
            "match",
            "Match",
            "Pair each word with its meaning",
            R.string.match,
            R.string.pair_each_word_with_its_meaning
        ),
        LEARN(
            "learn",
            "Learn",
            "Rebuild the reading from tiles",
            R.string.learn,
            R.string.rebuild_the_reading_from_tiles
        )
    }

    /** The tabs the intro can land on (the app's tab enum arrives with the navigation ticket). */
    enum class Tab { TODAY, KANA }

    /**
     * Where "Start learning" lands. Someone who cannot read kana yet starts on Kana, the one part of
     * the app that is free in full; everyone else, and anyone who skipped the question, keeps Today.
     */
    fun landingTab(kana: KanaLevel?): Tab = if (kana == KanaLevel.NOT_YET) Tab.KANA else Tab.TODAY
}

/**
 * The three answers the intro collects, and the single place they get written. Each is nullable
 * because Skip sits on every card: an unanswered question writes no preference at all, rather than
 * persisting a guess made on the learner's behalf.
 */
data class IntroAnswers(
    val kana: Intro.KanaLevel? = null,
    /** 0 = never studied the textbook, 1..N = the lesson they say they reached. Recorded only. */
    val textbookLesson: Int? = null,
    val goal: Intro.Goal? = null
) {
    /** Whether the run answered everything, which is what a survey submission requires. */
    val isComplete: Boolean get() = kana != null && textbookLesson != null && goal != null

    /**
     * The survey row for a completed run, or null for a partial one: a half-answered row could not
     * be told from a deliberate "0" once it is in the collection. Drop-off is counted in Analytics.
     */
    val submission: Survey.Intro?
        get() {
            val kana = kana ?: return null
            val textbookLesson = textbookLesson ?: return null
            val goal = goal ?: return null
            return Survey.Intro(kana.id, textbookLesson, goal.id)
        }

    /**
     * Marks the intro seen and persists whatever was answered. The flag goes down even on a skip,
     * or asking again on the next launch would turn a first-run tour into a nag.
     */
    suspend fun save(to: Prefs) {
        to.set(Pref.introAnswered, true)
        kana?.let { to.set(Pref.knowsKana, it.id) }
        textbookLesson?.let { to.set(Pref.textbookLesson, it) }
        goal?.let { to.set(Pref.goal, it.id) }
    }

    /** Params for `intro_done`: always the same three keys, so a funnel can count "unanswered". */
    val trackParams: Map<String, Any>
        get() = mapOf(
            "knows_kana" to (kana?.id ?: UNANSWERED),
            "textbook_lesson" to (textbookLesson ?: UNANSWERED_LESSON),
            "goal" to (goal?.id ?: UNANSWERED)
        )

    companion object {
        const val UNANSWERED = "unanswered"
        const val UNANSWERED_LESSON = -1
    }
}
