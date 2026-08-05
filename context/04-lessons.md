# 04 — Lessons tab (the core study engine)

Reference source (`reference-rn/app/containers/lessons/`):
- `index.js` — browser + fuzzy search
- `select-mode.js` — mode picker
- `vocab-list.js` — mode 1
- `assessment.js` — mode 2 (Learn / tile reconstruction)
- `assessment-mc.js` — mode 3 (Quiz / multiple choice)
- `assessment-listening.js` — mode 4 (Listening)
- `read-all.js` — mode 5 (Read All)
- `components/lesson-item.js`, `components/mode-item.js`

Shared display: `reference-rn/app/components/card.js` +
`card-option-selector.js` (see `05-shared-and-audio.md`).

> Note: gating (`FIRST_FREE_LESSONS = 3`, premium checks in `select-mode.js` ~L89)
> is **out of scope** — in the rebuild **all lessons and all modes are open**.
> Ignore every `isRequirePremium` / `gotoLockFeature` branch.

## Browser (`index.js`)

### Lesson groups (~L85)

4 paged groups via `IndicatorViewPager`:

| Group | Lessons |
|---|---|
| Beginning 1 | 1–13 |
| Beginning 2 | 14–25 |
| Advanced 1 | 26–38 |
| Advanced 2 | 39–50 |

Each group is a `FlatList` of `LessonItem`; tapping one navigates to `select-mode`
with `{ lesson }` (`lesson-item.js` → `select-mode.js` ~L133).

### Fuzzy search (Fuse.js, ~L24)

Config: `threshold 0.18`, `location 0`, `distance 100`, `maxPatternLength 32`,
`minMatchCharLength 1`, `keys: ['kanji','kana','romaji','translation']`, over the
flat `vocabs` array (all 2089 items). When the search box has text, results replace
the group grid with a `FlatList` of `VocabItem`s, each showing its **lesson number**
(`isShowLesson` ~L181).

### SwiftUI target

- `LessonListView`: a paged `TabView` (4 pages) or a single `List` with 4 `Section`s
  — sections are simpler and more idiomatic; the paging is cosmetic.
- `.searchable` bound to a query; when non-empty show a flat filtered list of `Vocab`
  with lesson badges.
- **Search port:** Fuse.js is fuzzy/typo-tolerant. Two options:
  1. v1 simple: `localizedCaseInsensitiveContains` across the 4 fields, ranked by
     match position (good enough, zero deps).
  2. faithful: a small fuzzy scorer approximating threshold 0.18. Recommend v1
     simple first; note the difference so it's a conscious downgrade.

```swift
func search(_ q: String, in all: [Vocab]) -> [Vocab] {
    guard !q.isEmpty else { return [] }
    let n = q.lowercased()
    return all.filter {
        [$0.kanji, $0.kana, $0.romaji, $0.translation]
            .contains { $0.lowercased().contains(n) }
    }
}
```

## Select-mode (`select-mode.js`)

5 buttons → navigation targets (ignore gating):

| Mode | Route | Doc §|
|---|---|---|
| Vocab List | `vocab-list` (~L133) | §1 |
| Learn | `assessment` (~L109) | §2 |
| Quiz | `assessment-mc` (~L145) | §3 |
| Listening | `assessment-listening` (~L152) | §4 |
| Read All | `read-all` (~L159) | §5 |

SwiftUI: `SelectModeView` = a `List`/grid of 5 `NavigationLink`s carrying the
`Lesson`. Model the 5 modes as an enum with a `destination`.

---

## §1 Vocab List (`vocab-list.js`)

- Loads `vocabularies[lesson].data` (~L91), renders each as a `VocabItem` in a
  `FlatList`.
- Row: left = kana + kanji (if kanji ≠ kana); right = translation + index.
- Tap row → speak (`vocab-item.js` ~L66) → routes to `Pronouncer` (no-op v1).

**SwiftUI:** `VocabListView(lesson:)` → `List(VocabStore.lesson(n))` of `VocabRow`.
Trivial.

---

## §2 Learn — tile reconstruction (`assessment.js`) ⭐ signature mode

The learner rebuilds a word's kana by tapping character tiles in order.

### Constants
`NO_OF_TILES = 5` (~L53), `SHOW_AFTER_NUMBER = 8` (~L54, drives a rating modal —
**drop**, ratings are out of scope).

### Tile generation — `getTiles()` (~L231)

1. `cleanKana = cleanWord(item.kana)` (~L245).
2. Distractor count: `length = NO_OF_TILES*2 - cleanKana.length` (= `10 - len`); if
   `< 0`, `length = NO_OF_TILES*3 - cleanKana.length` (= `15 - len`, ~L251); if
   **still `< 0`, bail** → `tiles = []` and return (~L255).
3. Pick distractor chars from the **flat kana pool** matching the word's script —
   `getRandom(hiragana, length)` or `getRandom(katakana, length)`, chosen by whether
   the first char of `cleanKana` is in the hiragana pool (~L261; pools are
   `utils/kana.js` `hiragana`/`katakana`, **74 entries each**).
4. `tiles = [...distractors, ...cleanKana.split('')]` then **Fisher-Yates shuffle**
   (~L262,267). The target chars are always included, so the answer is always
   buildable; the pool only supplies distractors.
   - `getRandom` (~L152) throws if `length > pool.size`. **Verified safe:** max
     `length` requested across all 2089 words is 9 (a 1-char word) ≪ 74, so it never
     throws.

> **Verified pre-flight (simulated over all 2089 words):** no crashes, no empty-clean
> kana. **Exactly one entry bails** (empty tiles): lesson 14
> `しんごうをみぎへまがってください` (clean length 16 > 15) — it's really a sentence, not a
> word. Decide: either replicate RN's graceful "no tiles" bail (show the card, skip
> the tile game for that item) **or** filter sentence-length entries out of Learn.
> Recommend: skip-with-message; don't crash.

