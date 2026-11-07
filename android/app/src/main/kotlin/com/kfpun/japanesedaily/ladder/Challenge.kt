package com.kfpun.japanesedaily.ladder

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.kfpun.japanesedaily.audio.Speech
import com.kfpun.japanesedaily.data.progress.LadderRules
import com.kfpun.japanesedaily.data.vocab.AudioVoice
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.data.vocab.cleanWord
import com.kfpun.japanesedaily.lessons.VForm
import kotlin.math.abs
import kotlin.random.Random

/** A prompt-to-answer form pair a rung may ask. */
data class FormPair(val from: VForm, val to: VForm)

/**
 * The Challenge ladder's maths (port of iOS `enum Challenge`, `nihongo/Lessons/Challenge.swift`): rung sizing, the
 * sliding review window, form tiering and star bands. Pure, so `LadderFixturesTest` asserts it against the numbers
 * dumped from the Swift. Rung sizing and the star bands live in [LadderRules] (the progress rules need them too).
 */
object Challenge {
    /** New words a later challenge aims to introduce: a target, not a fixed size. */
    const val WORDS_PER_STEP = 7

    /** Questions in every challenge, always: it keeps the pass bar at exactly 2 misses everywhere. */
    const val QUESTIONS_PER_CHALLENGE = 10

    /** Percent needed to pass: the same bar Kana Write uses. */
    const val PASS_SCORE = LadderRules.PASS_SCORE

    /** Questions a later rung must leave for older words. */
    const val MIN_REVIEW_SLOTS = 2

    /** How many steps back a rung still draws review from (the sliding window, 48% asked once versus 61%). */
    const val REVIEW_WINDOW = 3

    /** New words introduced by each challenge, in order. */
    fun steps(wordCount: Int): List<Int> = LadderRules.steps(wordCount)

    /** Challenges in a lesson of [wordCount] words. Always at least one. */
    fun count(wordCount: Int): Int = LadderRules.count(wordCount)

    /** 1 star at the pass mark, 2 at 90, 3 only for a clean sweep. Below the pass mark none. */
    fun stars(score: Int): Int = LadderRules.stars(score)

    /** Word index range visible to challenge [index] (1-based): its own step plus the previous `REVIEW_WINDOW - 1`. */
    fun poolRange(wordCount: Int, index: Int): IntRange {
        val s = steps(wordCount)
        val end = s.take(index).sum()
        val start = s.take(maxOf(0, index - REVIEW_WINDOW)).sum()
        return start until maxOf(start, end)
    }

    /** Cumulative word count up to and including challenge [index]: where the ladder has *reached*. */
    fun poolSize(wordCount: Int, index: Int): Int = steps(wordCount).take(index).sum()

    /** The words challenge [index] draws on: its new words plus the review window. */
    fun pool(words: List<Vocab>, index: Int): List<Vocab> {
        val r = poolRange(words.size, index)
        val lo = r.first.coerceIn(0, words.size)
        val hi = (r.last + 1).coerceIn(lo, words.size)
        return words.subList(lo, hi)
    }

    /** Just the words challenge [index] introduces: each is guaranteed a question. */
    fun newWords(words: List<Vocab>, index: Int): List<Vocab> {
        val start = poolSize(words.size, index - 1)
        val end = poolSize(words.size, index)
        if (start >= end || start >= words.size) return emptyList()
        return words.subList(start, minOf(end, words.size))
    }

    /**
     * Prompt-to-answer form pairs unlocked by challenge [index]. Keyed to the absolute rung, not to progress through
     * the lesson. Rung 1 recognition only; recall from rung 2; no-visual-cue audio from rung 3. [total] is unused:
     * difficulty deliberately no longer depends on lesson length.
     */
    @Suppress("UNUSED_PARAMETER")
    fun forms(index: Int, total: Int): List<FormPair> {
        val pairs = mutableListOf(FormPair(VForm.Kana, VForm.Translation))
        if (index >=
            2
        ) {
            pairs += listOf(FormPair(VForm.Translation, VForm.Kana), FormPair(VForm.Kanji, VForm.Translation))
        }
        if (index >= 3) pairs += listOf(FormPair(VForm.Audio, VForm.Translation), FormPair(VForm.Audio, VForm.Kana))
        return pairs
    }

    /** Whether [word] can be asked with this pair: a kanji prompt needs displayed kanji, audio needs a clip. */
    fun supports(word: Vocab, from: VForm, to: VForm): Boolean = listOf(from, to).all { form ->
        when (form) {
            VForm.Kanji -> word.displaysKanji
            VForm.Audio -> word.audio != null
            else -> true
        }
    }

