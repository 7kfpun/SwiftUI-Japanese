# 03 — Kana tab (reference + quiz)

Reference source:
- `reference-rn/app/containers/kana/index.js` — browser
- `reference-rn/app/containers/kana/assessment.js` — quiz
- `reference-rn/app/containers/kana/components/tile.js` — tile
- `reference-rn/app/utils/kana.js` — data tables

## Data (`utils/kana.js`)

Each entry is a 3-tuple **`[hiragana, katakana, romaji]`**, e.g. `['あ','ア','a']`.
Three grouped tables (`exports.seion` ~L92, `exports.dakuon` ~L168, `exports.youon`
~L206), each an array of rows:

| Table | Meaning | Rows | Real entries | Notes |
|---|---|---|---|---|
| `seion` 清音 | basic | 11 | **46** ✓ | uses `['','','']` placeholders for grid alignment; lone `['ん','ン','n']` last |
| `dakuon` 濁音 | voiced | 5 | **25** ✓ | all rows are 5-wide |
| `youon` 拗音 | combos | 11 | **33** ✓ | mostly 3-wide rows |

(Non-empty counts **verified** against `utils/kana.js`: 46 / 25 / 33 — use these as the
transcription checksum.)

`utils/kana.js` also exports flat `exports.hiragana` (~L1) and `exports.katakana`
(~L264) arrays — **74 entries each** (verified) — these are the distractor pools used
by the **Lessons → Learn** tile mode, not the Kana tab (see `04-lessons.md`). Note
they do **not** include small kana (っ ャ ッ ォ ィ), the chōonpu (ー), or the
punctuation/full-width chars that appear in some words, so distractors never contain
those — but target words still do (targets are added separately). **Transcribe both
flat pools verbatim** (all 74 each) to preserve distractor behavior.

### Swift port of the data

Keep the exact tuple + placeholder structure so the grid lays out identically.

```swift
struct Kana: Hashable, Identifiable {
    let hiragana: String
    let katakana: String
    let romaji: String
    var id: String { romaji.isEmpty ? UUID().uuidString : romaji }
    var isEmpty: Bool { romaji.isEmpty }          // grid placeholder
}

enum KanaTable: String, CaseIterable, Identifiable {
    case seion, dakuon, youon
    var id: String { rawValue }
    var title: String { ... }                     // 清音 / 濁音 / 拗音 labels
    var rows: [[Kana]] { ... }                    // transcribe from utils/kana.js
}
```

Transcribe the three tables verbatim from `utils/kana.js` (a mechanical copy — ~104
non-empty cells total). Preserve `['','','']` as `Kana(hiragana:"",katakana:"",
romaji:"")` so the grid keeps its shape.

## Browser (`kana/index.js`)

- 3 pages in an `IndicatorViewPager` (rn-viewpager): Seion / Dakuon / Youon, chosen
  by a top tab indicator (`PagerTabIndicator` ~L147; `onPageSelected` ~L140).
- Each page is a `ScrollView` of rows (`assessment.kana.map` ~L179), each row
  `flexDirection:'row'`, space-between.
- **Tile** (`components/tile.js` ~L87): hiragana big on top (26px), katakana + romaji
  small below. Tapping a tile speaks the hiragana (~L100). Tile width =
  `width / itemsPerRow - 10`.
- **History coloring:** on mount each tile reads `kana.assessment.{romaji}` (~L71)
  and borders itself **green** if last quiz answer was correct, **red** if wrong,
  white/none if never tested (~L89).

### SwiftUI target

- `KanaBrowserView`: a **segmented `Picker`** (`.pickerStyle(.segmented)`) over
  `KanaTable.allCases` (清音 / 濁音 / 拗音) at the top, with the selected table's grid
  below. (Decided over a paged `TabView` — see `07-ux-ui.md`; segmented shows all
  labels, allows random access, and is VoiceOver-correct.)
- The grid: `LazyVGrid` (or rows of `HStack`) of `KanaTileView`. Empty cells render as
  invisible spacers to preserve the あいうえお alignment.
- `KanaTileView`: VStack(hiragana / HStack(katakana, romaji)); border via
  `.overlay(RoundedRectangle().stroke(...))` colored by the stored `KanaResult` (see
  below); tap → `pronouncer.speak(...)` (no-op in v1, per tap-anywhere-to-hear).

