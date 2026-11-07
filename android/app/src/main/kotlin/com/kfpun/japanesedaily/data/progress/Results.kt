package com.kfpun.japanesedaily.data.progress

/**
 * The Challenge ladder's arithmetic that progress storage needs (ports of `Challenge.passScore`,
 * `stars(score:)`, `steps(wordCount:)` and `count(wordCount:)`). The ladder feature itself is a
 * later ticket; it should reuse this rather than redefine it.
 */
object LadderRules {
    const val PASS_SCORE = 80
    private const val QUESTIONS_PER_CHALLENGE = 10
    private const val WORDS_PER_STEP = 7
    private const val MIN_REVIEW_SLOTS = 2

    /** 1 star at the pass mark, 2 at 90, 3 only for a clean sweep. Below the pass mark none. */
    fun stars(score: Int): Int = when {
        score >= 100 -> 3
        score >= 90 -> 2
        score >= PASS_SCORE -> 1
        else -> 0
    }

    /** New words introduced by each challenge, in order. */
    fun steps(wordCount: Int): List<Int> {
        if (wordCount <= QUESTIONS_PER_CHALLENGE) return listOf(maxOf(wordCount, 0))
        val rest = wordCount - QUESTIONS_PER_CHALLENGE
        val maxNewPerLater = QUESTIONS_PER_CHALLENGE - MIN_REVIEW_SLOTS
        val later = maxOf(
            1,
            Math.round(rest.toDouble() / WORDS_PER_STEP).toInt(),
            Math.ceil(rest.toDouble() / maxNewPerLater).toInt()
        )
        val base = rest / later
        val extra = rest % later
        return listOf(QUESTIONS_PER_CHALLENGE) + List(later) { base + if (it < extra) 1 else 0 }
    }

    /** Challenges in a lesson of [wordCount] words; always at least one. */
    fun count(wordCount: Int): Int = steps(wordCount).size
}

/**
 * Persisted best result for one challenge, keyed `"<lesson>/<index>"`. Only bests are kept. A retry
 * can raise the score and stars but never lower them.
 *
 * Nothing in the table enforces one row per challenge (no unique constraint, so a later sign-in
 * sync can merge devices): every reader resolves duplicates through [better].
 */
data class ChallengeResult(
    val lesson: Int,
    val index: Int,
    val bestScore: Int = 0,
    val stars: Int = 0,
    val attempts: Int = 0,
    /** Epoch millis of the first pass; null while still unpassed. */
    val completedAt: Long? = null
) {
    val id: String get() = key(lesson, index)
    val isPassed: Boolean get() = completedAt != null

    companion object {
        fun key(lesson: Int, index: Int): String = "$lesson/$index"

        /**
         * Which of two rows for the same challenge to believe: the higher best score, then the
         * earlier first-pass date (a "first passed" stamp, so earlier is truer), then the higher
         * attempt count. On a full tie the first argument wins.
         */
        fun better(a: ChallengeResult, b: ChallengeResult): ChallengeResult {
            if (a.bestScore != b.bestScore) return if (a.bestScore > b.bestScore) a else b
            val x = a.completedAt
            val y = b.completedAt
            return when {
                x != null && y != null -> if (x <= y) a else b
                x != null -> a
                y != null -> b
                else -> if (a.attempts >= b.attempts) a else b
            }
        }

        /** Collapses rows to the strongest per challenge id. */
        fun collapse(rows: Iterable<ChallengeResult>): Map<String, ChallengeResult> {
            val best = LinkedHashMap<String, ChallengeResult>()
            for (row in rows) best[row.id] = best[row.id]?.let { better(it, row) } ?: row
            return best
        }

        /** Challenge [index] is unlocked when the one before it is passed; challenge 1 always is. */
        fun isUnlocked(index: Int, results: Map<Int, ChallengeResult>): Boolean =
            index <= 1 || results[index - 1]?.isPassed == true

        fun passedCount(results: Map<Int, ChallengeResult>): Int = results.values.count { it.isPassed }

        /** The lowest rung not yet passed, or null once the ladder is cleared. */
        fun firstUnpassed(total: Int, results: Map<Int, ChallengeResult>): Int? {
            if (total < 1) return null
            return (1..total).firstOrNull { results[it]?.isPassed != true }
        }
    }
}

/** The most recent Kana answer for a romaji. Latest [timestamp] wins on duplicates. */
data class KanaResult(val romaji: String, val isCorrect: Boolean, val timestamp: Long) {
    companion object {
        fun latest(rows: Iterable<KanaResult>): Map<String, KanaResult> {
            val out = HashMap<String, KanaResult>()
            for (row in rows) {
                val seen = out[row.romaji]
                if (seen == null || row.timestamp >= seen.timestamp) out[row.romaji] = row
            }
            return out
        }
    }
}

/**
 * A word the learner saved, filed under one, two or three stars (a grouping, not a score).
 * [word] is `Vocab.id`, stable across languages.
 */
data class Bookmark(val word: String, val lesson: Int, val stars: Int, val savedAt: Long) {
    companion object {
        fun clamp(stars: Int): Int = stars.coerceIn(1, 3)

        /** One row per word, the most recent wins, newest first. */
        fun collapse(rows: Iterable<Bookmark>): List<Bookmark> {
            val out = HashMap<String, Bookmark>()
            for (row in rows) {
                val seen = out[row.word]
                if (seen == null || row.savedAt > seen.savedAt) out[row.word] = row
            }
            return out.values.map { it.copy(stars = clamp(it.stars)) }.sortedByDescending { it.savedAt }
        }

        /** none -> 1 -> 2 -> 3 -> none. */
        fun next(stars: Int?): Int? = when (stars) {
            null -> 1
            1 -> 2
            2 -> 3
            else -> null
        }
    }
}

/** How far a word has climbed in Practice. Raw values are the stored format: append-only. */
enum class WordStage(val raw: Int) {
    Unseen(0),
    Seen(1),
    Recognized(2),
    Memorized(3);

    companion object {
        /** Clamps into the known ladder so a newer build's stage degrades rather than wipes. */
        fun fromRaw(raw: Int): WordStage = entries.first { it.raw == raw.coerceIn(0, Memorized.raw) }
    }
}
