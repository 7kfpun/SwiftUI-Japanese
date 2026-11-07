package com.kfpun.japanesedaily.data.progress

import androidx.room.withTransaction
import com.kfpun.japanesedaily.data.Course
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.data.vocab.VocabStore
import java.time.Instant
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Everything the app records about the learner, on this device only (ports of the `record`/reader
 * statics on `ChallengeResult`, `KanaResult`, `StudyDay` and `Bookmark`).
 *
 * Rules carried over from iOS: best-only persistence, duplicate rows tolerated by every reader, a
 * streak day written by *answering* (never by launching), and no seeded or invented history.
 */
class ProgressRepository(
    private val db: ProgressDatabase,
    private val vocab: VocabStore,
    private val course: Course = Course.current,
    private val clock: () -> Instant = { Instant.now() },
    /** Called once per studied day, on that day's first answer: the hook for the `study_day` event. */
    private val onFirstAnswerToday: (Streak) -> Unit = {}
) {
    // region Study days

    private suspend fun recordStudyDay() {
        val today = StudyDay.stamp(clock())
        val rows = db.studyDays().forDay(today)
        val first = rows.isEmpty()
        val row = rows.maxByOrNull { it.answers }
        if (row != null) {
            db.studyDays().update(row.copy(answers = row.answers + 1))
        } else {
            db.studyDays().insert(StudyDayRow(day = today, answers = 1))
        }
        if (first) onFirstAnswerToday(streak())
    }

    suspend fun streak(): Streak = Streak(db.studyDays().all().map { it.day }.toSet(), StudyDay.stamp(clock()))

    fun observeStreak(): Flow<Streak> = db.studyDays().observeAll().map { rows ->
        Streak(rows.map { it.day }.toSet(), StudyDay.stamp(clock()))
    }

    // endregion

    // region Challenge ladder

    /** Records an attempt, keeping the better score. Returns the stored row. */
    suspend fun recordChallenge(lesson: Int, index: Int, score: Int): ChallengeResult = db.withTransaction {
        val key = ChallengeResult.key(lesson, index)
        val matches = db.challenges().forKey(key)
        // Duplicate rows (a later merge): update the strongest, never a weaker twin.
        val existing = matches.reduceOrNull { a, b ->
            if (ChallengeResult.better(a.toDomain(), b.toDomain()) == a.toDomain()) a else b
        }
        var row = existing?.toDomain() ?: ChallengeResult(lesson, index)
        row = row.copy(attempts = row.attempts + 1)
        if (score > row.bestScore) row = row.copy(bestScore = score, stars = LadderRules.stars(score))
        // Stamped once, on the first pass: a replay does not move it.
        if (row.completedAt == null && score >= LadderRules.PASS_SCORE) {
            row = row.copy(completedAt = clock().toEpochMilli())
        }
        if (existing != null) db.challenges().update(row.toRow(existing.rowId)) else db.challenges().insert(row.toRow())
        // Any attempt counts toward the streak, passed or not.
        recordStudyDay()
        row
    }

    /** Every stored result for a lesson keyed by challenge index; duplicates collapse to the strongest. */
    suspend fun challengesByIndex(lesson: Int): Map<Int, ChallengeResult> =
        ChallengeResult.collapse(db.challenges().forLesson(lesson).map { it.toDomain() })
            .values.associateBy { it.index }

    /** All results, collapsed per challenge id, as a live stream. */
    fun observeChallenges(): Flow<Map<String, ChallengeResult>> =
        db.challenges().observeAll().map { rows -> ChallengeResult.collapse(rows.map { it.toDomain() }) }

    private fun rungs(lesson: Int): Int = LadderRules.count(vocab.wordCount(lesson))

    /**
     * Lesson `n`'s challenges open only once every challenge of lesson `n - 1` is *passed* (not
     * three-starred). Lesson 1 owes nothing, and a lesson with no rungs on record degrades open.
     */
    suspend fun previousLessonCleared(lesson: Int): Boolean {
        if (lesson <= 1) return true
        return ChallengeResult.passedCount(challengesByIndex(lesson - 1)) >= rungs(lesson - 1)
    }

    /** Rungs passed across every lesson, deduped by id so a merge cannot inflate it. */
    suspend fun totalPassed(): Int = ChallengeResult.collapse(db.challenges().all().map { it.toDomain() })
        .values.count { it.isPassed }

    /** Three stars on every rung of lessons `1..freeLessonLimit`: earns the first band free. */
    suspend fun hasEarnedFirstGroup(): Boolean {
        val limit = course.freeLessonLimit
        if (limit < 1) return false
        val best = ChallengeResult.collapse(db.challenges().all().map { it.toDomain() }).values
        return (1..limit).all { lesson ->
            val total = rungs(lesson)
            // A lesson with no known rung count has only failed to be measured, not been mastered.
            total > 0 && best.count { it.lesson == lesson && it.stars >= 3 } == total
        }
    }

    /** (three-starred rungs, total rungs) over the free lessons, for the progress line. */
    suspend fun firstGroupProgress(): Pair<Int, Int> {
        val limit = course.freeLessonLimit
        if (limit < 1) return 0 to 0
        val best = ChallengeResult.collapse(db.challenges().all().map { it.toDomain() }).values
        val total = (1..limit).sumOf { rungs(it) }
        return best.count { it.lesson <= limit && it.stars >= 3 } to total
    }

    // endregion

    // region Kana

    /** Upserts the row for a kana (latest wins), and counts toward the streak. */
    suspend fun recordKana(romaji: String, isCorrect: Boolean) = db.withTransaction {
        val now = clock().toEpochMilli()
        val existing = db.kana().forRomaji(romaji).maxByOrNull { it.timestamp }
        if (existing != null) {
            db.kana().update(existing.copy(isCorrect = isCorrect, timestamp = now))
        } else {
            db.kana().insert(KanaResultRow(romaji = romaji, isCorrect = isCorrect, timestamp = now))
        }
        recordStudyDay()
    }

    suspend fun kanaResults(): Map<String, KanaResult> = KanaResult.latest(db.kana().all().map { it.toDomain() })

    fun observeKana(): Flow<Map<String, KanaResult>> =
        db.kana().observeAll().map { rows -> KanaResult.latest(rows.map { it.toDomain() }) }

    // endregion

    // region Bookmarks

    suspend fun bookmarks(): List<Bookmark> = Bookmark.collapse(db.bookmarks().all().map { it.toDomain() })

    fun observeBookmarks(): Flow<List<Bookmark>> =
        db.bookmarks().observeAll().map { rows -> Bookmark.collapse(rows.map { it.toDomain() }) }

    /** The tier a word is filed under, or null if it is not bookmarked. */
    suspend fun bookmarkStars(word: String): Int? =
        db.bookmarks().forWord(word).maxByOrNull { it.savedAt }?.let { Bookmark.clamp(it.stars) }

    /**
     * Files [word] under [stars], or removes it when [stars] is null. Deletes every row for the
     * word first, so duplicates cannot resurrect a bookmark the learner just cleared.
     */
    suspend fun setBookmark(stars: Int?, word: Vocab) = db.withTransaction {
        db.bookmarks().deleteWord(word.id)
        if (stars != null) {
            db.bookmarks().insert(
                BookmarkRow(
                    word = word.id,
                    lesson = word.lesson,
                    stars = Bookmark.clamp(stars),
                    savedAt = clock().toEpochMilli()
                )
            )
        }
    }

    // endregion
}
