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

A plain `List` of 5 `NavigationLink`s: **Vocab List, Flashcards, Learn, Quiz,
Listening**. Re-resolves the lesson from the current `Pref.translationLanguage`
on push, so switching the Meanings language mid-session and re-entering a
lesson shows the new language immediately.

## §1 Vocab List (`Lessons/VocabListView.swift`)

A plain list of every entry with **Play all** in the toolbar
(`LessonPlayer` — an `AVAudioPlayerDelegate`/`AVSpeechSynthesizerDelegate` that
plays each word's bundled clip in sequence, falling back to live TTS for the 2
clip-less words, advancing 0.35s after each clip finishes). The currently
playing row auto-scrolls into view and highlights. **Always free**, even on
locked lessons — Vocab List is exempt from the trial-card gate entirely.

## §2 Flashcards (`Lessons/FlashcardView.swift`)

The shared `FlashcardScreen` (see `05-shared-and-audio.md`) over the lesson's
`Vocab` entries: kana(+kanji) face, reveal → translation + romaji. Subject to
the lesson's trial-card limit (`Gating.trialLimit`) when locked.

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
- **Gating**: `reachedLimit` counts pages viewed (`viewed`), not correct
  answers — on a locked lesson past `Gating.freeTrialCards` pages, further
  paging is blocked (`CardPager.canPage`) and a paywall sheet opens instead.

## §4 Quiz (`Lessons/QuizView.swift`) and §4b Listening

One `QuizModel` covers both — Listening is `QuizView(from: .audio)`, not a
separate screen.

- **Forms**: `VForm` = `kana`/`kanji`/`romaji`/`translation`/`audio`. `audio`
  can only be a *prompt* (`VForm.answerForms` excludes it — you can't have an
  audio-clip answer *option*). `cycleFrom()`/`cycleTo()` cycle through the
  valid forms for each side, always skipping whatever the other side currently
  holds so prompt and answer never coincide.
- **Question generation**: pick a random vocab as the answer; fill to 4
  options with random lesson vocab, deduped by `kana` (not `id`/`romaji`) so
  visually-identical readings never appear twice; shuffle.
- **Listening's pool**: filtered to `entries` that actually have a bundled
  `audio` clip when there are ≥4 of them (falls back to the full lesson
  otherwise) — so the Listening prompt is never silently a TTS-only word if
  clip coverage allows avoiding it.
- **Audio-safety rule** (`QuizModel.promptAudioSafe`): auto-playing the
  prompt's pronunciation is safe for any prompt form *except* `.translation`
  — hearing the word would give away the answer when the options are the
  written word itself. Listening mode always plays regardless (the audio IS
  the question).
- **Gating**: `model.total` (questions answered, not just viewed) drives the
  trial limit on locked lessons; hitting it opens the paywall. A popup
  interstitial ad is preloaded on entry and shown (throttled, non-premium
  only) on leaving the screen if at least one question was answered.

## Mode-by-mode gating summary

| Mode | Free everywhere? |
|---|---|
| Vocab List | ✅ always |
| Flashcards | 5-card trial past lesson 5 |
| Learn | 5-page trial past lesson 5 |
| Quiz | 5-question trial past lesson 5 |
| Listening | 5-question trial past lesson 5 |

Lessons 1–5 have no gate on any mode. See `Gating` in `Store/Store.swift` and
`00-overview.md`.

## What's *not* in this app

No bookmarking/star ratings, no "Read All" as a separate mode (folded into
Vocab List's "Play all"), no study reminders/notifications. These were dropped
during the SwiftUI rebuild and never came back.
