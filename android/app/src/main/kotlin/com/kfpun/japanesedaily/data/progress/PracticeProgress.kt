package com.kfpun.japanesedaily.data.progress

import com.kfpun.japanesedaily.data.vocab.Vocab
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Per-word Practice state keyed by `Vocab.id` (port of `PracticeProgress`). Local-only by decision:
 * unscored study metadata. Reads come from an in-memory map loaded once with [load]; each [set]
 * updates the map immediately and writes through to Room on [scope].
 */
class PracticeProgress(private val dao: PracticeDao, private val scope: CoroutineScope) {
    private val stages = HashMap<String, WordStage>()
    private var lastWrite: Job? = null

    /** Reads the stored stages. Unknown raw values clamp into the ladder; nothing is wiped. */
    suspend fun load() {
        val rows = dao.all()
        synchronized(this) {
            stages.clear()
            for (row in rows) stages[row.word] = WordStage.fromRaw(row.stage)
        }
    }

    /** Absent word: the common case forever, since only practised words get a row. */
    @Synchronized
    fun stage(word: String): WordStage = stages[word] ?: WordStage.Unseen

    @Synchronized
    fun snapshot(): Map<String, WordStage> = stages.toMap()

    @Synchronized
    fun set(stage: WordStage, word: String) {
        if (stage(word) == stage) return
        if (stage == WordStage.Unseen) stages.remove(word) else stages[word] = stage
        // Chained so writes land in the order they were made, even on a multi-threaded dispatcher.
        val previous = lastWrite
        lastWrite = scope.launch {
            previous?.join()
            if (stage == WordStage.Unseen) dao.delete(word) else dao.upsert(PracticeStageRow(word, stage.raw))
        }
    }

    /** Suspends until every write made so far is stored. Call before the process may die. */
    suspend fun flush() {
        val pending = synchronized(this) { lastWrite }
        pending?.join()
    }

    /** Memorized / recognized / unseen for one lesson's entries. `Seen` folds into unseen. */
    data class Counts(val memorized: Int = 0, val recognized: Int = 0, val unseen: Int = 0)

    fun counts(entries: List<Vocab>): Counts {
        var c = Counts()
        for (word in entries) {
            c = when (stage(word.id)) {
                WordStage.Memorized -> c.copy(memorized = c.memorized + 1)
                WordStage.Recognized -> c.copy(recognized = c.recognized + 1)
                WordStage.Seen, WordStage.Unseen -> c.copy(unseen = c.unseen + 1)
            }
        }
        return c
    }
}
