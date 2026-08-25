# 02 — The Challenge ladder

The app's core mechanic, and the only thing in it that is *scored*. Every lesson is
cut into a ladder of equally-sized rungs; a rung tests the words it introduces plus a
sliding window of recent review; passing a rung opens the next one. Three files own
it and nothing else does:

| File | Owns |
|---|---|
| `nihongo/Lessons/Challenge.swift` | The maths: rung sizing, the review window, form tiering, star bands, question generation |
| `nihongo/ChallengeResult.swift` | Persistence: best-only rows, the unlock rule, the CloudKit merge resolver |
| `nihongo/Lessons/ChallengeView.swift` | One run: fixed questions, result screen, ad + rating hooks |

`SelectModeView` renders the rungs (`04-lessons.md`), `TodayView` deals the next
rung's words (`00-overview.md`), and `LessonListView` draws the per-lesson progress
bar from passed counts. All three read the same functions rather than re-deriving
anything.

## The four constants everything else follows from

`Challenge.swift:15-37`:

| Constant | Value | Why that value |
|---|---|---|
| `questionsPerChallenge` | 10 | Uniform on purpose — one rung's effort equals the next's, "80%" means exactly 2 misses everywhere, and the star bands are only reachable at all because the denominator is fixed |
| `passScore` | 80 | Deliberately the same bar Kana Write uses (`KanaWriteView.passScore`) |
| `wordsPerStep` | 7 | A *target* for how many new words a later rung introduces, not a fixed size |
| `reviewWindow` | 3 | How many steps back a rung still draws review from |
| `minReviewSlots` | 2 | Questions a later rung must leave for older words |

## Rung sizing, and the even-split edge case

`Challenge.steps(wordCount:)` (`Challenge.swift:40`) returns the number of *new*
words each rung introduces. Lesson sizes run 17–63 words, so a fixed step size was
never going to work.

```
wordCount ≤ 10          → one rung, the whole lesson
otherwise               → [10] + an even split of the remainder
  laterRungs = max(1, round(rest / wordsPerStep), ceil(rest / (questions − minReviewSlots)))
  each later rung gets rest / laterRungs, with the remainder spread one-per-rung
```

Three decisions are packed into that:

- **Rung 1 takes a full quiz's worth (10).** There is nothing to review yet, so a
  short first rung would be both the odd one out *and* the strictest in the lesson —
  fewer questions means fewer mistakes allowed to clear 80%.
- **The remainder is split evenly, not chopped into 7s.** A fixed step leaves a
  ragged tail: a dozen lessons would end on a token 1–2 word rung, exactly where the
  lesson-completing challenge should feel like a capstone. `ChallengeTests.everyRungIsWellSized`
  pins `size >= 3` on every later rung of all 50 lessons.
- **The `ceil(rest / 8)` term is the edge case.** A plain even split can produce a
  later rung of 10 new words, which would fill all 10 questions with itself and leave
  the cumulative pool doing nothing. Lesson 22 (20 words) is the one that trips it: an
  unguarded split gives `[10, 10]`, so the third term forces two later rungs and
  yields `[10, 5, 5]`. The same test asserts `size <= questionsPerChallenge −
  minReviewSlots` everywhere.

`Challenge.count(wordCount:)` is just `steps().count`, and it is always ≥ 1 so even a
hypothetical empty lesson renders a ladder rather than nothing.

## The sliding review window — and the 61% → 48% measurement

`Challenge.poolRange(wordCount:index:)` (`Challenge.swift:63`) gives a rung its own
step plus the previous `reviewWindow − 1` steps. **Not** everything so far.

Cumulative sounds more thorough and measurably isn't. Across all 50 lessons a
cumulative pool leaves **61% of words asked exactly once** — at their introduction —
because the same handful of leftover review slots gets spread over an ever-growing
pool, and what review survives skews toward the *earliest* words, which sit in the
pool longest. A three-step window cuts that to **48%** and keeps review on the words
most recently met. Short lessons are unaffected: with fewer rungs than the window,
the window *is* the cumulative pool.

`ChallengeTests.poolIsASlidingWindow` uses lesson 40 (63 words, the longest ladder)
to assert the pool equals the sum of the last three steps and that the final rung no
longer sees the whole lesson.

Two related helpers exist because they answer different questions:
`poolSize(wordCount:index:)` is where the ladder has *reached* (cumulative), while
`poolRange`/`pool` is what a given rung can currently *see*. `newWords(_:index:)` is
the difference between consecutive `poolSize`s — the words this rung introduces, which
are guaranteed a question each so a rung always tests what it taught.

## Form tiering by rung

`Challenge.forms(index:of:)` (`Challenge.swift:118`) returns the prompt→answer pairs a
rung may ask, using `VForm` (defined in `Lessons/VForm.swift`):

