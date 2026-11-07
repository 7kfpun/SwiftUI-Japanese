package com.kfpun.japanesedaily.today

import com.kfpun.japanesedaily.data.progress.ChallengeResult
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.VocabStore
import com.kfpun.japanesedaily.ladder.Challenge
import com.kfpun.japanesedaily.lessons.Gating
import java.io.File
import java.time.Duration
import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ports of the iOS `TodayTests`, plus the rotation checked against the real Swift and the deck against the ladder. */
class TodayTest {
    private val store = VocabStore(FileAssetSource(File("../../nihongo/Resources")))
    private val ladder: JsonObject =
        Json.parseToJsonElement(javaClass.getResource("/challenge/ladder-fixtures.json")!!.readText()).jsonObject
    private val rotation: JsonObject =
        Json.parseToJsonElement(javaClass.getResource("/today/rotation-fixtures.json")!!.readText()).jsonObject

    private fun at(seconds: Double): Instant = Instant.ofEpochSecond(
        Math.floor(seconds).toLong(),
        ((seconds - Math.floor(seconds)) * 1_000_000_000).toLong()
    )

    private fun passed(lesson: Int, index: Int) = ChallengeResult(lesson, index, 80, 1, 1, completedAt = 1L)

    private fun passAll(lesson: Int) = (1..Challenge.count(store.wordCount(lesson))).map { passed(lesson, it) }

    private fun derive(results: List<ChallengeResult>) =
        TodayDeck.derive(results, store::wordCount, { store.lesson(it, "en").entries })

    /** The ladder's own pool for a rung, straight from the numbers dumped from Swift. */
    private fun ladderPool(lesson: Int, rung: Int): List<String> {
        val l = ladder["lessons"]!!.jsonArray.map { it.jsonObject }.first { it["number"]!!.jsonPrimitive.int == lesson }
        val r = l["rungs"]!!.jsonArray.map { it.jsonObject }.first { it["index"]!!.jsonPrimitive.int == rung }
        return r["pool"]!!.jsonArray.map { it.jsonPrimitive.content }
    }

    // region rotation

    @Test
    fun rotationMatchesTheSwiftForFixedTimestamps() {
        val rows = rotation["rotation"]!!.jsonArray.map { it.jsonObject }
        assertTrue(rows.size > 200)
        for (r in rows) {
            val t = r["t"]!!.jsonPrimitive.double
            val count = r["count"]!!.jsonPrimitive.int
            val cursor = r["cursor"]!!.jsonPrimitive.int
            assertEquals(
                "t=$t count=$count cursor=$cursor",
                r["index"]!!.jsonPrimitive.int,
                TodayShared.rotationIndex(count, cursor, at(t))
            )
        }
    }

    @Test
    fun hourSlotAndNextHourMatchTheSwift() {
        for (r in rotation["slots"]!!.jsonArray.map { it.jsonObject }) {
            val t = r["t"]!!.jsonPrimitive.double
            assertEquals("slot $t", r["slot"]!!.jsonPrimitive.long, TodayShared.hourSlot(at(t)))
            assertEquals(
                "next $t",
                r["nextHour"]!!.jsonPrimitive.double,
                TodayShared.nextHour(at(t)).epochSecond.toDouble(),
                0.0
            )
        }
    }

    @Test
    fun rotationIsStableWithinAnHour() {
        val hour = Instant.ofEpochSecond(472_222L * 3600)
        assertEquals(
            TodayShared.rotationIndex(7, at = hour.plusSeconds(60)),
            TodayShared.rotationIndex(7, at = hour.plusSeconds(59 * 60))
        )
    }

    @Test
    fun rotationAdvancesEveryHourAndWraps() {
        val base = Instant.ofEpochSecond(1_700_000_000L)
        val indices = (0 until 7).map { TodayShared.rotationIndex(7, at = base.plusSeconds(it * 3600L)) }
        assertEquals(7, indices.toSet().size)
        assertEquals(indices[0], TodayShared.rotationIndex(7, at = base.plusSeconds(7 * 3600L)))
    }

    @Test
    fun rotationHandlesNegativeCursorsAndEmptyDecks() {
        val base = Instant.ofEpochSecond(1_700_000_000L)
        for (cursor in -20..20) assertTrue(TodayShared.rotationIndex(7, cursor, base) in 0 until 7)
        assertEquals(0, TodayShared.rotationIndex(0, -3, base))
    }

    @Test
    fun nextHourLandsOnAClockBoundary() {
        val mid = Instant.ofEpochSecond(1_700_001_234L)
        val next = TodayShared.nextHour(mid)
        assertTrue(next > mid)
        assertEquals(0L, next.epochSecond % 3600)
        assertTrue(Duration.between(mid, next) <= Duration.ofHours(1))
    }

    @Test
    fun snapshotRoundTripsAndAnOldOneStillDecodes() {
        val words = store.lesson(2, "en").entries.take(7).map {
            TodayShared.Word(it.kana, it.kanji, it.romaji, it.translation)
        }
        val snap = TodayShared.Snapshot(2, words, challenge = 3)
        assertEquals(snap, TodayShared.decode(TodayShared.encode(snap)))
        assertNull(TodayShared.decode("""{"lesson":2,"words":[]}""")!!.challenge)
        assertNull(TodayShared.decode("not json"))
    }

    // endregion

    // region deck derivation

