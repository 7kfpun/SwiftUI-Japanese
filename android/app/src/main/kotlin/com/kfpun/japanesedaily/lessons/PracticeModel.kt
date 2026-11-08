package com.kfpun.japanesedaily.lessons

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.kfpun.japanesedaily.data.progress.PracticeProgress
import com.kfpun.japanesedaily.data.progress.WordStage
import com.kfpun.japanesedaily.data.vocab.Vocab
import kotlin.random.Random

/** What Practice needs from per-word stages; [PracticeProgress] is the real one, tests use a map. */
interface StageStore {
    fun stage(word: String): WordStage

    fun set(stage: WordStage, word: String)
}

/** [PracticeProgress] as a [StageStore]. */
fun PracticeProgress.asStageStore(): StageStore = object : StageStore {
    override fun stage(word: String): WordStage = this@asStageStore.stage(word)

    override fun set(stage: WordStage, word: String) = this@asStageStore.set(stage, word)
}

/**
 * The merged practice queue (port of `PracticeModel`): **only one scorer survives, the app**. A left or
 * right swipe always means *this answer*; every card is the same two-option question whatever the word's
 * stage. The persisted [WordStage] decides how much more proving a word needs. Two correct answers
 * memorise a word; a wrong one demotes it to `Seen` and the card comes back.
 *
 * Observable fields are Compose state so the screen re-renders; the logic stays plain and testable.
 */
