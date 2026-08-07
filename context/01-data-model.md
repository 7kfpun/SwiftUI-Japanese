# 01 — Data model

Every screen reads from data compiled ahead of build time. This doc covers what
gets generated, what's hand-written, and the Swift types that consume it.

## Source of truth: the `minna` submodule

`minna/` at the repo root is a **git submodule** (`.gitmodules` →
`git@github.com:7kfpun/minna.git`). It is *not* bundled into the app directly —
it's pure source data, refreshed independently of app releases. Its structure:

```
minna/
  vocab/{1..50}.json     Japanese source of truth (kanji/kana/romaji/dictionary/useKana/audio path)
  vocab/kana.json        the kana chart: grid layout (row/col), stroke counts, audio paths
  audio/…                Kyoko (`say -v Kyoko`) source clips, referenced by relative path
  en|zh|zh-Hant|vi|de|th|my|es|fr|ru|bn|hi|ta|te|fil|id|ko/{1..50}.json
                         translations, keyed by romaji — 17 languages total
```

`romaji` is the join key between a lesson's `vocab/{n}.json` and its translation
files, but it is only **unique within a lesson** — 111 romaji repeat across
different lessons, so nothing downstream can key off romaji alone (see
`Vocab.id` below).

## Why there's a compile step (`scripts/build-minna-data.py`)

An earlier attempt bundled `minna/` directly as an Xcode folder reference. That
didn't survive contact with this project's Xcode setup: the app target uses
**file-system-synchronized groups** (Xcode 26), which flatten resource
subfolders — `vocab/1.json` and `en/1.json` would both want to land at bundle
root as `1.json` and collide. The fix was to compile everything into a small
number of **flat, uniquely-named** files ahead of time:

Run from the repo root:
```sh
python3 scripts/build-minna-data.py
```

It reads `minna/` and writes into `nihongo/Resources/`:

- **`MinnaData.json`** (tracked in git, ~700 KB) — one JSON file: `languages`
  (the 17 codes), `lessons` (50 × `{number, entries}`, each entry has
  `kanji/kana/romaji/dictionary?/useKana?/audio?`), and `translations`
  (`lang → lessonNumber(as string) → romaji → text`).
- **`KanaChart.json`** (tracked) — `minna/vocab/kana.json` copied **verbatim**:
  grid position (`row`/`col`), romaji, hiragana/katakana stroke counts, and
  audio paths for every kana cell, grouped by `seion`/`dakuon`/`youon`.
- **`Resources/audio/<lesson>-<slug>.m4a`** — every vocab word's Kyoko clip,
  renamed flat (`1-watashi.m4a`, …) so the synchronized group can bundle them
  as individually-copied resources with no name collisions. **Git-ignored** —
  regenerate by re-running the script; it isn't checked in because it's ~75 MB.
- **`Resources/audio/kana-<romaji>.m4a`** — one clip per kana cell, deduped by
  romaji (じ/ぢ and ず/づ share a pronunciation, so the *first* one wins;
  see the comment in the script for exactly which).

Re-run the script whenever `minna/` updates (see the `refresh-data` skill) or
whenever `nihongo/Resources/MinnaData.json` looks stale relative to the
submodule. It's also idempotent and safe to run any time — it always
regenerates all outputs from scratch.

## Swift models

`nihongo/Models.swift`:

```swift
struct VocabEntry: Codable, Hashable {          // one row as stored in MinnaData.json
    let kanji: String
    let kana: String
    let romaji: String
    let dictionary: String?
    let useKana: Bool?
    let audio: String?        // bundled clip basename, no extension, e.g. "1-watashi"
}

struct Vocab: Identifiable, Hashable {          // enriched — what the UI actually renders
    let lesson: Int
    let kanji: String
    let kana: String
    let romaji: String
    let dictionary: String?
    let useKana: Bool
    let translation: String
    let audio: String?
    var id: String { "\(lesson)/\(romaji)" }     // must include lesson — romaji isn't globally unique
    var displaysKanji: Bool { !useKana && kanji != kana }
}

struct Lesson: Identifiable, Hashable {
    let number: Int
    let entries: [Vocab]
    var id: Int { number }
}
```

`nihongo/KanaData.swift`:

```swift
struct K: Hashable, Identifiable {              // one kana chart cell
    let hiragana: String, katakana: String, romaji: String
    let hiraganaStrokes: Int, katakanaStrokes: Int   // 0 = unknown
    var isEmpty: Bool { romaji.isEmpty }             // grid-alignment placeholder
}
```

