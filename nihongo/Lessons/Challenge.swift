import Foundation

/// The Challenge ladder — the tested half of a lesson, opposite the Learn modes
/// (Vocab List / Flashcards / Learn), which are untested practice.
///
/// A lesson's words are cut into evenly-sized steps. Challenge *N* introduces step
/// *N*'s words and reviews the previous `reviewWindow - 1` steps — a sliding window,
/// so review stays on recently-met words instead of thinning across the whole lesson.
/// Every challenge asks the same `questionsPerChallenge`, so each rung costs the same
/// effort and the pass bar means the same thing everywhere. The prompt/answer forms
/// harden as you climb, which is where Listening now lives — it used to be a separate
/// mode running the very same `QuizModel`.
enum Challenge {
    /// New words a later challenge aims to introduce — a target, not a fixed size.
    static let wordsPerStep = 7
    /// Questions in every challenge, always. Uniform on purpose: it makes one rung's
    /// effort comparable to the next, keeps the pass bar identical everywhere
    /// (2 misses), and it's what makes the star bands reachable at all.
    static let questionsPerChallenge = 10
    /// Percent needed to pass — the same bar Kana Write uses, kept deliberately equal.
    static let passScore = 80

    /// New words introduced by each challenge, in order.
    ///
    /// Rung 1 takes a full quiz's worth, because there is nothing to review yet and a
    /// short first rung would otherwise be both the odd one out *and* the strictest
    /// (fewer questions means fewer mistakes allowed). The remainder is then split as
    /// evenly as possible rather than chopped into fixed 7s, since a fixed step leaves
    /// a ragged tail — a dozen lessons would otherwise end on a token 1–2 word rung,
    /// exactly where the lesson-completing challenge should feel like a capstone.
    ///
    /// The split keeps every later rung small enough to leave `minReviewSlots`
    /// questions for older words — otherwise a rung introducing a full quiz's worth of
    /// new words would test nothing but itself, which is precisely what the cumulative
    /// pool exists to prevent. (Lesson 22, at 20 words, is the one that trips this:
    /// a plain even split gives it 10+10 and no review at all.)
    static let minReviewSlots = 2
    private static var maxNewPerLaterRung: Int { questionsPerChallenge - minReviewSlots }

    static func steps(wordCount: Int) -> [Int] {
        guard wordCount > questionsPerChallenge else { return [max(wordCount, 0)] }
        let rest = wordCount - questionsPerChallenge
        let laterRungs = max(1,
                             Int((Double(rest) / Double(wordsPerStep)).rounded()),
                             Int((Double(rest) / Double(maxNewPerLaterRung)).rounded(.up)))
        let (base, extra) = (rest / laterRungs, rest % laterRungs)
        return [questionsPerChallenge] + (0..<laterRungs).map { base + ($0 < extra ? 1 : 0) }
    }

    /// How many steps back a challenge still draws review from.
    ///
    /// A sliding window rather than the whole lesson so far. Cumulative sounds more
    /// thorough but spreads the same handful of review slots over an ever-growing
    /// pool: measured across all 50 lessons it leaves 61% of words asked exactly once
    /// — at their introduction — and skews what review remains toward the *earliest*
    /// words, which sit in the pool longest. A three-step window cuts that to 48% and
    /// keeps review on the words most recently met. Short lessons are unaffected: with
    /// fewer rungs than the window, this is the cumulative pool.
    static let reviewWindow = 3

    /// Word index range visible to challenge `index` (1-based): its own step plus the
    /// previous `reviewWindow - 1`.
    static func poolRange(wordCount: Int, index: Int) -> Range<Int> {
        let s = steps(wordCount: wordCount)
        let end = s.prefix(index).reduce(0, +)
        let start = s.prefix(max(0, index - reviewWindow)).reduce(0, +)
        return start..<max(start, end)
    }

    /// Cumulative word count up to and including challenge `index` — where the ladder
    /// has reached, as opposed to what a given challenge can currently see.
    static func poolSize(wordCount: Int, index: Int) -> Int {
        steps(wordCount: wordCount).prefix(index).reduce(0, +)
    }

    /// Challenges in a lesson of `wordCount` words. Always at least one, so even a
    /// hypothetical empty lesson still renders a ladder rather than nothing.
    static func count(wordCount: Int) -> Int { steps(wordCount: wordCount).count }

