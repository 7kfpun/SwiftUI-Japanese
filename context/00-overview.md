# 00 — Overview & architecture

## What the app teaches

The **Minna no Nihongo** textbook: 50 lessons, ~2089 vocabulary entries, plus the
two kana syllabaries (hiragana + katakana). It is a vocabulary + kana drill app, not
a grammar app.

## Navigation graph

The RN app's root is a **bottom tab bar** of 5 tabs; each tab is its own navigation
stack. Reference: `reference-rn/app/App.js`. Below, tabs kept for the rebuild are
marked ✅ and dropped ones ❌.

```
TabView (bottom)
├─ ❌ Today    → todayNavigator      : today                     (DROPPED / deferred)
├─ ✅ Kana     → kanaNavigator       : kana → kana-assessment
├─ ✅ Lessons  → lessonNavigator     : lessons → vocab-list
│                                             → select-mode → assessment          (Learn)
│                                                           → assessment-mc        (Quiz / MC)
│                                                           → assessment-listening (Listening)
│                                                           → read-all             (Read All)
├─ ❌ Bookmark → bookmarkNavigator   : bookmark → bookmark-list   (DROPPED)
└─ ❌ About    → aboutNavigator      : settings/premium           (DROPPED)
```

In scope for the rebuild: **Kana** and **Lessons** only. Explicitly **dropped**:
the **Today** tab, the **Bookmark** tab and all star-rating/bookmarking, the
**About** tab, and any **study reminder** / notification feature. The rebuilt app is
a 2-tab (Kana, Lessons) offline study app.

## The 5 tabs at a glance

1. **Today** (`02-today.md`) — a daily set of vocab flashcards selected from the
   **bundled** data (no server), with field-visibility toggles, shuffle/next, and
   reveal-on-hold. Simplest tab.

2. **Kana** (`03-kana.md`) — a 3-page reference (Seion / Dakuon / Youon) of the kana
   grid, each tile showing hiragana + katakana + romaji; plus a 4-choice quiz with
   any-form→any-form direction toggles. Tiles remember your last quiz result
   (green/red).

3. **Lessons** (`04-lessons.md`) — the core engine. Browse 50 lessons in 4 groups,
   fuzzy-search all vocab, and drill each lesson in 5 modes: Vocab List, Learn (tile
   reconstruction), Quiz (MC), Listening, Read All.

(Bookmark and About tabs are dropped — see scope note above.)

## Cross-cutting pieces (see `05-shared-and-tts.md`)

- **Card** — the shared vocab display with per-field visibility, used by Today and
  Learn.
- **CardOptionSelector** — the row of toggle buttons (kanji/kana/romaji/translation/
  sound, plus ordered/random in Learn).
- **Audio** — word pronunciation (RN used `react-native-tts`). **Deferred for now**
  but designed in: every "speak" call goes through a `Pronouncer` protocol that is a
  no-op stub in v1, so audio can be dropped in later (planned: macOS `say -v Kyoko`
  pre-generated clips, or live `AVSpeechSynthesizer`). See `05-shared-and-audio.md`.
- **helpers** — `shuffle` (Fisher-Yates), `cleanWord`, `choice`, `randomInt`,
  `range`, `getRandom`.

(The `SaveVocab` + `Rating` star control is dropped with bookmarking.)

## State & persistence model (RN → SwiftUI)

- **User preferences** (`@AppStorage` in SwiftUI): `isKanjiShown`, `isKanaShown`,
  `isRomajiShown`, `isTranslationShown`, `isSoundOn`, `isOrdered`. All default `true`
  (except `isOrdered`), gated on a first-run flag `isNotFirstStart`.
- **Kana quiz history** (SwiftData in SwiftUI): key `kana.assessment.{romaji}` →
  `true|false`, plus `kana.assessment.{romaji}.timestamp` → unix seconds. Drives the
  green/red tile coloring in the Kana browser.

These live in `react-native-simple-store` (a thin AsyncStorage key/value wrapper) in
the RN app. In the rebuild: prefs → `@AppStorage`; the kana quiz history → a small
SwiftData model (see `06-swiftui-rebuild-plan.md`).

(The bookmark store `lessons.assessment.{romaji}` → `1|2|3` is **dropped** with the
bookmarking feature.)
