# 03 — Kana tab

Everything under the Kana tab is **always free** — there is no premium gating
anywhere in this feature, and no `Gating` call in any file under `nihongo/Kana`
(contrast with Lessons, `04-lessons.md`). That's also what the intro tour leans on:
someone who can't read kana yet lands here instead of Today (`09-intro-and-survey.md`).

## Browser (`nihongo/Kana/KanaBrowserView.swift`)

A segmented `Picker` over `KanaTable.allCases` (`.seion`/`.dakuon`/`.youon`) with the
selected table's grid below.

**The tabs are named Seion / Dakuon / Youon**, not "Basic / Voiced / Combos"
(`KanaBrowserView.swift:12`). Same treatment as Hiragana/Katakana elsewhere: romanized
in Latin scripts, transliterated or given the native term otherwise. A learner meets
these words in every other kana resource, so naming the tabs after them teaches
something — "Combos" doesn't survive contact with a textbook.

- **Grid shape**: Seion and Dakuon render as **square** tiles; Youon (拗音, only 3
  columns wide) deliberately renders **non-square** (`KanaGrid(square:)`) — forcing
  3-wide rows into squares would make each tile huge and out of proportion with the
  other two tables. Tile size is computed explicitly from the measured row width
  (`onGeometryChange`) rather than via `.aspectRatio`, because `.aspectRatio(1, .fit)`
  inside a flexible `HStack` doesn't reliably divide space into even squares across
  cells.
- **Mastery coloring**: each tile borders green/red/neutral from the learner's most
  recent `KanaResult` for that romaji (`Theme.correct`/`.wrong`/`.line`). The map is
  merged **by timestamp, not first-wins** (`KanaGrid.byRomaji`) — a CloudKit merge can
  leave duplicate rows and "the most recent answer" is this store's meaning
  (`01-data-model.md`).
- A trash-can toolbar button (disabled when there are no results) opens a confirmation
  dialog naming the row count, then wipes every `KanaResult` and resets every tile.
- Tapping a tile speaks it (`pronouncer.speak(kana:)`) and logs `play_kana`.

### The tile script is one rotating toolbar button

What each tile shows **big** is a three-way choice — hiragana / katakana / romaji —
stored in `Pref.kanaTileScript` and driven by a **single toolbar button that rotates
through the three on each tap**, showing あ / ア / A. It is not a `Menu` with a `Picker`
and not a second segmented row: there are only three mutually-exclusive values and the
button's own glyph already shows which one is active, so a dropdown spent two taps and a
covered screen saying what one tap says. (Two stacked segmented controls looked
cluttered, which is why the menu existed in the first place.)

```swift
private static let tileScripts: [(glyph: String, name: String)] = [
    ("あ", "Hiragana"), ("ア", "Katakana"), ("A", "Romaji"),
]
```

**The index order of that table is a persisted contract.** The array index *is* the
stored `Pref.kanaTileScript` value and *is* `KanaTileView.big`. Appending a fourth entry
is safe; reordering the existing three would silently rewrite every existing user's
setting into a different script. `name` reuses the three localized strings the old menu
had, so the VoiceOver label costs no new keys — sighted users read the state off the
glyph, VoiceOver needs the name.

`KanaTileView` also rotates its two small captions with `big`, so the tile always shows
all three forms: whichever two aren't the headline sit underneath in `.caption`.

### Fonts follow the content's script, at runtime

This is the rule for the whole tab, and `07-ux-ui.md` holds the authoritative
size table. The short version: **`KForm.isJapanese`** (`KanaQuizView.swift:25` —
hiragana/katakana yes, romaji no) decides the face in every switchable slot.

| Slot | Japanese | Latin (romaji) |
|---|---|---|
| Browser tile headline | `Theme.jpBold(26)` | `Theme.display(26, .semibold)` |
| The toolbar rotate button's glyph | `Theme.jpBold(15)` | `Theme.display(15, .semibold)` |
| Classic quiz prompt | `Theme.jpStrokes(120)` | `Theme.display(120)` |
| Swipe quiz prompt | `Theme.jpStrokes(150)` | `Theme.display(150)` |
| Classic quiz option text | `Theme.jpBold(26)` | `Theme.display(26, .semibold)` |
| Swipe quiz option chip | `Theme.jpBold(30)` | `Theme.display(30, .semibold)` |