    /**
     * How many wrong answers still round to at least [minScore] percent: the honest way to phrase the star bands per
     * run, since a short rung allows fewer misses (port of `ChallengeView.allowedWrong`).
     */
    fun allowedWrong(questions: Int, minScore: Int): Int {
        if (questions <= 0) return 0
        var w = 0
        while (w + 1 <= questions && percent(questions - w - 1, questions) >= minScore) w++
        return w
    }

    /** `correct / total` as a rounded percent; 0 for an empty run. */
    fun percent(correct: Int, total: Int): Int =
        if (total <= 0) 0 else Math.round(correct.toDouble() / total * 100).toInt()
}

/**
 * One question in a challenge: fixed prompt, options, forms and voice. The voice is fixed when the question is built so
 * a replay sounds like the same question; a fresh run re-rolls every voice.
 */
data class ChallengeQuestion(
    val id: Int,
    val answer: Vocab,
    val options: List<Vocab>,
    val from: VForm,
    val to: VForm,
    val voice: AudioVoice = AudioVoice.Default
) {
    fun isCorrect(optionIndex: Int): Boolean = options[optionIndex].id == answer.id
}

/**
 * One run, fixed up front (port of iOS `ChallengeModel`): the questions, their forms and their order are all decided at
 * construction, because a score only means something when the run is the same shape every time. Observable fields are
 * Compose state; the logic stays plain and testable with an injected [random].
 */
class ChallengeModel(
    val lessonNumber: Int,
    val index: Int,
    total: Int,
    words: List<Vocab>,
    random: Random = Random.Default
) {
    val questions: List<ChallengeQuestion> = build(words, index, total, random)

    var current by mutableIntStateOf(0)
        private set
    var picked by mutableStateOf<Int?>(null)
        private set
    var correct by mutableIntStateOf(0)
        private set
    var missed by mutableStateOf<List<Vocab>>(emptyList())
        private set

    val question: ChallengeQuestion? get() = questions.getOrNull(current)
    val isDone: Boolean get() = current >= questions.size
    val isLastQuestion: Boolean get() = current == questions.size - 1

    /** Percent correct, rounded. 0 for an empty challenge rather than a divide by zero. */
    val scorePercent: Int get() = Challenge.percent(correct, questions.size)
    val passed: Boolean get() = scorePercent >= Challenge.PASS_SCORE
    val stars: Int get() = Challenge.stars(scorePercent)

    /** Locks in an answer; a second pick on the same question is ignored. */
    fun choose(optionIndex: Int) {
        val q = question ?: return
        if (picked != null) return
        picked = optionIndex
        if (q.isCorrect(optionIndex)) correct += 1 else missed = missed + q.answer
    }

    /** Moves past an answered question. Refuses to skip an unanswered one. */
    fun advance() {
        if (picked == null) return
        picked = null
        current += 1
    }

    /** A word missed twice shouldn't be listed twice. */
    val uniqueMissed: List<Vocab> get() = missed.distinctBy { it.id }

    companion object {
        /**
         * Every new word this challenge introduces, then review words from the window, up to the question cap, then
         * shuffled again so a run never reads "new words, then review".
         */
        private fun build(words: List<Vocab>, index: Int, total: Int, random: Random): List<ChallengeQuestion> {
            val pool = Challenge.pool(words, index)
            if (pool.isEmpty()) return emptyList()
            val new = Challenge.newWords(words, index)
            val newIds = new.map { it.id }.toSet()
            val review = pool.filter { it.id !in newIds }.shuffled(random)
            val limit = minOf(Challenge.QUESTIONS_PER_CHALLENGE, pool.size)
            val asked = (new.shuffled(random) + review).take(limit).shuffled(random)
            val pairs = Challenge.forms(index, total)
            return asked.mapIndexed { position, word ->
                // Dealt in rotation, not drawn at random: independent draws can come out ten kana-to-meaning in a row.
                // Each question starts at its own offset and falls through to the first pair the word supports.
                val rotation = pairs.indices.map { pairs[(it + position) % pairs.size] }
                val pair = rotation.firstOrNull { Challenge.supports(word, it.from, it.to) }
                    ?: FormPair(VForm.Kana, VForm.Translation)
                ChallengeQuestion(
                    id = position,
                    answer = word,
                    options = options(word, pair.from, pair.to, pool, random),
                    from = pair.from,
                    to = pair.to,
                    // Alternating voices keeps a listening rung a listening test. Rolled for every question.
                    voice = Speech.randomVoice(random)
                )
            }
        }

        /**
         * Four options including the answer: distinct displayed text, no distractor sharing the answer's prompt-side
         * text (a homophone under audio, a shared gloss under a translation prompt), and a preference for lookalikes.
         */
        fun options(answer: Vocab, from: VForm, to: VForm, pool: List<Vocab>, random: Random): List<Vocab> {
            val chosen = mutableListOf(answer)
            val seen = mutableSetOf(to.value(answer))
            val promptText = from.value(answer)
            // Shuffle first so similarity ties break randomly run to run.
            val ranked = pool.shuffled(random).sortedByDescending { lookalike(it, answer) }
            for (candidate in ranked) {
                if (chosen.size >= 4) break
                val text = to.value(candidate)
                if (from.value(candidate) == promptText || text in seen) continue
                seen += text
                chosen += candidate
            }
            return chosen.shuffled(random)
        }

        /** How confusable [candidate] is with [answer] on the reading: shared first kana +2, length within one +1. */
        fun lookalike(candidate: Vocab, answer: Vocab): Int {
            val c = cleanWord(candidate.kana)
            val a = cleanWord(answer.kana)
            var score = 0
            if (c.firstOrNull() == a.firstOrNull()) score += 2
            if (abs(c.length - a.length) <= 1) score += 1
            return score
        }
    }
}

