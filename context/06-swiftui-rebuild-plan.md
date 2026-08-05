# 06 — SwiftUI rebuild plan

Ties the analysis together into a concrete build order.

## ✅ STATUS: Phases 0–3 built, tested, and running (branch `rebuild-swiftui`)

v1 is implemented and green:
- **Data:** submodule relocated to repo-root `minna/`; `scripts/build-minna-data.py`
  compiles it to `nihongo/Resources/MinnaData.json` (single bundled file — the
  synchronized-group project flattens resource folders, so a folder reference was
  not viable). `VocabStore` loads it.
- **Kana tab:** segmented browser (清音/濁音/拗音) with quiz-history tile coloring +
  any-form→any-form quiz persisting `KanaResult` (SwiftData).
- **Lessons tab:** grouped browser + search; Vocab List, Learn (tile reconstruction),
  Quiz (MC). Listening + Read All are stubbed in select-mode ("needs audio").
- **Audio (Phase 4 done):** `AudioPronouncer` plays bundled **Kyoko** clips
  (`minna/audio/kyoko`, 2087 clips, ~75 MB) with an `AVSpeechSynthesizer` (ja-JP)
  fallback for the 2 clip-less words and for bare kana tiles. `scripts/build-minna-
  data.py` copies the clips to `nihongo/Resources/audio/<lesson>-<slug>.m4a` (flat,
  unique — synchronized groups flatten resources) and embeds the basename per entry
  in `MinnaData.json`. The audio folder is git-ignored (regenerate via the script).
- **Kana quiz modes:** Classic (4-option tap) + Swipe (Tinder-style, 2 options).
- **Shared UI:** `ScoreBadge` (one consistent right/wrong/total indicator across all
  quizzes) + `QuizOptionButton`/`OptionGrid` (full-height 2×2). Kana browser has a
  "clear all learned" (trash) button.
- **Tests:** 21 unit tests (`nihongoTests`) + 3 UI smoke flows (`nihongoUITests`) pass.
- **Toolchain:** deployment target **iOS 26.5**; build/run/test on the **iPhone 17
  Pro** simulator (iOS 26.5). iPhone 15 (17.4) is *ineligible* — use an iOS 26 sim.

Remaining: **Phase 4 (audio)** → then Listening + Read All light up. The plan below
is the original; it's accurate except the data-bundling mechanism (see note in `01`).

Original starting state was the default Xcode SwiftData template
(`nihongoApp.swift`, `ContentView.swift`, `Item.swift` — now replaced/removed).

## Target app shape

A 2-tab offline study app:

```
nihongoApp
└─ RootView: TabView
   ├─ Kana     → KanaBrowserView / KanaQuizView
   └─ Lessons  → LessonListView → SelectModeView → { VocabList | Learn | Quiz | Listening* | ReadAll* }
```
`*` Listening & Read All are audio-dependent → land with the `Pronouncer` (v2).

## Proposed file layout (under `nihongo/`)

```
nihongo/
  nihongoApp.swift            # SwiftData container: [KanaResult.self]; inject Pronouncer
  RootView.swift             # TabView(Kana, Lessons)
  Models/
    VocabEntry.swift         # Codable structs (01-data-model)
    Vocab.swift              # enriched item + Lesson
    Kana.swift               # Kana tuple + KanaTable tables (transcribe utils/kana.js)
    KanaResult.swift         # @Model (SwiftData) quiz history
  Data/
    VocabStore.swift         # bundle loader + allVocab cache
    TextCleaning.swift       # cleanWord()
    Search.swift             # search(_:in:)
  Audio/
    Pronouncer.swift         # protocol + SilentPronouncer (+ SystemTTS later)
  Kana/
    KanaBrowserView.swift
    KanaTileView.swift
    KanaQuizView.swift
    KanaQuizModel.swift
  Lessons/
    LessonListView.swift
    SelectModeView.swift
    VocabListView.swift
    VocabCard.swift
    CardOptionsBar.swift
    LearnView.swift / LearnModel.swift
    QuizView.swift  / QuizModel.swift
    ListeningView.swift      # v2 (audio)
    ReadAllView.swift  / ReadAllModel.swift   # v2 (audio)
  Resources/
    minna/                   # <-- submodule, added as a FOLDER REFERENCE to the target
```