| Rung | Pairs unlocked | Kind |
|---|---|---|
| 1 | kana → meaning | recognition |
| ≥ 2 | + meaning → kana, kanji → meaning | recall |
| ≥ 3 | + audio → meaning, audio → kana | no visual cue |

- **Keyed to the absolute rung, not to progress through the lesson.** Scaling by
  fraction sounds fairer and inverts the intent: a 9-rung lesson would spend its first
  three rungs — thirty consecutive questions — on the single easiest form, so the
  longer the lesson, the longer the monotony lasted. `ChallengeTests.formsHardenAcrossTheLadder`
  asserts rung 1 is the *only* single-form rung in every lesson.
- **Recall arrives immediately after rung 1.** Recognising a word is much easier than
  producing it, and testing only the easy direction flatters the learner.
- `total` is still in the signature but unused — difficulty deliberately no longer
  depends on lesson length.
- `Challenge.supports(_:from:to:)` filters pairs per word: a kanji prompt needs
  `displaysKanji` (many entries are kana-only, where prompt would equal answer), an
  audio prompt needs a bundled clip.

### Why pairs are dealt in rotation

`ChallengeModel.build` (`Challenge.swift:196`) does **not** draw a pair at random per
question. Independent draws leave the mix to chance — a run can legitimately come out
ten kana→meaning in a row, which is the monotony the tiers exist to prevent. Instead
each question starts at its own offset into the unlocked pairs and falls through to the
first pair the word actually supports, with `kana → translation` as the last resort. So
directions spread evenly, and a kana-only or clipless word degrades to a *neighbouring*
form instead of collapsing back onto the easiest one every time.
`ChallengeTests.challengesMixPromptDirections` requires ≥2 distinct pairs per rung from
rung 2 on, in every lesson.

### Question selection and distractors

New words are shuffled in front of shuffled review, truncated to
`min(questionsPerChallenge, pool.count)`, and then **shuffled again** — without that
final shuffle every run reads "new words, then review" and the rhythm is predictable
after one rung.

`ChallengeModel.options` (`Challenge.swift:245`) builds four options: two rules and one
preference.

1. **Distinct displayed text** — two buttons reading the same thing make the question
   unanswerable.
2. **No distractor may share the answer's *prompt-side* text.** The data has
   homophones (います twice in lesson 11) and shared glosses (なん/なに both "what").
   Under an audio prompt such a distractor sounds identical to the answer; under a
   translation prompt it *is* a second right answer that would be marked wrong.
   Roughly one rung in twenty would hit this without the guard, and it is why
   `generatedQuestionsAreAnswerable` tolerates 3 options (never fewer than 2) on a
   small pool.
3. **Prefer lookalikes** — `lookalike(_:_:)` scores a shared first kana +2 and a length
   difference ≤1 +1. Uniformly random distractors are usually eliminable at a glance
   (a two-kana word among six-kana options answers itself); confusable options are what
   makes multiple choice worth anything. The pool is shuffled *before* sorting so
   similarity ties break differently run to run.

## Star bands

`Challenge.stars(score:)` (`Challenge.swift:97`): **3★ only for 100**, 2★ at 90–99, 1★
at 80–89, none below the pass mark. Because every rung asks exactly 10 questions this
reads directly as "no misses / one miss / two misses", which is the whole payoff of the
uniform question count. `StarRow` (`ChallengeView.swift`) draws them on the briefing,
the result screen and the ladder chips — and the briefing states the bands **in misses**,
computed by `ChallengeView.allowedWrong` from the run's real question count rather than
hardcoded to ten (a short rung allows fewer misses, and pinned by
`ChallengeTests.briefingStarBandsFollowTheQuestionCount`).

## Persistence: best-only, and the merge resolver

`ChallengeResult` is one row per rung, keyed `"<lesson>/<index>"`. It stores
`bestScore`, `stars`, `attempts` and `completedAt` — and **no attempt history**. The
ladder asks "how far have I got, how well"; storing every run would grow without bound
for no extra answer. A retry raises the best score and stars but can never lower them,
so replaying a passed rung is always safe, and `completedAt` is stamped once on the
*first* pass so a later replay doesn't move the unlock marker
(`ChallengeResultTests.completionTimestampIsStable`).

**No `@Attribute(.unique)`, deliberately.** The container is CloudKit-backed
(`nihongoApp.swift:19-29`, `iCloud.com.kfpun.nihongo`) and CloudKit-backed SwiftData
forbids unique constraints — see `01-data-model.md`. One row per rung is therefore only
a convention that `record`'s fetch-then-update maintains, and two devices playing
offline *can* merge into duplicates. Every reader resolves that through
`ChallengeResult.better(_:_:)`:

1. higher `bestScore` wins;
2. else the **earlier** `completedAt` (it's a "first passed" stamp, so earlier is more
   truthful), a present stamp beating a nil one;
3. else the higher `attempts`.

So a sync race can inflate nothing and lose nothing. The readers that matter:

