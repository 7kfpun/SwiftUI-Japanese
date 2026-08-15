# 04 — Lessons tab

The core study engine: 50 Minna no Nihongo lessons. Each lesson offers **four
untested practice modes** — Vocab List, Flashcards, Train, Learn — **plus the scored
Challenge ladder**, which is the only thing that records a result. The ladder has its
own doc (`02-challenge-ladder.md`); this one covers everything around it.

## Browser (`nihongo/Lessons/LessonListView.swift`)

- **No search text**: a segmented `Picker` over 4 fixed groups — Beginning 1
  (1–13), Beginning 2 (14–25), Advanced 1 (26–38), Advanced 2 (39–50) — above a
  `List` of lesson-number rows for the selected group.
- **With search text**: the group picker disappears and the list becomes a
  flat, lesson-tagged result list from `searchVocab(_:in:)` (simple
  case-insensitive `contains` across kanji/kana/romaji/translation — see
  `01-data-model.md`). Input is debounced 600ms before logging a
  `search_vocab` analytics event; the filtering itself is synchronous.
- **Each row carries a slim challenge progress bar**, not a ring: passed rungs over the
  lesson's rung count. It sits on the list you see most rather than one level in,
  because the bar is the reason to come back. Untouched lessons show **no bar at all** —
  an empty track on all 50 rows would read as "nothing works" rather than "nothing
  started" — and the bar has a fixed width so the bars line up down the list instead of
  jittering with each row's title length.
- The counts come from **one** `ChallengeResult` fetch per appear
  (`reloadProgress`), tallied per lesson, collapsing duplicate rows by rung first — a
  CloudKit merge can leave two rows for one rung and counting both would overfill the
  bar. Refreshing on appear is what makes the bar update behind you when you finish a
  rung and navigate back.
- **The navigation stack lives on `Router`**, not in the view, so the widget's
  "Ready for Challenge N?" link can push a lesson into a tab the user isn't on. Row taps
  append to the same path, so a deep link and a tap leave the user in the same place with
  a working back button either way.
- `VocabRow` (also reused by search results, `VocabListView` and `BookmarksView`) shows
  kana/kanji on the left, translation (+ `L<n>` badge when `showLesson`) in the middle,
  and a fixed 28pt trailing column holding the speaker over the bookmark star; tapping
  the row or the speaker speaks the word and logs `play_vocab`.
- **The star is a sibling in that column, never an overlay.** It was
  `.overlay(alignment: .topTrailing)`, which takes no layout space, so its position
  followed the row's height: a two-line row (kanji shown) left it hovering above the
  speaker and a one-line row put it straight on top. It is also **one glyph plus a
  numeral** (`★2`), not one glyph per tier — three repeated stars is a variable-width
  control, and in a list that means nothing lines up. Both are separate buttons: tapping
  a star must never also play audio. It uses `.buttonStyle(.plain)` deliberately: the default style tints the
  whole label with the accent colour and beats a `.foregroundStyle(.primary)` applied
  inside, so only the style change keeps the vocabulary reading as text rather than as a
  link.

## Select-mode (`SelectModeView`)

Two sections, and the split is the point: a **Learn** section of four untested
practice modes you can wander through — **Vocab List, Flashcards, Train, Learn**,
ordered shallow → deep — then a **Challenge** section listing the lesson's rungs,
which are scored and gate each other. Its header carries `passedCount /
challengeCount`.

Re-resolves the lesson from the current `Pref.translationLanguage` on push, so
switching the Meanings language mid-session and re-entering a lesson shows the new
language immediately.

**This is the one place lesson gating is enforced for the practice modes and the
ladder** — a locked row opens the paywall instead of navigating, so no practice screen
has to police access itself. (`VocabListView` is the only other enforcement point, and
only for reading meanings aloud — see `06-monetization.md`.)

On a **free** lesson the Challenge section's footer also carries the earned unlock: the
offer, a progress bar and an `n / m three-starred` count. It is hidden once won, for
subscribers, and on locked lessons — where it would read as a taunt rather than an
offer.

## §1 Vocab List (`Lessons/VocabListView.swift`)

A plain list of every entry with **Play all** in the toolbar
(`LessonPlayer` — an `AVAudioPlayerDelegate`/`AVSpeechSynthesizerDelegate` that
plays each word's bundled clip in sequence, falling back to live TTS for the 2
clip-less words, advancing 0.35s after each clip finishes). It shares the *policy* —
which clip, which voice, what rate — with `AudioPronouncer` through `Speech`, and adds
only the delegate it needs to know when to advance (`05-shared-and-audio.md`). The
currently playing row auto-scrolls into view and highlights, and playback stops on
`onDisappear`. **Always free**, even on locked lessons — it's the one mode exempt from
gating, so browsing and search never lock.

