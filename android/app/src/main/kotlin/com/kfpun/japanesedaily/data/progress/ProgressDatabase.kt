package com.kfpun.japanesedaily.data.progress

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

// No table has a unique constraint beyond its surrogate id: one row per challenge / kana / word / day
// is a convention kept by the repository's upsert, and every reader tolerates duplicates, so a later
// sign-in sync (FOX-163) can merge devices without a rewrite.

@Entity(tableName = "challenge_result", indices = [Index("key"), Index("lesson")])
data class ChallengeResultRow(
    @PrimaryKey(autoGenerate = true) val rowId: Long = 0,
    val key: String,
    val lesson: Int,
    val idx: Int,
    val bestScore: Int,
    val stars: Int,
    val attempts: Int,
    val completedAt: Long?
) {
    fun toDomain() = ChallengeResult(lesson, idx, bestScore, stars, attempts, completedAt)
}

fun ChallengeResult.toRow(rowId: Long = 0) =
    ChallengeResultRow(rowId, id, lesson, index, bestScore, stars, attempts, completedAt)

@Entity(tableName = "kana_result", indices = [Index("romaji")])
data class KanaResultRow(
    @PrimaryKey(autoGenerate = true) val rowId: Long = 0,
    val romaji: String,
    val isCorrect: Boolean,
    val timestamp: Long
) {
    fun toDomain() = KanaResult(romaji, isCorrect, timestamp)
}

@Entity(tableName = "study_day", indices = [Index("day")])
data class StudyDayRow(@PrimaryKey(autoGenerate = true) val rowId: Long = 0, val day: Int, val answers: Int)

@Entity(tableName = "bookmark", indices = [Index("word")])
data class BookmarkRow(
    @PrimaryKey(autoGenerate = true) val rowId: Long = 0,
    val word: String,
    val lesson: Int,
    val stars: Int,
    val savedAt: Long
) {
    fun toDomain() = Bookmark(word, lesson, stars, savedAt)
}

/** Per-word Practice stage, keyed by `Vocab.id`. Absent means unseen. */
@Entity(tableName = "practice_stage")
data class PracticeStageRow(@PrimaryKey val word: String, val stage: Int)

@Dao
interface ChallengeDao {
    @Query("SELECT * FROM challenge_result WHERE key = :key")
    suspend fun forKey(key: String): List<ChallengeResultRow>

    @Query("SELECT * FROM challenge_result WHERE lesson = :lesson")
    suspend fun forLesson(lesson: Int): List<ChallengeResultRow>

    @Query("SELECT * FROM challenge_result")
    suspend fun all(): List<ChallengeResultRow>

    @Query("SELECT * FROM challenge_result")
    fun observeAll(): Flow<List<ChallengeResultRow>>

    @Insert
    suspend fun insert(row: ChallengeResultRow): Long

    @Update
    suspend fun update(row: ChallengeResultRow)
}

@Dao
interface KanaDao {
    @Query("SELECT * FROM kana_result WHERE romaji = :romaji")
    suspend fun forRomaji(romaji: String): List<KanaResultRow>

    @Query("SELECT * FROM kana_result")
    suspend fun all(): List<KanaResultRow>

    @Query("SELECT * FROM kana_result")
    fun observeAll(): Flow<List<KanaResultRow>>

    @Insert
    suspend fun insert(row: KanaResultRow): Long

    @Update
    suspend fun update(row: KanaResultRow)
}

@Dao
interface StudyDayDao {
    @Query("SELECT * FROM study_day WHERE day = :day")
    suspend fun forDay(day: Int): List<StudyDayRow>

    @Query("SELECT * FROM study_day")
    suspend fun all(): List<StudyDayRow>

    @Query("SELECT * FROM study_day")
    fun observeAll(): Flow<List<StudyDayRow>>

    @Insert
    suspend fun insert(row: StudyDayRow): Long

    @Update
    suspend fun update(row: StudyDayRow)
}

@Dao
interface BookmarkDao {
    @Query("SELECT * FROM bookmark")
    suspend fun all(): List<BookmarkRow>

    @Query("SELECT * FROM bookmark")
    fun observeAll(): Flow<List<BookmarkRow>>

    @Query("SELECT * FROM bookmark WHERE word = :word")
    suspend fun forWord(word: String): List<BookmarkRow>

    @Query("DELETE FROM bookmark WHERE word = :word")
    suspend fun deleteWord(word: String)

    @Insert
    suspend fun insert(row: BookmarkRow): Long
}

@Dao
interface PracticeDao {
    @Query("SELECT * FROM practice_stage")
    suspend fun all(): List<PracticeStageRow>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(row: PracticeStageRow)

    @Query("DELETE FROM practice_stage WHERE word = :word")
    suspend fun delete(word: String)
}

@Database(
    entities = [
        ChallengeResultRow::class,
        KanaResultRow::class,
        StudyDayRow::class,
        BookmarkRow::class,
        PracticeStageRow::class
    ],
    version = 1,
    exportSchema = true
)
abstract class ProgressDatabase : RoomDatabase() {
    abstract fun challenges(): ChallengeDao

    abstract fun kana(): KanaDao

    abstract fun studyDays(): StudyDayDao

    abstract fun bookmarks(): BookmarkDao

    abstract fun practice(): PracticeDao

    companion object {
        const val NAME = "progress.db"

        fun open(context: Context): ProgressDatabase =
            Room.databaseBuilder(context.applicationContext, ProgressDatabase::class.java, NAME).build()
    }
}