    @Test
    fun deckIsTheChallengePoolNotJustNewWords() {
        val all = store.lesson(2, "en").entries
        val pool = Challenge.pool(all, 2)
        val new = Challenge.newWords(all, 2)
        assertTrue(pool.size > new.size)
        assertTrue(new.all { n -> pool.any { it.id == n.id } })
    }

    @Test
    fun freshInstallDealsLessonOneRungOne() {
        val deal = derive(emptyList())
        assertEquals(1, deal.lesson)
        assertEquals(1, deal.upNext)
        assertTrue(deal.hasNext)
        assertEquals(ladderPool(1, 1), deal.words.map { it.id })
    }

    @Test
    fun deckFollowsTheNextUnpassedRungAndKeepsItsReviewWindow() {
        // Rung 1 and 2 passed in lesson 1: the next is 3, whose pool is its own words plus the window before it.
        val deal = derive(listOf(passed(1, 1), passed(1, 2)))
        assertEquals(1, deal.lesson)
        assertEquals(3, deal.upNext)
        assertEquals(ladderPool(1, 3), deal.words.map { it.id })
        assertTrue(deal.words.size > Challenge.newWords(store.lesson(1, "en").entries, 3).size)
    }

    @Test
    fun aGapStopsAtTheLowestUnpassedRung() {
        val deal = derive(listOf(passed(1, 2)))
        assertEquals(1, deal.upNext)
        assertEquals(ladderPool(1, 1), deal.words.map { it.id })
    }

    @Test
    fun clearingALessonRollsOnToTheNextLessonsFirstRung() {
        val deal = derive(passAll(1))
        assertEquals(2, deal.lesson)
        assertEquals(1, deal.upNext)
        assertEquals(ladderPool(2, 1), deal.words.map { it.id })
    }

    @Test
    fun deckWalksPastTheFreeLessonsWhateverPremiumSays() {
        val results = (1..7).flatMap(::passAll)
        val deal = derive(results)
        assertEquals(8, deal.lesson)
        // The lesson is locked for a free learner, and still dealt: only the banner's destination respects the lock.
        assertTrue(Gating.isLocked(deal.lesson, isPremium = false, earnedFirstGroup = false))
        assertFalse(Gating.isLocked(deal.lesson, isPremium = true))
        assertEquals(ladderPool(8, 1), deal.words.map { it.id })
    }

    @Test
    fun aFinishedLadderParksOnTheLastRungAsReview() {
        val deal = derive((1..50).flatMap(::passAll))
        assertEquals(50, deal.lesson)
        assertEquals(Challenge.count(store.wordCount(50)), deal.upNext)
        assertFalse(deal.hasNext)
        assertEquals(ladderPool(50, deal.upNext), deal.words.map { it.id })
    }

    @Test
    fun aLessonTheDataLacksDealsAnEmptyDeckNotACrash() {
        // The ladder always owes at least one rung (`Challenge.count(0) == 1`, as on iOS), so the walk stops there.
        val deal = TodayDeck.derive(emptyList(), { 0 }, { emptyList() })
        assertEquals(1, deal.lesson)
        assertEquals(1, deal.upNext)
        assertTrue(deal.words.isEmpty())
    }

    @Test
    fun theSnapshotCarriesTheDealForTheWidget() {
        val deal = derive(listOf(passed(1, 1)))
        val snap = TodayDeck.snapshot(deal)
        assertEquals(deal.lesson, snap.lesson)
        assertEquals(deal.upNext, snap.challenge)
        assertEquals(deal.words.map { it.kana }, snap.words.map { it.kana })
        assertEquals(deal.words.map { it.translation }, snap.words.map { it.meaning })
    }

    // endregion

    // region widget

    @Test
    fun theWidgetShowsTheWordTheAppRotationPicks() {
        val deal = derive(emptyList())
        val snap = TodayDeck.snapshot(deal)
        val now = Instant.ofEpochSecond(1_700_000_000L)
        for (h in 0 until 30) {
            val t = now.plusSeconds(h * 3600L)
            val state = TodayWidgetState.of(snap, t)
            assertEquals(snap.words[TodayShared.rotationIndex(snap.words.size, at = t)], state.word)
        }
    }

    @Test
    fun anEmptyDeckFallsBackToTheSampleWords() {
        val state = TodayWidgetState.of(TodayShared.Snapshot(1, emptyList()), Instant.ofEpochSecond(0))
        assertTrue(state.word in TodayShared.sampleWords)
        assertEquals(TodayShared.sampleWords.size, state.deckSize)
    }

    @Test
    fun theHourlyRedrawIsAimedJustPastTheBoundary() {
        val mid = Instant.ofEpochSecond(1_700_001_234L)
        val delay = TodayWidgetSchedule.delayToNextHour(mid)
        assertTrue(delay > Duration.ZERO)
        assertTrue(delay <= Duration.ofHours(1).plus(TodayWidgetSchedule.boundarySlack))
        // Landing there puts the clock in the next hour, so the word has rotated.
        assertEquals(TodayShared.hourSlot(mid) + 1, TodayShared.hourSlot(mid.plus(delay)))
        // On the boundary itself the next redraw is a full hour away, never zero (no busy loop).
        val boundary = Instant.ofEpochSecond(472_222L * 3600)
        assertTrue(TodayWidgetSchedule.delayToNextHour(boundary) > Duration.ofHours(1))
    }

    @Test
    fun theWidgetDrawsNothingUntilAWidgetIsPlaced() {
        assertFalse(TodayWidgetSchedule.shouldSchedule(false))
        assertTrue(TodayWidgetSchedule.shouldSchedule(true))
    }

    // endregion
}