class PracticeModel(
    val vocab: List<Vocab>,
    private val progress: StageStore,
    initialFrom: VForm = VForm.Kana,
    initialTo: VForm = VForm.Translation,
    initialMixed: Boolean = false,
    private val persistPair: (VForm, VForm, Boolean) -> Unit = { _, _, _ -> },
    private val random: Random = Random.Default
) {
    /** One entry in the queue: the word and nothing else, every card is the same card. */
    data class Item(val vocab: Vocab)

    var queue: List<Item> by mutableStateOf(emptyList())
        private set
    var options: List<Vocab> by mutableStateOf(emptyList())
        private set
    var picked: Int? by mutableStateOf(null)
        private set

    /** Cards graded this session, requeues included: "did anything happen here", the exit-ad gate. */
    var answered: Int by mutableStateOf(0)
        private set

    /** Words retired this session: a word retires only by a correct answer from `Recognized` up. */
    var retired: Int by mutableStateOf(0)
        private set
    var sessionTotal: Int by mutableStateOf(0)
        private set

    /** The session's workload in correct answers; the denominator of [fractionDone]. */
    var sessionWork: Int by mutableStateOf(1)
        private set

    var from: VForm by mutableStateOf(VForm.Kana)
        private set
    var to: VForm by mutableStateOf(VForm.Translation)
        private set

    /** Every quiz card draws a random valid pair instead. */
    var mixed: Boolean by mutableStateOf(false)
        private set

    /** The pair actually asked of the *current* card (mixed re-rolls it, kanji-less words step off kanji). */
    var questionFrom: VForm by mutableStateOf(VForm.Kana)
        private set
    var questionTo: VForm by mutableStateOf(VForm.Translation)
        private set

    val current: Item? get() = queue.firstOrNull()
    val isDone: Boolean get() = queue.isEmpty()

    fun stage(word: Vocab): WordStage = progress.stage(word.id)

    private val remainingWork: Int get() = queue.sumOf { work(progress.stage(it.vocab.id)) }

    /**
     * How far through the session's workload the learner is, in [0, 1]. Weighted by answers owed, not
     * words retired: a word needs two correct answers, so a bar drawn from `retired` sat at zero through
     * the whole first pass. [sessionWork] ratchets when a demotion grows the owed work past it.
     */
    val fractionDone: Double
        get() {
            val total = maxOf(sessionWork, 1).toDouble()
            return ((total - remainingWork) / total).coerceIn(0.0, 1.0)
        }

    init {
        // A stored half-pair (both slots on one face) is a state the sheet refuses: fall back to the default.
        if (initialFrom in QUIZ_FACES) from = initialFrom
        if (initialTo in QUIZ_FACES && initialTo != from) to = initialTo
        if (from == to) {
            from = VForm.Kana
            to = VForm.Translation
        }
        mixed = initialMixed
        restart()
    }

    /**
     * The sheet's commit: a fixed pair, or mixed. Re-deals the current question, because the distractor
     * was chosen to be distinct under the *old* pair and a collision under the new one is fatal.
     */
    fun setPair(from: VForm, to: VForm, mixed: Boolean) {
        if (from !in QUIZ_FACES || to !in QUIZ_FACES || from == to) return
        this.from = from
        this.to = to
        this.mixed = mixed
        persistPair(from, to, mixed)
        prepare()
    }

    /**
     * Builds the session from the *current* stages, so a restart after progress is a shorter queue.
     * Shuffled, not stage-sorted. A fully memorised lesson re-enters whole as quiz review.
     */
    fun restart() {
        val pending = vocab.filter { progress.stage(it.id) != WordStage.Memorized }
        val pool = pending.ifEmpty { vocab }
        queue = pool.shuffled(random).map { Item(it) }
        sessionTotal = queue.size
        sessionWork = maxOf(1, remainingWork)
        answered = 0
        retired = 0
        picked = null
        prepare()
    }

    fun choose(i: Int) {
        if (picked != null || i !in options.indices) return
        picked = i
    }

    fun isCorrectOption(i: Int): Boolean = i in options.indices && options[i].id == current?.vocab?.id

    /**
     * Called by the screen after the verdict has been shown: the only thing that moves a word up the
     * ladder. [credited] is false when the learner looked at the back of the card first: a right answer
     * after reading the answer proves nothing, so the word simply comes back. A *wrong* answer still
     * demotes, peek or no peek.
     */
    fun resolve(credited: Boolean = true) {
        val item = current ?: return
        val choice = picked ?: return
        answered += 1
        val stage = progress.stage(item.vocab.id)
        val correct = isCorrectOption(choice)
        if (correct && !credited) {
            advance(Item(item.vocab))
            return
        }
        if (correct) {
            if (stage >= WordStage.Recognized) {
                progress.set(WordStage.Memorized, item.vocab.id)
                retired += 1
                advance(null)
            } else {
                progress.set(WordStage.Recognized, item.vocab.id)
                advance(Item(item.vocab), PROVEN_WINDOW)
            }
        } else {
            progress.set(WordStage.Seen, item.vocab.id)
            advance(Item(item.vocab))
            // The demotion may have grown the owed work past the session's original total.
            sessionWork = maxOf(sessionWork, remainingWork)
        }
    }

    private fun advance(requeue: Item?, window: IntRange = REQUEUE_WINDOW) {
        if (queue.isEmpty()) return
        val rest = queue.drop(1).toMutableList()
        if (requeue != null) rest.add(minOf(random.nextInt(window.first, window.last + 1), rest.size), requeue)
        queue = rest
        picked = null
        prepare()
    }

    private fun prepare() {
        val item = current
        if (item == null) {
            options = emptyList()
            return
        }
        val (f, t) = pair(item.vocab)
        questionFrom = f
        questionTo = t
        options = options(item.vocab, vocab, f, t, random)
    }

    /**
     * Resolve the pair for one word: a uniform draw over the combinations this word *supports* when
     * mixed, otherwise the learner's fixed choice. Drawn from the supported set, never rewritten into it
     * (rewriting loaded the die toward kana to meaning on katakana-heavy lessons).
     */
    fun pair(word: Vocab): Pair<VForm, VForm> {
        val available = faces(word)
        if (mixed) {
            val combos = available.flatMap { a -> available.filter { it != a }.map { b -> a to b } }
            return combos.randomOrNull(random) ?: (VForm.Kana to VForm.Translation)
        }
        // The fixed pair, with any slot the word cannot fill moved off kanji. When that collapses the
        // pair, the *degraded* side moves again, so the side the learner chose survives.
        var f = from
        var t = to
        val fDegraded = f !in available
        val tDegraded = t !in available
        if (fDegraded) f = VForm.Kana
        if (tDegraded) t = VForm.Kana
        if (f == t) {
            if (fDegraded) {
                f = if (t == VForm.Translation) VForm.Kana else VForm.Translation
            } else {
                t = if (f == VForm.Translation) VForm.Kana else VForm.Translation
            }
        }
        return f to t
    }

    companion object {
        /** How far back a re-queued word goes: drawn per word so cards and quizzes interleave. */
        val REQUEUE_WINDOW = 3..8

        /** After a word's first correct answer: much further back, it needs confirming, not another look. */
        val PROVEN_WINDOW = 18..28

        /** Two candidates, one swipe: the gentlest form of being asked. */
        const val OPTION_COUNT = 2

        /** A deliberate subset of [VForm]: romaji is a crutch, audio belongs to the ladder. */
        val QUIZ_FACES = listOf(VForm.Kana, VForm.Kanji, VForm.Translation)

        /** Resolves a stored `VForm.label` into a quiz face; unset or unrecognised reads as null. */
        fun face(label: String?): VForm? = QUIZ_FACES.firstOrNull { it.label == label }

        /** Correct answers a word at [stage] still owes: one from `Recognized` up, two below. */
        fun work(stage: WordStage): Int = if (stage >= WordStage.Recognized) 1 else 2

        /** The faces a word can be asked in: a word with no kanji of its own has two, not three. */
        fun faces(word: Vocab): List<VForm> = QUIZ_FACES.filter { it != VForm.Kanji || word.displaysKanji }

        /**
         * Two options. A distractor must differ from the answer on **both** faces: matching the answer
         * side makes a second right answer marked wrong, matching the prompt side makes the question
         * unanswerable.
         */
        fun options(
            answer: Vocab,
            pool: List<Vocab>,
            from: VForm = VForm.Kana,
            to: VForm = VForm.Translation,
            random: Random = Random.Default
        ): List<Vocab> {
            val opts = mutableListOf(answer)
            var guard = 0
            while (opts.size < minOf(OPTION_COUNT, pool.size) && guard < 2000) {
                guard += 1
                val c = pool.randomOrNull(random) ?: break
                if (opts.any { it.id == c.id }) continue
                if (to.value(c) == to.value(answer) || from.value(c) == from.value(answer)) continue
                opts.add(c)
            }
            return opts.shuffled(random)
        }
    }
}

/** Minutes and card count of the session Practice would deal now (the select screen's hero). */
fun heroEstimate(counts: PracticeProgress.Counts, wordCount: Int): Pair<Int, Int> {
    val total = maxOf(wordCount, 1)
    val cards = counts.recognized + counts.unseen
    val queue = if (cards == 0) total else cards
    // ~20 s per round trip; a rough promise, deliberately rounded up.
    val minutes = maxOf(1, Math.ceil(queue * 20 / 60.0).toInt())
    return minutes to queue
}