/**
 * A short reaction to a finished challenge, spoken and shown (port of iOS `Cheer`). [text] is Japanese content (never
 * in `UIStrings.json`); [key] is the clip stem and the reading; [meaning] is the English source string of an interface
 * gloss, resolved through the string resources by the screen.
 */
data class Cheer(val text: String, val key: String, val meaning: String) {
    /** The reading as shown: `yoku-dekimashita` becomes `yoku dekimashita`. */
    val romaji: String get() = key.replace("-", " ")

    enum class Tier { Perfect, Passed, Missed }

    companion object {
        /** After a pass: six ways to say it, because praise you can predict has stopped being praise. */
        val passed = listOf(
            Cheer("すごい", "sugoi", "Amazing"),
            Cheer("よくできました", "yoku-dekimashita", "Well done"),
            Cheer("いいですね", "ii-desu-ne", "Nice"),
            Cheer("やったね", "yatta-ne", "You did it"),
            Cheer("じょうずですね", "jouzu-desu-ne", "You're good at this"),
            Cheer("そのちょうし", "sono-choushi", "That's the spirit")
        )

        /** Held back for a clean sweep: both name full marks. */
        val perfect = listOf(
            Cheer("はなまる", "hanamaru", "Full marks"),
            Cheer("かんぺき", "kanpeki", "Perfect")
        )

        /** After a miss: encouragement, never correction. */
        val missed = listOf(
            Cheer("がんばって", "ganbatte", "Keep at it"),
            Cheer("おしい", "oshii", "So close"),
            Cheer("だいじょうぶ", "daijoubu", "It's all right"),
            Cheer("もういちど", "mou-ichido", "Once more"),
            Cheer("つぎはできる", "tsugi-wa-dekiru", "You'll get it next time"),
            Cheer("あきらめないで", "akiramenaide", "Don't give up"),
            Cheer("もうすこし", "mou-sukoshi", "A little further"),
            Cheer("がんばろう", "ganbarou", "Let's keep going")
        )

        fun tier(stars: Int, passed: Boolean): Tier = when {
            stars >= 3 -> Tier.Perfect
            passed -> Tier.Passed
            else -> Tier.Missed
        }

        fun pool(tier: Tier): List<Cheer> = when (tier) {
            Tier.Perfect -> perfect
            Tier.Passed -> passed
            Tier.Missed -> missed
        }

        /** Pick one, never the one just used. Pure, so the no-repeat rule is testable. */
        fun pick(from: List<Cheer>, avoiding: Cheer?, random: Random = Random.Default): Cheer? =
            from.filter { it != avoiding }.randomOrNull(random) ?: from.randomOrNull(random)

        private val last = HashMap<Tier, Cheer>()

        /** The next phrase for a run, remembering the last of each tier so none repeats back to back. */
        @Synchronized
        fun next(stars: Int, passed: Boolean, random: Random = Random.Default): Cheer? {
            val tier = tier(stars, passed)
            val choice = pick(pool(tier), last[tier], random) ?: return null
            last[tier] = choice
            return choice
        }
    }
}