Why this was a bug worth a rule: **all three Japanese faces have full Latin coverage.**
`HiraginoSans-W6` and the bundled `KanjiStrokeOrders` both have real glyphs for a–z and
0–9, so a romaji tile or a romaji prompt drawn with them came out merely *plain* — never
as tofu — which is exactly why several slots sat on the wrong face unnoticed. And this
isn't an edge case: `KanaQuizModel.to` **defaults to romaji**, so before the split every
classic quiz opened with four Latin answers set in Hiragino Sans. `KanjiStrokeOrders` is
never used for romaji at all: stroke order is the entire reason it's bundled, and Latin
letters have none. The Latin side always takes the *same point size* as the Japanese
face it alternates with, or switching script would resize the card.

## Choosing a quiz mode (`KanaQuizModeView`)

**Five modes**, all operating over whichever table (`KanaTable`) was showing in the
browser:

| Mode | View | Mechanic |
|---|---|---|
| Flashcards | `KanaFlashcardView` | Shared `FlashcardScreen` — swipe right if you know it |
| Classic | `KanaQuizView` | Tap 1 of 4 options |
| Swipe | `KanaSwipeQuizView` | Tinder-style: swipe left/right between 2 options |
| Listening | `KanaQuizView(listening: true)` | Same as Classic, but the prompt is audio, not a glyph |
| Write | `KanaWriteView` | Hear it, draw it — freehand scored against the target glyph |

Kana keeps Listening as a *mode*; on the Lessons side it became a prompt form instead
(`04-lessons.md`). The reason is asymmetry in what the prompt can give away: kana
audio can never reveal the answer, because hiragana, katakana and romaji all share one
sound, so an audio prompt is a genuinely different question rather than a variation.

### Classic / Listening — `KanaQuizModel`

Any-form→any-form multiple choice: `from`/`to`/`other` (`KForm`:
hiragana/katakana/romaji) with `swapFrom()`/`swapTo()` exchanging the active side with
the reserve. `next()` picks a random answer plus up to `optionCount - 1`
distinct-romaji distractors from the pool, shuffled. `choose(_:context:)` locks the
pick, updates the session correct/total, and calls `KanaResult.record` **unconditionally**
— right or wrong, because the browser tile's job is to show your last answer, not only
your successes.

Listening mode reuses the exact same model with `listening: true`: the direction-toggle
row collapses to a static speaker icon (there is no `swapFrom`, since the prompt form is
fixed to "hear it"), and `autoPlay()` speaks regardless of the global sound toggle —
**in Listening, the sound IS the question, so the toggle can't silence it.** Classic
mode respects the toggle for its optional auto-play. Either way, tapping the prompt card
always replays audio.

### Swipe — `KanaSwipeQuizView`

`KanaQuizModel(optionCount: 2)` — same model, just 2 options instead of 4. The prompt
sits in a shared `SwipeCard` over a static `CardStackPeek()` backdrop (decorative — it
never moves) and is the only draggable element. Dragging past a 90pt threshold in either
direction commits that side's option; the card's corner stamps (arrows, via `SwipeCard`)
fade in with the drag so they reach full strength exactly where the swipe would commit.
On decide, the card flings off-screen, a correct/wrong badge shows for 0.5s, then the
next question loads and auto-plays. Tapping a chip works too — it was the obvious thing
to try, and the chips looked tappable long before they were.

### Write (`KanaWriteView` + `KanaSketch`)

The one Kana mode with real scoring logic rather than multiple choice.

- Learner picks Hiragana/Katakana via a segmented control, sees the **romaji** prompt
  (`Theme.display(40)` — the picker above already says which script, so repeating it was
  redundant), and draws freehand in a `Canvas` over an optional translucent stroke-order
  template (toggle with **Reveal**).
