package com.kfpun.japanesedaily.intro

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.kfpun.japanesedaily.data.prefs.Pref
import com.kfpun.japanesedaily.data.prefs.Prefs
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.VocabStore
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Port of the iOS `IntroTests` (nihongoTests.swift). Unit tests run from android/app. */
@OptIn(ExperimentalCoroutinesApi::class)
class IntroTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun TestScope.newPrefs() = Prefs(
        PreferenceDataStoreFactory.create(scope = CoroutineScope(UnconfinedTestDispatcher(testScheduler))) {
            File(tmp.root, "prefs.preferences_pb")
        }
    )

    @Test
    fun cardsAreNumberedInPagingOrder() {
        assertEquals(listOf(1, 2, 3, 4, 5, 6), Intro.Card.entries.map { it.number })
        assertEquals(
            listOf(
                Intro.Card.MEANINGS,
                Intro.Card.KANA,
                Intro.Card.MODES,
                Intro.Card.CHALLENGE,
                Intro.Card.TODAY,
                Intro.Card.REMINDERS
            ),
            Intro.Card.entries
        )
        // The ask goes last, after the tour has shown what there is to come back to.
        assertEquals(Intro.Card.REMINDERS, Intro.Card.entries.last())
    }

    @Test
    fun onlyNoKanaDivertsTheLandingTab() {
        assertEquals(Intro.Tab.KANA, Intro.landingTab(Intro.KanaLevel.NOT_YET))
        assertEquals(Intro.Tab.TODAY, Intro.landingTab(Intro.KanaLevel.HIRAGANA))
        assertEquals(Intro.Tab.TODAY, Intro.landingTab(Intro.KanaLevel.BOTH))
        assertEquals(Intro.Tab.TODAY, Intro.landingTab(null))
        // The raw values are the stored/reported wire format, not display text.
        assertEquals(listOf("none", "hiragana", "both"), Intro.KanaLevel.entries.map { it.id })
        assertEquals(listOf("travel", "jlpt", "work", "culture", "other"), Intro.Goal.entries.map { it.id })
    }

    @Test
    fun answersMapOntoPreferences() = runTest {
        val prefs = newPrefs()
        IntroAnswers(Intro.KanaLevel.BOTH, 12, Intro.Goal.JLPT).save(prefs)
        assertTrue(prefs.get(Pref.introAnswered))
        assertEquals("both", prefs.get(Pref.knowsKana))
        assertEquals(12, prefs.get(Pref.textbookLesson))
        assertEquals("jlpt", prefs.get(Pref.goal))
    }

    /** "Never studied it" is the answer 0, not the absence of one: it must be written, so it is `isSet`. */
    @Test
    fun startingFreshIsStoredAsZero() = runTest {
        val prefs = newPrefs()
        assertFalse(prefs.isSet(Pref.textbookLesson))
        IntroAnswers(textbookLesson = 0).save(prefs)
        assertTrue(prefs.isSet(Pref.textbookLesson))
        assertEquals(0, prefs.get(Pref.textbookLesson))
    }

    /** A skipped question writes nothing, but the intro is still marked seen or the tour reopens. */
    @Test
    fun skippedQuestionsWriteNothingButStillCloseTheIntro() = runTest {
        val prefs = newPrefs()
        IntroAnswers().save(prefs)
        assertTrue(prefs.get(Pref.introAnswered))
        assertFalse(prefs.isSet(Pref.knowsKana))
        assertFalse(prefs.isSet(Pref.textbookLesson))
        assertFalse(prefs.isSet(Pref.goal))
    }

    @Test
    fun trackParamsAlwaysCarryTheSameThreeKeys() {
        val empty = IntroAnswers().trackParams
        assertEquals(setOf("knows_kana", "textbook_lesson", "goal"), empty.keys)
        assertEquals(IntroAnswers.UNANSWERED, empty["knows_kana"])
        assertEquals(IntroAnswers.UNANSWERED, empty["goal"])
        assertEquals(IntroAnswers.UNANSWERED_LESSON, empty["textbook_lesson"])

        val full = IntroAnswers(Intro.KanaLevel.HIRAGANA, 0, Intro.Goal.TRAVEL)
        assertEquals(empty.keys, full.trackParams.keys)
        assertEquals("hiragana", full.trackParams["knows_kana"])
        assertEquals(0, full.trackParams["textbook_lesson"])
        assertEquals("travel", full.trackParams["goal"])
        assertTrue(full.isComplete)
        assertFalse(IntroAnswers(Intro.KanaLevel.HIRAGANA, goal = Intro.Goal.TRAVEL).isComplete)
    }

    /** Only a fully answered run is submitted, with this run's answers. */
    @Test
    fun onlyACompleteRunMakesASurveyRow() {
        assertNull(IntroAnswers(Intro.KanaLevel.BOTH, 3).submission)
        val row = IntroAnswers(Intro.KanaLevel.NOT_YET, 0, Intro.Goal.WORK).submission
        assertNotNull(row)
        assertEquals("none", row!!.knowsKana)
        assertEquals(0, row.textbookLesson)
        assertEquals("work", row.goal)
    }

    /** Card 3's chips are the lesson screen's rows: order, titles and subtitles (IntroTests.modeChipsReuseSelectModeStrings). */
    @Test
    fun modeChipsReuseSelectModeStrings() {
        assertEquals(
            listOf(
                Intro.Mode.VOCAB_LIST,
                Intro.Mode.FLASHCARDS,
                Intro.Mode.PRACTICE,
                Intro.Mode.MATCH,
                Intro.Mode.LEARN
            ),
            Intro.Mode.entries
        )
        assertEquals(
            listOf("Vocab List", "Flashcards", "Practice", "Match", "Learn"),
            Intro.Mode.entries.map { it.titleKey }
        )
        assertEquals(
            listOf(
                "Browse & hear all words",
                "Swipe through the words",
                "Cards first, then a quick quiz",
                "Pair each word with its meaning",
                "Rebuild the reading from tiles"
            ),
            Intro.Mode.entries.map { it.subtitleKey }
        )
    }

    /** Every string the intro asks for has an English entry in UIStrings.json (all 19 languages are checked by StringResourcesTest). */
    @Test
    fun introStringsHaveEnglishEntries() {
        val text = File("../../nihongo/UIStrings.json").readText()
        val keys = Intro.Mode.entries.flatMap { listOf(it.titleKey, it.subtitleKey) } +
            Intro.KanaLevel.entries.map { it.titleKey } + Intro.Goal.entries.map { it.titleKey }
        keys.forEach { assertTrue("missing UIStrings key: $keys", text.contains("\"${jsonEscape(it)}\"")) }
    }

    private fun jsonEscape(s: String) = s.replace("\\", "\\\\").replace("\"", "\\\"")

    /** Card 1 skips わたし (kana only) for the first entry with a distinct kanji; lesson 1 comes from the data. */
    @Test
    fun samplesComeFromLessonOneOfTheBundledData() {
        val samples = IntroSamples.from(VocabStore(FileAssetSource(File("../../nihongo/Resources"))), "en")
        assertTrue(samples.lesson1.size > 10)
        assertEquals("わたし", samples.lesson1.first().kana)
        assertFalse(samples.lesson1.first().displaysKanji)
        assertTrue(samples.anatomyWord!!.displaysKanji)
        assertTrue(samples.anatomyWord!!.translation.isNotEmpty())
        assertEquals(50, samples.lessonCount)
        assertTrue("en" in samples.languages && samples.languages.size >= 19)
    }
}