Delete the template `Item.swift` and replace `ContentView.swift` with `RootView.swift`
(update `nihongoApp.swift`'s `WindowGroup`).

## Pre-flight verification (DONE — before rebuild)

Ran against the actual `minna` submodule + vendored `kana.js`. All green except two
notes to handle in code:

| Check | Result |
|---|---|
| Total vocab entries | **2089** ✓ (matches schema) |
| Lesson files 1–50 | present, no gaps ✓ |
| `useKana` / `dictionary` counts | **32 / 284** ✓ |
| All 7 languages: key-set == vocab romaji, no empty values, no missing files | ✓ |
| JSON parses (varying indent / `\uXXXX` escapes) | ✓ (Swift `JSONDecoder` handles both) |
| `romaji` globally unique? | **NO** — 111 repeat across lessons → key `Vocab.id` on `lesson/romaji`; audio can't be named by romaji alone |
| Kana table counts (seion/dakuon/youon) | **46 / 25 / 33** ✓ (transcription checksum) |
| Flat distractor pools `hiragana`/`katakana` | **74 each** ✓ — transcribe verbatim |
| Learn `getRandom` overflow (throw risk) | **never throws** ✓ (max 9 distractors ≪ 74) |
| Learn cleaned-kana empties | **0** ✓ |
| ⚠️ Learn tile-cap overflow | **1 entry** — L14 `しんごうをみぎへまがってください` (len 16) produces empty tiles; handle gracefully (skip/label), it's a sentence not a word |

Two code TODOs fall out of this: (1) `Vocab.id = "\(lesson)/\(romaji)"`; (2) Learn
must handle the one sentence-length entry (bail with a message, don't crash). Both
are documented in `01`/`04`.

## Build order (each step compiles & runs)

**Phase 0 — data foundation**
1. Add `Resources/minna` as a **folder reference** to the app target (01-data-model
   §Xcode setup). Verify a JSON loads at runtime.
2. `VocabEntry`/`Vocab`/`Lesson` + `VocabStore` + `cleanWord`. Unit-test:
   `allVocab().count == 2089`; every `Vocab.translation` non-empty for `en`.

**Phase 1 — Lessons browse (no quiz)**
3. `LessonListView` with 4 sections + `.searchable` (simple `search`).
4. `SelectModeView`; `VocabListView` + `VocabRow` (tap = no-op speak).
   → Milestone: browse all 50 lessons and read every word offline.

**Phase 2 — the two keyboard-free quizzes**
5. `VocabCard` + `CardOptionsBar` (`@AppStorage` toggles).
6. **Learn** (`LearnModel` tile reconstruction) — the signature mode. Needs the flat
   kana pools (`Kana.swift`).
7. **Quiz/MC** (`QuizModel`, any-form→any-form, dedup-by-kana distractors).
   → Milestone: Lessons fully usable minus audio modes.

**Phase 3 — Kana tab**
8. Transcribe `utils/kana.js` into `KanaTable` (seion/dakuon/youon + flat pools).
9. `KanaBrowserView` + `KanaTileView`.
10. `KanaResult` `@Model` + `KanaQuizView`/`KanaQuizModel`; wire tile green/red
    coloring off `KanaResult`.
    → Milestone: full Kana tab, quiz history persists.

**Phase 4 — audio (deferred)**
11. Implement `SystemTTS` (or `BundledAudio` via macOS `say -v Kyoko`), swap it in for
    `SilentPronouncer`.
12. Turn on **Listening** and **Read All**.

## RN → SwiftUI mapping (consolidated)

| RN | SwiftUI |
|---|---|
| `createBottomTabNavigator` | `TabView` |
| `createStackNavigator` | `NavigationStack` + `.navigationDestination` |
| `IndicatorViewPager` (groups/kana pages) | `List` sections (lessons) / segmented `Picker` (kana) |
| component `state`/`setState` | `@State` / `@Observable` model |
| `react-native-simple-store` prefs | `@AppStorage` |
| `kana.assessment.*` store | `KanaResult` `@Model` |
| `lessons.assessment.*` (bookmarks) | **dropped** |
| `fuse.js` | `search(_:in:)` (simple contains; fuzzy later) |
| `react-native-tts` | `Pronouncer` seam → `SystemTTS`/`BundledAudio` |
| `react-native-i18n` `minna.*` | per-lesson `[String:String]` from bundle |
| `Ionicons` | SF Symbols |
| `shuffle`/`choice`/`randomInt` | `shuffled()`/`randomElement()`/`Int.random` |

## Explicitly out of scope (do not build)

Today tab, Bookmark tab + star ratings, About tab, study reminders/notifications,
premium/IAP, ads, analytics, auth, social login. See `README.md` scope.

## Open items / conscious downgrades

- **Search fidelity:** simple `contains` vs Fuse.js `threshold 0.18` fuzziness.
  Acceptable for v1; revisit if users miss typo-tolerance.
- **Listening / Read All** blocked on audio (Phase 4).
- **Audio quality:** decide `SystemTTS` (live) vs `BundledAudio` (pre-generated)
  when Phase 4 starts; both routes documented in `05-shared-and-audio.md`.
- **Kana data transcription** from `utils/kana.js` is manual — verify counts
  (seion ~46, dakuon 25, youon 33) after porting.
