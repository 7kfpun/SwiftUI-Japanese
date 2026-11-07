package com.kfpun.japanesedaily.ladder

import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.data.vocab.VocabStore
import com.kfpun.japanesedaily.lessons.VForm
import java.io.File
import java.text.Normalizer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The ladder maths against numbers dumped from the real Swift (`python3 scripts/dump-challenge-fixtures.py`):
 * rung sizing, the review window, form tiering, `supports`, lookalike scores, star bands and `allowedWrong`, over the
 * real 50 lessons. Question selection is random, so `ChallengeModelTest` covers it by invariant instead.
 */
class LadderFixturesTest {
    private val store = VocabStore(FileAssetSource(File("../../nihongo/Resources")))
    private val fixtures: JsonObject =
        Json.parseToJsonElement(javaClass.getResource("/challenge/ladder-fixtures.json")!!.readText()).jsonObject

    private fun words(lesson: Int): List<Vocab> = store.lesson(lesson, "en").entries

    private fun JsonArray.ints() = map { it.jsonPrimitive.int }

    private fun JsonArray.strings() = map { it.jsonPrimitive.content }

    @Test
    fun constantsMatch() {
        val c = fixtures["constants"]!!.jsonObject
        assertEquals(c["questionsPerChallenge"]!!.jsonPrimitive.int, Challenge.QUESTIONS_PER_CHALLENGE)
        assertEquals(c["passScore"]!!.jsonPrimitive.int, Challenge.PASS_SCORE)
        assertEquals(c["wordsPerStep"]!!.jsonPrimitive.int, Challenge.WORDS_PER_STEP)
        assertEquals(c["reviewWindow"]!!.jsonPrimitive.int, Challenge.REVIEW_WINDOW)
        assertEquals(c["minReviewSlots"]!!.jsonPrimitive.int, Challenge.MIN_REVIEW_SLOTS)
    }

    @Test
    fun starBandsMatchForEveryScore() {
        val expected = fixtures["stars"]!!.jsonArray.ints()
        assertEquals(101, expected.size)
        for (score in 0..100) assertEquals("score $score", expected[score], Challenge.stars(score))
    }

    @Test
    fun allowedWrongMatches() {
        for (row in fixtures["allowedWrong"]!!.jsonArray.map { it.jsonObject }) {
            val q = row["questions"]!!.jsonPrimitive.int
            val m = row["minScore"]!!.jsonPrimitive.int
            assertEquals("q=$q min=$m", row["allowed"]!!.jsonPrimitive.int, Challenge.allowedWrong(q, m))
        }
    }

    @Test
    fun rungsPoolsAndFormsMatchOnEveryLesson() {
        val lessons = fixtures["lessons"]!!.jsonArray.map { it.jsonObject }
        assertEquals(50, lessons.size)
        for (l in lessons) {
            val n = l["number"]!!.jsonPrimitive.int
            val w = words(n)
            assertEquals("lesson $n words", l["wordCount"]!!.jsonPrimitive.int, w.size)
            assertEquals("lesson $n steps", l["steps"]!!.jsonArray.ints(), Challenge.steps(w.size))
            assertEquals("lesson $n count", l["count"]!!.jsonPrimitive.int, Challenge.count(w.size))
            for (r in l["rungs"]!!.jsonArray.map { it.jsonObject }) {
                val i = r["index"]!!.jsonPrimitive.int
                val range = Challenge.poolRange(w.size, i)
                assertEquals("$n/$i start", r["poolStart"]!!.jsonPrimitive.int, range.first)
                assertEquals("$n/$i end", r["poolEnd"]!!.jsonPrimitive.int, range.last + 1)
                assertEquals("$n/$i size", r["poolSize"]!!.jsonPrimitive.int, Challenge.poolSize(w.size, i))
                assertEquals("$n/$i new", r["new"]!!.jsonArray.strings(), Challenge.newWords(w, i).map { it.id })
                assertEquals("$n/$i pool", r["pool"]!!.jsonArray.strings(), Challenge.pool(w, i).map { it.id })
                val forms = Challenge.forms(i, w.size).map { "${it.from.label}>${it.to.label}" }
                assertEquals("$n/$i forms", r["forms"]!!.jsonArray.strings(), forms)
            }
        }
    }

    @Test
    fun supportsMatchesForEveryWord() {
        val lessons = fixtures["lessons"]!!.jsonArray.map { it.jsonObject }
        val byLabel = VForm.entries.associateBy { it.label }
        for (l in lessons) {
            val n = l["number"]!!.jsonPrimitive.int
            val pairs = l["supportPairs"]!!.jsonArray.strings().map { p ->
                val (a, b) = p.split(">")
                byLabel.getValue(a) to byLabel.getValue(b)
            }
            val rows = l["supports"]!!.jsonArray.strings()
            words(n).forEachIndexed { k, word ->
                val bits = pairs.joinToString("") { (f, t) -> if (Challenge.supports(word, f, t)) "1" else "0" }
                assertEquals("${word.id} supports", rows[k], bits)
            }
        }
    }

    @Test
    fun lookalikeScoresMatch() {
        val byId = words(1).associateBy { it.id }
        val rows = fixtures["lookalikes"]!!.jsonArray.map { it.jsonObject }
        assertTrue(rows.isNotEmpty())
        for (r in rows) {
            val c = byId.getValue(r["candidate"]!!.jsonPrimitive.content)
            val a = byId.getValue(r["answer"]!!.jsonPrimitive.content)
            assertEquals("${c.id} vs ${a.id}", r["score"]!!.jsonPrimitive.int, ChallengeModel.lookalike(c, a))
        }
    }

    @Test
    fun cheerPoolsMatchTheSwift() {
        val cheers = fixtures["cheers"]!!.jsonObject
        fun pool(name: String) = cheers[name]!!.jsonArray.map {
            val o = it.jsonObject
            Cheer(
                o["text"]!!.jsonPrimitive.content,
                o["key"]!!.jsonPrimitive.content,
                o["meaning"]!!.jsonPrimitive.content
            )
        }
        assertEquals(pool("passed"), Cheer.passed)
        assertEquals(pool("perfect"), Cheer.perfect)
        assertEquals(pool("missed"), Cheer.missed)
    }

    /** `lookalike` compares `first`/`length`, which equal Swift's grapheme counts only on precomposed kana. */
    @Test
    fun everyKanaIsPrecomposed() {
        for (n in 1..50) {
            for (w in words(n)) {
                assertEquals(w.id, Normalizer.normalize(w.kana, Normalizer.Form.NFC), w.kana)
            }
        }
    }
}