### Answer checking — tile tap (~L439)

- Append tapped char to `answers`; max length = `cleanKana.length` (~L440).
- **Correct** when `answers.join('') === cleanKana` (~L446).
- **Wrong** the instant `!cleanKana.startsWith(answers.join(''))` (prefix check,
  ~L453) — i.e. the first out-of-order tap fails immediately.

### Card / display

Uses the shared `Card` + `CardOptionSelector` with toggles `isKanjiShown`,
`isKanaShown`, `isRomajiShown`, `isTranslationShown`, `isSoundOn`, `isOrdered`
(persisted, see `05`). The card shows the live assembled answer over the kana slots,
plus correct/incorrect icons.

### Navigation (~L470)

- `isOrdered = true`: Previous / Next through the lesson in order + reveal button.
- `isOrdered = false`: single **Random** button (jump to a random item) + reveal.

### SwiftUI target

`LearnView` + `@Observable LearnModel`:

```swift
@Observable final class LearnModel {
    let vocab: [Vocab]
    var index = 0
    var tiles: [Character] = []          // shuffled pool
    var answer: [Character] = []         // taps so far
    var state: AnswerState = .inProgress // .correct / .wrong

    func loadTiles() { /* getTiles(): clean kana, size pool, draw from
                          KanaTable.hiraganaFlat / katakanaFlat, shuffle */ }
    func tap(_ c: Character) {
        answer.append(c)
        let built = String(answer), target = cleanWord(vocab[index].kana)
        if built == target { state = .correct }
        else if !target.hasPrefix(built) { state = .wrong }
    }
    func next() / previous() / random()  // honor `isOrdered`
}
```

Tiles = `LazyVGrid` of tappable `TileView`s. Needs `KanaTable.hiraganaFlat` /
`katakanaFlat` (the flat pools from `utils/kana.js`) as distractor sources. Drop the
`SHOW_AFTER_NUMBER` rating modal.

---

## §3 Quiz — multiple choice (`assessment-mc.js`)

### Forms (~L111,147)
`modeAll = ['kana','kanji','romaji','translation']`. Defaults `modeFrom='kana'`,
`modeTo='translation'`. `nextModeFrom`/`nextModeTo` (~L192,197) cycle through
`modeAll` via `getNextMode` (~L93), which **skips the value currently used by the
other side** so question and answer forms never coincide.

### Question generation — `getNext()` (~L161)
1. Random vocab from the lesson = the question (~L170).
2. Start `choices = [correct]`; add random lesson vocab until 4, deduping by `kana`
   (`choices.filter { $0.kana === temp.kana }.length === 0`, ~L174).
3. Shuffle `choices` (~L182). → **4 options**.

Display resolves `translation` via i18n when a side is `translation`; otherwise the
raw field (~L245).

### Scoring — `checkAnswer()` (~L202)
`correctAnswer === userAnswer` → `correctNumber += 1` else only `total += 1`. Header
`correctNumber / total` (~L124). Correct border green `#2ECC40`, wrong pick red
`#FF4136`, disabled after pick until Next.

### SwiftUI target
`QuizView` + `@Observable QuizModel`. `Form` enum `{ kana, kanji, romaji,
translation }` with a `value(of: Vocab) -> String`. `nextMode` cycles skipping the
other side. 2×2 option grid, same green/red + lock-until-Next as Kana quiz. Score is
session state.

---

## §4 Listening (`assessment-listening.js`)

Identical distractor generation + scoring as §3. Differences:
- The question is **not shown as text** — it's a big play icon `ios-play` (80px,
  ~L296); tapping the card speaks the word (~L289).
- `modeFrom` is fixed to "Listening"; only `modeTo` cycles the four forms (~L279).

**SwiftUI:** reuse `QuizModel` with `from == nil` (listening); the prompt cell is a
speaker button calling `pronouncer.speak(question)`. **Because audio is deferred,
this mode is non-functional in v1** — build the UI but gate it, or defer the whole
mode until the `Pronouncer` is real. Note this explicitly to the user.

---

## §5 Read All (`read-all.js`)

Hands-free playback of the whole lesson.
- TTS setup rate 0.4, lang `ja`, ducking (~L25).
- `read()` (~L148) loops every vocab: speak cleaned kana, then the translation in the
  voice locale (or a pause), sequentially.
- Advances on the `tts-finish` event (~L106,135); updates `count/total`; **auto-closes
  3s after the last word** (~L131).
- Single tap toggles pause/resume (`isReading` ~L191); play/pause icon (~L201);
  shows current kana + romaji + translation (~L195).

**SwiftUI:** `ReadAllView` + `@Observable ReadAllModel` driving an
`AVSpeechSynthesizerDelegate`-style "speak next on finish" loop. **Depends entirely
on audio** → deferred with the `Pronouncer`. Build UI + progress; wire the loop when
audio lands.

---

## Star rating — DROPPED

`components/save-vocab.js` / `rating.js` and the `lessons.assessment.{romaji}` store
are **out of scope**. Where `Card` renders `SaveVocab` (`card.js` ~L273), omit it.

## Mode-by-mode audio dependency (v1)

| Mode | Works in v1 without audio? |
|---|---|
| Vocab List | ✅ (tap-to-speak is a no-op) |
| Learn | ✅ |
| Quiz (MC) | ✅ |
| Listening | ❌ needs audio — defer/gate |
| Read All | ❌ needs audio — defer/gate |

So **v1 = Vocab List + Learn + Quiz** fully working; Listening + Read All land with
the `Pronouncer`.