- **Template**: rendered from the bundled **KanjiStrokeOrders** font — the same shape
  shown as guidance is also the scoring template, so it has to be scoring-clean. That
  font bakes small numbered stroke-order digits into every glyph;
  `KanaSketch.stripTinyComponents` erases them via connected-component analysis (any blob
  smaller than `maxDim = 6` in both axes is assumed to be a digit, not ink — calibrated
  against the font's actual digit size, with real marks like dakuten measuring ≥8×6)
  before either display or scoring. The on-screen template is pre-rendered at 640px,
  aspect-preserved so combos (ちゅ) never squish, and drawn at 60% of the canvas so it
  reads as a guide rather than a shape to fill edge-to-edge.
- **Scoring** (`KanaSketch.matchScore`): strokes are rasterized into a **48×48** boolean
  grid with a 12% margin, stretched per-axis to normalize away position/scale/aspect,
  then compared against the target glyph rendered in **5 template fonts** —
  `KanjiStrokeOrders`, `YuKyokasho-Medium`, `Klee-Medium` (教科書体, whose letterforms
  match how kana are actually handwritten), `TsukushiARoundGothic-Regular` and
  `HiraginoSans-W6` — taking the **best (lowest-distance) match across all 5**, so both
  printed and handwritten letterforms count as a good match. The metric is symmetric
  **chamfer distance** (mean distance from each shape's ink to the other's nearest ink —
  tolerant of wobble) plus **5 × a zone-density term** (6×6 region ink-mass histogram, L1
  difference) because chamfer alone under-punishes a missing stroke (に can look close to
  ロ on chamfer alone). The raw distance maps to a score as `100 − distance × 3.5`,
  clamped 0–100 — a gentle curve on purpose: a faithful trace lands mid-90s and a
  correct-but-wobbly freehand attempt lands 70s–80s, which is practice feedback rather
  than a grade.
- **Stroke-count penalty**: drawing the wrong number of strokes costs **10 points per
  stroke of difference** inside `matchScore`, because shape matching alone can't
  distinguish a one-swipe scribble from a properly multi-stroke glyph.
- **Grading is separate from scoring, and happens on Next.** `KanaWriteView.grade()` is a
  hard pass/fail: the stroke count must match the textbook count from `KanaChart.json`
  **exactly** (when known) *and* the score must clear `passScore = 80` — chosen because
  that's exactly where the score row turns green, so the verdict and the visual feedback
  always agree, and because it's the same bar the Challenge ladder uses. Grading once per
  kana (rather than per stroke) is why the low scores midway through a multi-stroke glyph
  never count as misses; an undrawn, skipped kana isn't graded at all. A pass upserts
  `KanaResult` and feeds the same green/red browser tile coloring as every other mode.
- Score/stroke feedback is deliberately **wordless** — an icon, a percentage and a
  `drawn/expected` counter — so it needs no translation. Too *few* strokes stays neutral
  rather than red: it may just mean "not finished".
- All the CoreGraphics work is off the main thread (`Task.detached`), and a stale
  in-flight template render is discarded by comparing the glyph it was started for.

## Shared chrome

`ScoreBadge`, `SoundToggle`, `OptionGrid`/`QuizOptionButton`, `SwipeCard`,
`SwipeOptionChip`, `CardStackPeek` and `FlashcardScreen` are all shared with the Lessons
side — see `05-shared-and-audio.md`. That sharing is the reason Kana Flashcards and
Lessons Flashcards behave identically: they are the same generic screen over `K` and
`Vocab`.

## What's deliberately not here

- **No kana writing practice for kanji**, and no kanji anywhere in this tab.
- **No stroke-order animation.** The template is a static shape with its numbers
  stripped; the numbers are absorbed instead through `jpStrokes` on the *quiz* prompts.
- **No per-kana statistics screen.** The tile colours are the whole progress UI — "memory
  in the UI" rather than a dashboard (`07-ux-ui.md`).
