# 03 — Kana tab

Everything under the Kana tab is **always free** — there is no premium gating
anywhere in this feature (contrast with Lessons, `04-lessons.md`).

## Browser (`nihongo/Kana/KanaBrowserView.swift`)

A segmented `Picker` over `KanaTable.allCases` (`.seion`/`.dakuon`/`.youon`,
labeled **Basic / Voiced / Combos**) with the selected table's grid below.

- **Grid shape**: Basic and Voiced render as **square** tiles; Combos (拗音,
  only 3 columns wide) deliberately render **non-square** (`KanaGrid(square:)`)
  — forcing 3-wide rows into squares would make each tile huge and
  out-of-proportion with the other two tables. Tile size is computed
  explicitly from the measured row width (`onGeometryChange`) rather than via
  `.aspectRatio`, because `.aspectRatio(1, .fit)` inside a flexible `HStack`
  doesn't reliably divide space into even squares across cells.
- **What's "big" on each tile** is a 3-way toggle (hiragana / katakana /
  romaji), stored in `Pref.kanaTileScript` and exposed as a compact toolbar
  menu (a glyph button showing あ/ア/A) rather than a second segmented row —
  two stacked segmented controls looked cluttered.
- **Mastery coloring**: each tile borders green/red/neutral from the learner's
  most recent `KanaResult` for that romaji (`Theme.correct`/`.wrong`/`.line`).
  A trash-can toolbar button (disabled when there are no results) opens a
  confirmation dialog to wipe all `KanaResult` rows and reset every tile.
- Tapping a tile speaks it (`pronouncer.speak(kana:)`) and logs `play_kana`.

## Choosing a quiz mode (`KanaQuizModeView`)

Five modes, all operating over whichever table (`KanaTable`) was showing in
the browser:

| Mode | View | Mechanic |
|---|---|---|
| Flashcards | `KanaFlashcardView` | Shared `FlashcardScreen` — swipe right if you know it |
| Classic | `KanaQuizView` | Tap 1 of 4 options |
| Swipe | `KanaSwipeQuizView` | Tinder-style: swipe left/right between 2 options |
| Listening | `KanaQuizView(listening: true)` | Same as Classic, but the prompt is audio, not a glyph |
| Write | `KanaWriteView` | Hear it, draw it — freehand scored against the target glyph |

### Classic / Listening — `KanaQuizModel`

Any-form→any-form multiple choice, same shape as the RN original: `from`/`to`/
`other` (`KForm`: hiragana/katakana/romaji) with `swapFrom()`/`swapTo()`
exchanging the active side with the reserve. `next()` picks a random answer
plus up to `optionCount - 1` distinct-romaji distractors from the pool,
shuffled. `choose(_:context:)` locks the pick, updates the session
correct/total, and calls `KanaResult.record` unconditionally (right or wrong).

Listening mode reuses the exact same model with `listening: true`: the
direction-toggle row collapses to a static speaker icon (no `swapFrom`, since
the prompt form is fixed to "hear it"), and `autoPlay()` always speaks
regardless of the global sound toggle — **in Listening, the sound IS the
question, so the toggle can't silence it.** Classic mode respects the sound
toggle for its optional auto-play. Either way, tapping the prompt card always
replays audio.

### Swipe — `KanaSwipeQuizView`

`KanaQuizModel(optionCount: 2)` — same model, just 2 options instead of 4. The
prompt card sits over a static `CardStackPeek()` backdrop (decorative — it
never moves) and is the only draggable element. Dragging past a 90pt threshold
in either direction commits that side's option; a `SwipeStamp` (arrow +
colored border) previews which way you're about to commit as you drag, scaled
by how far past the threshold you are. On decide, the card flings off-screen,
a correct/wrong badge flashes for 0.5s, then the next question loads and
auto-plays.

### Write (`KanaWriteView` + `KanaSketch`)

The one Kana mode with real scoring logic, not just multiple choice.

- Learner picks Hiragana/Katakana via a segmented control, sees the romaji
  prompt, and draws freehand in a `Canvas` over an optional translucent
  stroke-order template (toggle with **Reveal**).
- **Template**: rendered from the bundled **KanjiStrokeOrders** font — the
  same shape shown as guidance is also the scoring template, so it has to be
  scoring-clean. That font bakes small numbered stroke-order digits into every
  glyph; `KanaSketch.stripTinyComponents` erases them via connected-component
  analysis (any blob smaller than `maxDim` in both axes is assumed to be a
  digit, not ink — calibrated against the font's actual digit size) before
  either display or scoring.
- **Scoring** (`KanaSketch.matchScore`): strokes are rasterized into a 48×48
  boolean grid, stretched per-axis to normalize away position/scale/aspect,
  then compared against the target glyph rendered in **5 template fonts**
  (the stroke-order font plus print/rounded/textbook faces — 教科書体
  YuKyokasho/Klee — so both printed and handwritten letterforms count as a
  good match) using the **best (lowest-distance) match across all 5**. The
  distance metric is symmetric **chamfer distance** (mean distance from each
  shape's ink to the other's nearest ink — tolerant of wobble) plus a
  **zone-density term** (6×6 region ink-mass histogram L1 difference) because
  chamfer alone under-punishes a missing stroke (e.g. に vs ロ can look close
  on chamfer alone). The raw distance maps to a 0–100 score via a curve tuned
  so a faithful trace lands mid-90s and a correct-but-wobbly freehand attempt
  lands 70s–80s.
- **Stroke-count penalty**: drawing the wrong number of strokes costs 10
  points per stroke of difference inside `matchScore` (shape matching alone
  can't distinguish a one-swipe scribble from a properly multi-stroke glyph).
  Separately, on **Next**, grading (`KanaWriteView.grade()`) is a hard
  pass/fail: the stroke count must match the textbook count from
  `KanaChart.json` **exactly** (when known) *and* the shape score must clear
  `passScore = 80` — chosen because that's exactly where the score curve
  turns green, so the pass/fail verdict and the visual feedback color always
  agree. A pass upserts `KanaResult` and feeds the same green/red browser tile
  coloring as every other quiz mode.
- Score/stroke feedback is deliberately **wordless** (no localized strings) —
  just an icon + percentage + `drawn/expected` stroke counter — so it needs no
  translation.

## `ScoreBadge` / `SoundToggle` / `OptionGrid`

Shared across every quiz screen (Kana and Lessons alike) — see
`05-shared-and-audio.md`.