| Function | Used by | Merge handling |
|---|---|---|
| `byIndex(lesson:context:)` | `SelectModeView`, `ChallengeView`'s briefing + stats, `TodayView` | one fetch per ladder, duplicates collapsed via `better` |
| `isUnlocked(index:results:)` | rung chips | rung 1 always open, else the previous must be passed |
| `previousLessonCleared(lesson:context:)` | `SelectModeView`'s ladder section | **cross-lesson gate (2026-08-25)**: lesson n's ladder opens only once every rung of lesson n − 1 is *passed* (not three-starred — that bar belongs to the earned unlock). Lesson 1 is always open; a dataset with no rungs for the previous lesson degrades open. Study modes are untouched — the rule sequences the tests, not the studying. **There is deliberately no mid-course entrance** (kf, 2026-08-26): a learner joining at lesson 25 clears the ladders from lesson 1, full stop — the intro's `textbookLesson` answer stays recorded-only and must not be read to seed or skip the gate. Today's capsule and the widget already respect it by construction: `studyLesson()` walks lessons in order, so the frontier lesson's predecessors are cleared by definition |
| `passedCount(results:)` | the Challenge header (with the star tally) | counts passed values of the collapsed map |
| `totalPassed(context:)` | the rating prompt | dedupes by `id` **first** — counting both twins would fire the prompt early |
| `firstUnpassed(total:results:)` | Today's deck | lowest unpassed rung, nil once cleared |

`LessonListView.reloadProgress` does the same collapse by hand for its 50-row tally,
because it needs every lesson in one fetch rather than one ladder.

## One run (`ChallengeView`)

The run is fixed up front — questions, forms and order all decided by `ChallengeModel`
in `init` — because a score only means something if the run is the same shape every
time. That is the deliberate opposite of `PracticeView`, which re-queues endlessly and
lets the learner cycle forms.

**Three screens: briefing → play → result.** The briefing sizes the run up before it
starts (pool as words, star bands in misses, a "last time n%" banner on a return
visit); `challenge_start` fires from its button, not from `onAppear`, so a run begins
when the learner says so. Play adds a clock, the stars *still reachable*, per-question
pips, a spelled-out prompt label and a risk line. Result is `model.isDone` rather than
a phase, so no state bug can show a score without the questions — see `04-lessons.md`
§5 for the full anatomy.

Details that are load-bearing:

- **`restart()` returns to the briefing**, not to question 1: a retry is exactly when
  the "last time n%" banner has something to say. `advanceToNext()` does the same one
  rung up. `@State`'s initial value is used once per view *identity*, and re-pushing the
  same row reuses that identity — so without `restart()` and the `onAppear` check you
  return to the previous run's result screen with no way to play again.
- **`finish()` is guarded by `recorded`.** `isDone` can re-fire on a redraw and
  a second `ChallengeResult.record` would inflate `attempts`.
- **A miss demotes the word in `PracticeProgress`** (`.recognized`+ → `.seen`), which is
  what makes the result screen's "missed words come back in Practice" true rather than
  a promise the app doesn't keep.
- **Audio rules.** An audio prompt always
  speaks — the clip *is* the question, so the sound toggle can't silence it. Other
  prompts respect the toggle with one hard exception: a **translation prompt never
  speaks**, because the options are the Japanese words and pronouncing the answer reads
  the correct button aloud.
- **`advance()` refuses to skip an unanswered question**, and `choose` ignores a second
  pick — the "answer then lock" rule from `07-ux-ui.md`.
- **`challenge_abandon` fires from `onDisappear`** past question 1, carrying `question`.
  Count alone is `start − complete`; *where* people bail is the actionable part (see
  `08-analytics.md`).
- **The result screen swaps button prominence**: after a miss Retry leads (the words to
  fix are listed right there, deduped); after a pass Done leads while Retry stays
  available for chasing the third star. Above them sit three stat cards — this run, the
  rung's best, and the lesson's star tally out of `total * 3`.
- **Ads and the rating ask hang off the run's edges** — interstitial preloaded on
  appear, shown on the way out only if the run finished; the star row offered only to a
  premium user who just *passed* their 15th rung. Both in `06-monetization.md`.

## What's deliberately not here

- **No per-question analytics.** ~10 events per run (2,780 across the whole ladder) to
  learn which *words* are hardest — and you can't edit Minna no Nihongo's vocabulary,
  so it's high volume for near-zero actionability.
- **No spaced repetition across rungs.** The review window is positional (which step a
  word came from), not scheduled (when you last missed it). `KanaResult`-style
  per-item mastery exists for kana and deliberately has no vocab equivalent.
- **No partial credit and no time limit.** The play screen shows an elapsed clock, but
  nothing depends on it — it is a sense of pace, never a scored dimension, and no result
  is worse for taking longer.
- **No seeding from the intro's "how far have you studied" answer** — see
  `09-intro-and-survey.md` for why inventing history would be worse than ignoring it.
