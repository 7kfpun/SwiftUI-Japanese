package com.kfpun.japanesedaily.feedback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of the iOS `FeedbackTests`: wire values, caps and the one validity rule. */
class FeedbackTest {
    @Test
    fun wireValuesMatchTheDirectusColumns() {
        assertEquals(listOf("settings", "rating", "hidden", "card"), Feedback.Source.entries.map { it.wire })
        assertEquals(listOf("bug", "idea", "content", "other"), Feedback.Kind.entries.map { it.wire })
        // iOS also has "watch"; there is no Wear OS app, so Android never offers it.
        assertFalse(Feedback.Area.entries.any { it.wire == "watch" })
    }

    @Test
    fun onlyTheMessageIsRequired() {
        assertFalse(FeedbackDraft().isValid)
        assertFalse(FeedbackDraft(message = "  \n ").isValid)
        assertNull(FeedbackDraft(message = " ").submission(Feedback.Source.Settings))
        val row = FeedbackDraft(message = " broken ").submission(Feedback.Source.Settings)!!
        assertEquals("other", row.kind)
        assertEquals("broken", row.message)
        assertEquals("settings", row.source)
    }

    @Test
    fun areaTravelsOnlyForABug() {
        val bug = FeedbackDraft(kind = Feedback.Kind.Bug, area = Feedback.Area.Audio, message = "x")
        assertEquals("audio", bug.submission(Feedback.Source.Settings)!!.area)
        assertEquals("", bug.copy(kind = Feedback.Kind.Idea).submission(Feedback.Source.Settings)!!.area)
    }

    @Test
    fun theWordTravelsOnlyForContent() {
        val item = Feedback.Item(lesson = 2, romaji = "tsukue")
        val content = FeedbackDraft(kind = Feedback.Kind.Content, item = item, message = "x")
        val row = content.submission(Feedback.Source.Card)!!
        assertEquals(2, row.lesson)
        assertEquals("tsukue", row.item)
        val other = content.copy(kind = Feedback.Kind.Bug).submission(Feedback.Source.Card)!!
        assertEquals(0, other.lesson)
        assertEquals("", other.item)
    }

    @Test
    fun lengthsAreCapped() {
        val draft = FeedbackDraft(
            message = "m".repeat(Feedback.MESSAGE_LIMIT + 50),
            email = " " + "e".repeat(Feedback.EMAIL_LIMIT + 50),
            kind = Feedback.Kind.Content,
            item = Feedback.Item(1, "r".repeat(Feedback.ITEM_LIMIT + 10))
        )
        val row = draft.submission(Feedback.Source.Settings)!!
        assertEquals(Feedback.MESSAGE_LIMIT, row.message.length)
        assertEquals(Feedback.EMAIL_LIMIT, row.email.length)
        assertEquals(Feedback.ITEM_LIMIT, row.item.length)
    }

    @Test
    fun theStarsRideAlongAndTheTrackParamsNeverCarryText() {
        val draft = FeedbackDraft(stars = 2, message = "secret words", email = "a@b.c")
        assertEquals(2, draft.submission(Feedback.Source.Rating)!!.stars)
        val params = draft.trackParams(Feedback.Source.Rating)
        assertEquals("rating", params["source"])
        assertEquals(12, params["message_length"])
        assertEquals(true, params["has_email"])
        assertTrue(params.values.none { it == "secret words" || it == "a@b.c" })
    }
}