`KanaData.seion` / `.dakuon` / `.youon` are `[[K]]` grids built at load time
from `KanaChart.json` by placing entries at their `row`/`col`, padding gaps
with empty placeholders, and trimming trailing-empty cells per row (so ん sits
alone on its row, matching the printed textbook chart). `KanaData.hiraganaPool`
/ `.katakanaPool` are flat 74-entry arrays (hand-transcribed, not
data-driven) used as the distractor source for Lessons → Learn's tile game.

## `VocabStore` — the bundle loader (`nihongo/VocabStore.swift`)

Loads `MinnaData.json` once into a `fatalError`-on-missing static (missing
means someone forgot to run the build script). Per-language `[Lesson]` arrays
are built **lazily and cached** — only the language actually shown gets
decoded/resolved, not all 17, keeping launch cheap. The cache is guarded by an
`NSLock` because Swift Testing runs test cases in parallel and an unlocked
mutable `static var` would data-race.

Key entry points:
- `VocabStore.lessons(_ language:)` / `.allVocab(_:)` / `.lesson(_:_:)`
- `VocabStore.audioURL(for: Vocab)` — resolves a word's `.m4a` by its stored
  `audio` basename.
- `VocabStore.kanaAudioURL(_ romaji:)` — resolves `kana-<romaji>.m4a`.
- `VocabStore.displayName(_ code:)` — a language code → its localized display
  name (`Locale.localizedString(forIdentifier:)`), used in Settings' language
  pickers.

`cleanWord(_:)` (also in `VocabStore.swift`) strips display annotations before
tiling/speaking: `（…）`, `［…］`, `「…」`, `[…]`, `～`, `。`. Used by Learn's
tile target and by every TTS fallback path.

`searchVocab(_:in:)` is a simple case-insensitive `contains` across
kanji/kana/romaji/translation — not fuzzy matching. `LessonListView` debounces
input 600ms before logging a `search_vocab` analytics event, but filtering
itself is synchronous and instant.

## Persistence split

| Data | Storage | Notes |
|---|---|---|
| Vocab/Lesson/kana chart | Bundled JSON, decoded to structs | Immutable reference data — never `@Model` |
| Field-visibility + sound/order toggles (`isKanjiShown`, `isKanaShown`, `isRomajiShown`, `isTranslationShown`, `isSoundOn`, `isOrdered`) | `@AppStorage` | Keys centralized in `Pref` (`nihongo/Prefs.swift`) — never inline string literals |
| App-UI language / vocab-translation language | `@AppStorage` (`Pref.appLanguage`, `Pref.translationLanguage`) | Two independent settings — see `07-ux-ui.md` |
| Kana quiz/write mastery (`KanaResult`) | **SwiftData** `@Model` | One row per romaji, upserted on every answer |
| Today's daily lesson + saved 7-word selection | `@AppStorage` (`Pref.todayLesson`, `Pref.todaySelection` as JSON) | Also mirrored into an App Group for the widget — see `05-shared-and-audio.md` |

`Pref` (`nihongo/Prefs.swift`) is the single registry of `@AppStorage` key
strings — the file comment explains why: a typo in an inline string literal
would silently create a brand-new, disconnected setting instead of erroring.

### `KanaResult` (`nihongo/KanaResult.swift`)

```swift
@Model final class KanaResult {
    @Attribute(.unique) var romaji: String
    var isCorrect: Bool
    var timestamp: Date
    static func record(romaji:isCorrect:context:)   // upsert — used by every kana quiz/write mode
}
```

Registered in the app's single `ModelContainer` (`nihongoApp.swift`, schema
`[KanaResult.self]`). Drives the green/red tile borders in `KanaBrowserView`
and is the only SwiftData model in the app — there's no bookmarking, no
lesson-level progress persistence beyond this.

## Data integrity — what the tests actually pin down

`nihongoTests/nihongoTests.swift` (`DataTests`) is the living contract for the
generated data and will fail loudly if `build-minna-data.py`'s output shape
changes: exactly 2089 vocab entries across 50 lessons, 2087 of them with a
bundled audio clip (2 don't — those fall back to live TTS), globally-unique
`Vocab.id`, every lesson has ≥7 entries (Today needs 7) and ≥4 distinct kana
readings (the quiz needs 4 options), every kana cell has a bundled clip, and
every one of the 17 languages resolves non-empty translations for lesson 1.
Update these numbers together with a data regeneration, not independently.