## Quiz (`kana/assessment.js`)

The distinctive mechanic: **any-form → any-form** multiple choice.

### Direction state (~L101)

Three slots: `modeFrom` (question form), `modeTo` (answer form), `modeOther` (the
form held in reserve). Defaults: `hiragana → romaji`, reserve `katakana`. The
form→tuple-index map is `{hiragana:0, katakana:1, romaji:2}` (~L211).

- **swapModeFrom** (~L159): exchange `modeFrom ↔ modeOther` (toggles the question
  between hiragana/katakana).
- **swapModeTo** (~L164): exchange `modeTo ↔ modeOther` (toggles the answer form).

Tapping the question label calls swapModeFrom; tapping the answer label calls
swapModeTo. So the learner can drill hiragana→romaji, katakana→romaji,
hiragana→katakana, etc.

### Question generation — `getNext()` (~L119)

1. Pick a random non-empty origin tuple: `choice(choice(kana))`, reroll while
   `origin[0] === ''` (skip placeholders).
2. Build **3 distractors**: random tuples where `origin[0] !== temp[0]` and
   `temp[0] !== ''` (distinct, non-empty).
3. Insert the correct origin at a random slot: `choices.splice(randomInt(4), 0,
   origin)` → **4 options**.
4. Reset `isCorrect=null`, `answerPosition=-1`.

`question = origin[idx(modeFrom)]`, `rightAnswer = origin[idx(modeTo)]`,
`answers = choices.map { $0[idx(modeTo)] }` (~L216).

### Scoring & feedback — `checkAnswer()` (~L169)

- Compare `rightAnswer === userAnswer`.
- Correct → `correctNumber += 1`; wrong → unchanged. `total += 1` always. Header
  shows `correctNumber / total`.
- Persist **every** answer: `kana.assessment.{origin.romaji}` = `true|false` and
  `kana.assessment.{origin.romaji}.timestamp` = `floor(Date.now()/1000)` (~L185,199).
- Colors: correct option border **green `#2ECC40`**; the user's wrong pick border
  **red `#FF4136`**; others white. Options disabled after answering until **Next**
  (`disabled = answerPosition !== -1`).

### SwiftUI target

`KanaQuizView` + `@Observable KanaQuizModel`:

```swift
enum KanaForm: Int { case hiragana = 0, katakana = 1, romaji = 2 }

@Observable final class KanaQuizModel {
    var from: KanaForm = .hiragana
    var to:   KanaForm = .romaji
    var other: KanaForm = .katakana
    private(set) var options: [Kana] = []
    private(set) var answer: Kana!
    private(set) var picked: Int? = nil
    private(set) var correct = 0, total = 0

    func swapFrom()  { swap(&from, &other) }
    func swapTo()    { swap(&to, &other) }
    func next() { /* getNext(): pick answer + 3 distractors, insert at random slot */ }
    func choose(_ i: Int, into ctx: ModelContext) { /* checkAnswer + record */ }
}
```

- 2×2 grid of option buttons; tap the question/answer headers to swap forms.
- On `choose`, compare `options[i][to] == answer[to]`, update score, upsert a
  `KanaResult`, then lock until Next.

### Persistence model (SwiftData)

Replaces the two `kana.assessment.*` keys:

```swift
@Model final class KanaResult {
    @Attribute(.unique) var romaji: String
    var isCorrect: Bool
    var timestamp: Date
    init(romaji: String, isCorrect: Bool, timestamp: Date) { ... }
}
```

The browser tile queries `KanaResult` by `romaji` to pick its border color; the quiz
upserts one on every answer. `correct/total` is per-session (view state), not
persisted — matches RN (`correctNumber`/`total` reset to 0 when entering the quiz,
`index.js` ~L107).

## Cleanup / porting notes

- RN speaks kana at rate 0.4 on tile tap; in v1 this routes to the no-op
  `Pronouncer` (audio deferred).
- The `choice`, `randomInt`, `shuffle` helpers (`utils/helpers.js`) become
  `Array.randomElement()`, `Int.random(in:)`, `Array.shuffle()` / `.shuffled()`.
