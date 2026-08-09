# 04 — Lessons tab

The core study engine: 50 Minna no Nihongo lessons, each drillable in 5 modes.

## Browser (`nihongo/Lessons/LessonListView.swift`)

- **No search text**: a segmented `Picker` over 4 fixed groups — Beginning 1
  (1–13), Beginning 2 (14–25), Advanced 1 (26–38), Advanced 2 (39–50) — above a
  `List` of lesson-number rows for the selected group.
- **With search text**: the group picker disappears and the list becomes a
  flat, lesson-tagged result list from `searchVocab(_:in:)` (simple
  case-insensitive `contains` across kanji/kana/romaji/translation — see
  `01-data-model.md`). Input is debounced 600ms before logging a
  `search_vocab` analytics event; the filtering itself is synchronous.
- Tapping a lesson row pushes `SelectModeView` via
  `.navigationDestination(for: Lesson.self)`.
- `VocabRow` (also reused by search results and `VocabListView`) shows
  kana/kanji on the left, translation (+ lesson badge when `showLesson`) on the
  right, and a speaker icon; tapping the whole row speaks the word and logs
  `play_vocab`.

## Select-mode (`SelectModeView`)

Two sections, and the split is the point: a **Learn** section of four untested
practice modes you can wander through — **Vocab List, Flashcards, Train, Learn**,
ordered shallow → deep — then a **Challenge** section listing the lesson's rungs,
which are scored and gate each other. Its header carries `passedCount /
challengeCount`.

Re-resolves the lesson from the current `Pref.translationLanguage` on push, so
switching the Meanings language mid-session and re-entering a lesson shows the new
language immediately.

**This is the one place lesson gating is enforced** — a locked row opens the
paywall instead of navigating, so no practice screen has to police access itself.

## §1 Vocab List (`Lessons/VocabListView.swift`)

A plain list of every entry with **Play all** in the toolbar
(`LessonPlayer` — an `AVAudioPlayerDelegate`/`AVSpeechSynthesizerDelegate` that
plays each word's bundled clip in sequence, falling back to live TTS for the 2
clip-less words, advancing 0.35s after each clip finishes). The currently
playing row auto-scrolls into view and highlights. **Always free**, even on
locked lessons — it's the one mode exempt from gating, so browsing and search
never lock.

## §2 Flashcards (`Lessons/FlashcardView.swift`)

The shared `FlashcardScreen` (see `05-shared-and-audio.md`) over the lesson's
`Vocab` entries: kana(+kanji) face, reveal → translation + romaji. Locked
entirely on a premium lesson — there is no partial trial.

## §3 Learn — tile reconstruction (`Lessons/LearnView.swift`) — signature mode

The learner rebuilds a word's kana reading by tapping shuffled character
tiles in order.

- **Tile generation** (`LearnModel.loadTiles`): clean the target kana with
  `cleanWord`, then distractor count = `10 - cleanLength` (or `15 -
  cleanLength` if that's negative); if *still* negative the entry is
  sentence-length and gets **no tile game** (`isPlayable == false`) — the app
  shows the card with a "This entry is a full sentence — no tile game."
  message instead of crashing. Exactly one entry in the whole dataset hits
  this (lesson 14, a full sentence, clean length 16 > 15) — pinned by
  `LearnTests.sentenceLengthEntryBails`.
- Distractors are drawn from `KanaData.hiraganaPool`/`.katakanaPool` (whichever
  script the target's first character belongs to), shuffled together with the
  target's own characters so the correct answer is always buildable.
- **Answer checking** (`LearnModel.tap`): append the tapped character; correct
  the instant the built string equals the target, **wrong the instant it's no
  longer a prefix of the target** — an out-of-order tap fails immediately
  rather than waiting for the full length.
- **Card display**: `CardOptionsBar` toggles (kanji/kana/romaji/translation/
  sound, `@AppStorage`-backed) control what's shown around the assembled
  answer; a correct/wrong icon overlays once the state resolves.
- **Navigation**: an Ordered/Random segmented control. Ordered pages
  sequentially with swipe-to-turn (`CardPager` — see `05`); Random has a single
  shuffle button instead. Either way, paging speaks the new word explicitly in
  the page-turn handler (not via `.onChange(of: index)`, since a random jump
  can land on the same index and would silently skip the announcement).
## §4 Train — endless 50/50 practice (`Lessons/TrainView.swift`)

`TrainModel`: **the old Quiz and Listening modes, merged.** Listening was always
this same model with an audio prompt, so it became a prompt form rather than a
screen. There is no `QuizView.swift`.

- **Two options, not four** (`TrainModel.optionCount`). Train sits between
  Flashcards and Learn in the study funnel, so it stays fast and physical — a
  50/50 is the gentlest form of being asked. Four-option multiple choice now
  belongs to the Challenge ladder, where it's scored.
- **Forms**: `VForm` = `kana`/`kanji`/`romaji`/`translation`/`audio`. `audio` can
  only be a *prompt* (`VForm.answerForms` excludes it — there's no audio-clip
  answer *option*). `cycleFrom()`/`cycleTo()` walk the valid forms per side,
  always skipping whatever the other side holds so prompt and answer never
  coincide. Cycling re-deals the distractor: it was chosen to be distinct under
  the *old* pair, and with only two chips a collision under the new one is fatal.
- **Distractor rule**: a candidate must differ from the answer on *both* faces.
  Matching the displayed side makes the question unanswerable; matching the
  prompt side (homophones, shared glosses) makes it a second right answer that
  would be marked wrong.
- **Ordered vs random**: random by default, because a fixed order becomes its own
  memory cue — you start knowing what comes *next*, not the word. Turning
  `ordered` on mid-run resumes from the word on screen; it's an init parameter
  rather than a later assignment, or `didSet` would anchor the walk to a word
  already drawn at random.
- **Audio-safety rule** (`TrainModel.promptAudioSafe`): auto-playing the prompt is
  safe for every form *except* `.translation`, where hearing the word gives away
  the answer. An audio prompt always plays — the sound *is* the question.
- **Untested and unscored** beyond the session badge. Results count only in the
  Challenge ladder.

## §5 The Challenge ladder

The scored half of a lesson, and the app's core loop. Fully documented in
`Challenge.swift`/`ChallengeResult.swift`; the short version: rungs of
`questionsPerChallenge` (10) questions, `passScore` (80%) to pass, 1–3 stars by
score, and rung *N* unlocks only once *N−1* is passed
(`ChallengeResult.isUnlocked`). Prompt/answer pairs harden by rung —
recognition at 1, recall from 2, audio-with-no-visual-cue from 3
(`Challenge.forms`). Only *best* results are kept, so a retry can raise a score
but never lower it.

An interstitial ad is preloaded on entry and shown on the way out (throttled,
non-premium only) if at least one question was answered.

## Mode-by-mode gating summary

| Mode | On a locked lesson |
|---|---|
| Vocab List | ✅ free on every lesson |
| Flashcards | locked |
| Train | locked |
| Learn | locked |
| Challenge (every rung) | locked |

**One rule, no partial trial.** Lessons 1–`Gating.freeLessonLimit` (3) are free in
full — every mode, every rung — and the rest are locked outright. The earlier
per-mode card/page/question quotas are gone: a free user can *finish* the early
lessons, fill the ring and earn the stars, then meet the paywall carrying that
momentum instead of being cut off mid-practice. See `Gating` in `Store/Store.swift`
and `00-overview.md`.

## What's *not* in this app

No bookmarking/star ratings, no "Read All" as a separate mode (folded into
Vocab List's "Play all"), no study reminders/notifications. These were dropped
during the SwiftUI rebuild and never came back.