    /// The words challenge `index` draws on — its new words plus the review window.
    static func pool(_ words: [Vocab], index: Int) -> [Vocab] {
        let r = poolRange(wordCount: words.count, index: index)
        return Array(words[r.clamped(to: 0..<words.count)])
    }

    /// Just the words challenge `index` introduces — guaranteed a question each, so a
    /// challenge always tests what it taught rather than drifting into pure review.
    static func newWords(_ words: [Vocab], index: Int) -> [Vocab] {
        let start = poolSize(wordCount: words.count, index: index - 1)
        let end = poolSize(wordCount: words.count, index: index)
        guard start < end, start < words.count else { return [] }
        return Array(words[start..<min(end, words.count)])
    }

    /// 1★ at the pass mark, 2★ at 90, 3★ only for a clean sweep. Below the pass mark
    /// there are no stars — and no completion.
    static func stars(score: Int) -> Int {
        switch score {
        case 100...:        return 3
        case 90..<100:      return 2
        case passScore..<90: return 1
        default:            return 0
        }
    }

    /// Prompt→answer form pairs unlocked by challenge `index`.
    ///
    /// Keyed to the absolute rung, not to progress through the lesson. Scaling by
    /// fraction sounds fairer but inverts the intent: a 9-rung lesson would spend its
    /// first three challenges — thirty consecutive questions — on the single easiest
    /// form, so the longer the lesson, the longer the monotony lasted.
    ///
    /// Only rung 1 is recognition-only, as a gentle first look at words just met.
    /// Recall (meaning→Japanese) arrives immediately after, because recognising a word
    /// is much easier than producing it and testing only the easy direction flatters
    /// the learner. `total` is unused now but kept in the signature — difficulty
    /// deliberately no longer depends on lesson length.
    static func forms(index: Int, of total: Int) -> [(from: VForm, to: VForm)] {
        var pairs: [(from: VForm, to: VForm)] = [(.kana, .translation)]   // recognition
        if index >= 2 { pairs += [(.translation, .kana), (.kanji, .translation)] }  // recall
        if index >= 3 { pairs += [(.audio, .translation), (.audio, .kana)] }        // no visual cue
        return pairs
    }

    /// Whether `word` can actually be asked with this form pair. Kanji prompts need a
    /// word that displays kanji (many are kana-only, where the prompt would equal the
    /// answer); audio prompts need a bundled clip.
    static func supports(_ word: Vocab, from: VForm, to: VForm) -> Bool {
        for form in [from, to] {
            switch form {
            case .kanji: if !word.displaysKanji { return false }
            case .audio: if word.audio == nil { return false }
            default: break
            }
        }
        return true
    }
}

/// One question in a challenge: a fixed prompt, fixed options, fixed forms. Unlike
/// `QuizModel` — which regenerates endlessly and lets the user cycle forms — a
/// challenge's questions are decided up front so the run is bounded and scoreable.
struct ChallengeQuestion: Identifiable {
    let id: Int
    let answer: Vocab
    let options: [Vocab]
    let from: VForm
    let to: VForm

    func isCorrect(_ optionIndex: Int) -> Bool { options[optionIndex].id == answer.id }
}

@Observable
final class ChallengeModel {
    let lessonNumber: Int
    let index: Int
    let questions: [ChallengeQuestion]

    private(set) var current = 0
    private(set) var picked: Int?
    private(set) var correct = 0
    private(set) var missed: [Vocab] = []

    var question: ChallengeQuestion? { current < questions.count ? questions[current] : nil }
    var isDone: Bool { current >= questions.count }
    var isLastQuestion: Bool { current == questions.count - 1 }

    /// Percent correct, rounded. 0 for an empty challenge rather than a divide by zero.
    var scorePercent: Int {
        guard !questions.isEmpty else { return 0 }
        return Int((Double(correct) / Double(questions.count) * 100).rounded())
    }
    var passed: Bool { scorePercent >= Challenge.passScore }
    var stars: Int { Challenge.stars(score: scorePercent) }

    init(lessonNumber: Int, index: Int, total: Int, words: [Vocab]) {
        self.lessonNumber = lessonNumber
        self.index = index
        self.questions = Self.build(words: words, index: index, total: total)
    }