## §2 Flashcards (`Lessons/FlashcardView.swift`)

The shared `FlashcardScreen` (see `05-shared-and-audio.md`) over the lesson's
`Vocab` entries: kana(+kanji) face, reveal → translation + romaji, swipe right to retire
a card and left to send it to the back of the deck. Locked entirely on a premium lesson —
there is no partial trial, and `FlashcardScreen` no longer takes a trial-limit parameter
at all.

## §3 Train — endless 50/50 practice (`Lessons/TrainView.swift`)

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
- An interstitial ad is preloaded on entry and shown on the way out (throttled,
  non-premium only) if at least one question was answered.

## §4 Learn — tile reconstruction (`Lessons/LearnView.swift`) — signature mode

The learner rebuilds a word's kana reading by tapping shuffled character
tiles in order. It's last in the section because it's the deepest ask short of the
ladder: producing a reading from nothing rather than choosing between options.

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
  target's own characters so the correct answer is always buildable
  (`LearnTests.tileGenerationNeverCrashesAndKeepsAnswerBuildable` checks that on every
  entry of all 50 lessons).
- **Answer checking** (`LearnModel.tap`): append the tapped character; correct
  the instant the built string equals the target, **wrong the instant it's no
  longer a prefix of the target** — an out-of-order tap fails immediately
  rather than waiting for the full length. A wrong state disables the grid and
  surfaces a Clear button.
- **Card display**: `CardOptionsBar` toggles (kanji/kana/romaji/translation/
  sound, `@AppStorage`-backed) control what's shown around the assembled
  answer; a correct/wrong icon overlays once the state resolves. The assembled
  reading shrinks rather than wrapping (`Theme.jp(52)`, floor 0.35), because entries run
  to 15 characters and a fixed size that fits those would be tiny for the common short
  ones.
- **Navigation**: an Ordered/Random segmented control, persisted in `Pref.ordered` and
  defaulting to **ordered** — the opposite of Train's `Pref.trainOrdered`, which is why
  they're two keys. Ordered pages sequentially with swipe-to-turn (`CardPager` — see
  `05`); Random has a single shuffle button that drives the *same* animation through
  `CardPager`'s `fling` binding. Either way, paging speaks the new word explicitly in the
  page-turn handler (not via `.onChange(of: index)`, since a random jump can land on the
  same index and would silently skip the announcement).
- The tile grid computes an explicit square size from its measured width, the same
  measure-then-divide pattern as the Kana browser tiles (`07-ux-ui.md`).

## §5 The Challenge ladder

The scored half of a lesson, and the app's core loop — **fully documented in
`02-challenge-ladder.md`**. The short version: rungs of `questionsPerChallenge` (10)
questions, `passScore` (80%) to pass, 1–3 stars by score, and rung *N* unlocks only once
*N−1* is passed (`ChallengeResult.isUnlocked`). Prompt/answer pairs harden by rung —
recognition at 1, recall from 2, audio-with-no-visual-cue from 3 (`Challenge.forms`).
Only *best* results are kept, so a retry can raise a score but never lower it.

`SelectModeView` renders the rungs and distinguishes **two kinds of lock**, on purpose,
because only one of them is something the user can fix by paying
(`ChallengeRowState`): `.sequential` names the concrete rung that blocks it ("Beat
Challenge 2 to unlock"), while `.premium` opens the paywall and logs `locked_challenge`.
An unattempted-but-open rung shows its number and three empty stars — no padlock.

## Mode-by-mode gating summary

| Mode | On a locked lesson |
|---|---|
| Vocab List | ✅ free on every lesson |
| Flashcards | locked |
| Train | locked |
| Learn | locked |
| Challenge (every rung) | locked |

**One whole-lesson rule.** Lessons 1–`Gating.freeLessonLimit` (5) are free in full —
every mode, every rung — and the rest are locked outright. The earlier per-mode
card/page/question quotas are gone: a free user can *finish* the early lessons, fill the
progress bar and earn the stars, then meet the paywall carrying that momentum instead of
being cut off mid-practice.

The **one** exception is Vocab List's "Play with meanings", which on a locked lesson
reads `Gating.freeMeaningPreview` (7) words and then shows the paywall. Plain "Play all"
is Japanese only and free everywhere. See `06-monetization.md` for `Gating`, the
products, the paywall and why that exception is the only one.

## What's *not* in this app

No bookmarking/star ratings, no "Read All" as a separate mode (folded into
Vocab List's "Play all"), no study reminders/notifications, and — since the rebuild
consolidated them — **no `Lessons/QuizView.swift`**: four-option multiple choice belongs
to the Challenge ladder, and Listening became `VForm.audio`, a prompt form inside
`TrainModel` and `Challenge.forms`. There is also no per-word progress record on the
Lessons side; `KanaResult` has no vocab equivalent (`01-data-model.md`).