    func choose(_ optionIndex: Int) {
        guard picked == nil, let q = question else { return }
        picked = optionIndex
        if q.isCorrect(optionIndex) { correct += 1 } else { missed.append(q.answer) }
    }

    func advance() {
        guard picked != nil else { return }   // no skipping past an unanswered question
        picked = nil
        current += 1
    }

    /// Build the question list: every new word this challenge introduces, then review
    /// words drawn from earlier steps, up to the question cap.
    private static func build(words: [Vocab], index: Int, total: Int) -> [ChallengeQuestion] {
        let pool = Challenge.pool(words, index: index)
        guard !pool.isEmpty else { return [] }

        let new = Challenge.newWords(words, index: index)
        let newIDs = Set(new.map(\.id))
        let review = pool.filter { !newIDs.contains($0.id) }.shuffled()

        let limit = min(Challenge.questionsPerChallenge, pool.count)
        // Selection guarantees the new words a slot; the final shuffle stops them from
        // always occupying the first questions — without it every run reads "new words,
        // then review", and after one challenge the rhythm is predictable.
        let asked = Array((new.shuffled() + review).prefix(limit)).shuffled()

        let pairs = Challenge.forms(index: index, of: total)
        return asked.enumerated().map { position, word in
            // Deal the unlocked pairs in rotation rather than drawing one at random per
            // question. Independent draws leave the mix to chance — a run could come out
            // ten kana→meaning in a row, which is exactly the monotony these tiers exist
            // to avoid. Rotating spreads the directions evenly across the challenge.
            //
            // Each question starts at its own offset and falls through to the next pair
            // the word actually supports, so kana-only words (no kanji prompt) or the
            // rare clipless one degrade to a neighbouring form instead of collapsing
            // back onto kana→meaning every time.
            let rotation = pairs.indices.map { pairs[($0 + position) % pairs.count] }
            let pair = rotation.first { Challenge.supports(word, from: $0.from, to: $0.to) }
                ?? (from: VForm.kana, to: VForm.translation)
            return ChallengeQuestion(id: position,
                                     answer: word,
                                     options: options(for: word, from: pair.from, to: pair.to, pool: pool),
                                     from: pair.from,
                                     to: pair.to)
        }
    }

    /// Four options including the answer. Two rules and one preference:
    ///
    /// - Distinct *displayed* text — two buttons reading the same thing would make the
    ///   question unanswerable.
    /// - No distractor may share the answer's *prompt-side* text either. The data has
    ///   homophones (います ×2 in lesson 11) and shared glosses (なん/なに = "what"):
    ///   under an audio prompt such a distractor sounds identical to the answer, and
    ///   under a translation prompt it IS a second right answer — picking it would be
    ///   marked wrong. Roughly one challenge in twenty can hit this without the guard.
    /// - Prefer distractors that *resemble* the answer (shared first kana, similar
    ///   length). Uniformly random distractors are usually eliminable at a glance —
    ///   a two-kana word among six-kana options answers itself — and confusable
    ///   options are what makes a multiple-choice question worth anything.
    private static func options(for answer: Vocab, from: VForm, to: VForm, pool: [Vocab]) -> [Vocab] {
        var chosen = [answer]
        var seen = Set([to.value(answer)])
        let promptText = from.value(answer)

        // Shuffle first so similarity ties break randomly run to run.
        let ranked = pool.shuffled().sorted { lookalike($0, answer) > lookalike($1, answer) }
        for candidate in ranked where chosen.count < 4 {
            let text = to.value(candidate)
            guard from.value(candidate) != promptText, !seen.contains(text) else { continue }
            seen.insert(text)
            chosen.append(candidate)
        }
        return chosen.shuffled()
    }

    /// How confusable `candidate` is with `answer`, judged on the reading: sharing the
    /// first kana forces actual recall (the usual shortcut is recognising just the
    /// start), and near-equal length removes the "the long one" giveaway.
    private static func lookalike(_ candidate: Vocab, _ answer: Vocab) -> Int {
        let c = cleanWord(candidate.kana), a = cleanWord(answer.kana)
        var score = 0
        if c.first == a.first { score += 2 }
        if abs(c.count - a.count) <= 1 { score += 1 }
        return score
    }
}
