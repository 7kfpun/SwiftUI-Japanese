# 01 — Data model

Every screen reads from data compiled ahead of build time. This doc covers what
gets generated, what's hand-written, the Swift types that consume it, and where
mutable state actually lives.

## Source of truth: the `minna` submodule

`minna/` at the repo root is a **git submodule** (`.gitmodules` →
`git@github.com:7kfpun/minna.git`). It is *not* bundled into the app directly —
it's pure source data, refreshed independently of app releases. Its structure:

```
minna/
  vocab/{1..50}.json     Japanese source of truth (kanji/kana/romaji/dictionary/useKana/audio path)
  vocab/kana.json        the kana chart: grid layout (row/col), stroke counts, audio paths
  audio/<voice>/…        source clips per voice (kyoko, kenzaki, whitecul), by relative path
  en|zh|zh-Hant|vi|de|th|my|es|fr|ru|bn|hi|ta|te|fil|id|ko/{1..50}.json
                         translations, keyed by romaji — 19 languages total
```

`romaji` is the join key between a lesson's `vocab/{n}.json` and its translation
files, but it is only **unique within a lesson** — romaji repeat across different
lessons, so nothing downstream can key off romaji alone (see `Vocab.id` below).

**The bundled audio is synthesised upstream — not native-speaker recordings.**
Marketing and store copy must not claim otherwise, whatever the voice.

The submodule ships three voices for Minna: `kyoko` (Apple's `say`, concatenative) and
the VOICEVOX neural pair `kenzaki` and `whitecul`. `whitecul` is what the app bundles;
`kenzaki` rides along only for the Challenge ladder. JLPT ships `kyoko` alone.

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

- **`MinnaData.json`** (git-ignored, regenerated) — one JSON file: `languages`
  (the 19 codes), `lessons` (50 × `{number, entries}`, each entry has
  `kanji/kana/romaji/dictionary?/useKana?/audio?`), and `translations`
  (`lang → lessonNumber(as string) → romaji → text`).
- **`KanaChart.json`** (git-ignored, regenerated) — `minna/vocab/kana.json` copied **verbatim**:
  grid position (`row`/`col`), romaji, hiragana/katakana stroke counts, and
  audio paths for every kana cell, grouped by `seion`/`dakuon`/`youon`.
- **`Resources/audio/vocab/<lesson>-<slug>.m4a`** — every vocab word's default clip
  (`whitecul`), with `<lesson>-<slug>-kenzaki.m4a` beside it for the ladder,
  renamed flat (`1-watashi.m4a`, …) so the synchronized group can bundle them
  as individually-copied resources with no name collisions. **Git-ignored** —
  regenerate by re-running the script; it isn't checked in because of its size.
  The `vocab/` level exists so the pbxproj can name it: the `nihongo` folder is
  also listed by the `jlpt` target, and 23MB of Minna clips have no business in a
  JLPT binary. Subfolders inside a synchronized group flatten into the bundle
  root, so `Bundle.main.url(forResource:)` is unaffected by the extra level.
- **`Resources/audio/kana/kana-<romaji>.m4a`** — one clip per kana cell, deduped by
  romaji (じ/ぢ and ず/づ share a pronunciation, so the *first* one wins;
  see the comment in the script for exactly which).

Re-run the script whenever `minna/` updates (see the `refresh-data` skill) or
whenever `nihongo/Resources/MinnaData.json` looks stale relative to the
submodule. It's idempotent and safe to run any time — it always regenerates all
outputs from scratch.

### What the generated data actually contains, right now

Counted from `MinnaData.json`, not from memory:

| Fact | Value |
|---|---|
| Lessons | 50 |
| Vocab entries | 2089 |
| Entries with a bundled clip | 2089 (all of them) |
| Words per lesson | 17 (min) – 63 (max) |
| Languages | 19 |
| Resolved translation strings | 35 513 |

The shipped set is **18** (`en, zh, zh-Hant, vi, de, th, my, es, fr, ru, bn,
hi, ta, te, ne, fil, id, ko` — Nepali joined 2026-08), which is what
`MinnaData.json`, `UIStrings.json` and
`LocalizationTests.uiStringsCoverEveryLanguageAndKey` all agree on. A language
count quoted anywhere else — code comments, store copy, the website — is a
snapshot that goes stale; these files are the ground truth.

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

`displaysKanji` is load-bearing well beyond display: `Challenge.supports` refuses a
kanji prompt for a kana-only word (the prompt would equal the answer), and the intro's
first card picks its sample word by it.

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
alone on its row, matching the printed textbook chart) — 46 / 25 / 33 non-empty
cells respectively. `KanaData.hiraganaPool` / `.katakanaPool` are flat 74-entry
arrays (hand-transcribed, not data-driven) used as the distractor source for
Lessons → Learn's tile game.

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

**Two different defaults, and the difference matters.**
`VocabStore.defaultLanguage` is literally `"en"` and stays that way: it's the
argument-less fallback for `lessons(_:)`/`allVocab(_:)`/`lesson(_:_:)` and the
missing-translation fallback, and several tests depend on that meaning.
`VocabStore.deviceDefaultLanguage` forwards to `L.deviceDefault` and is the
**first-launch default for `Pref.translationLanguage`**, so a Vietnamese user gets
Vietnamese meanings without first finding Settings (see `09-intro-and-survey.md`).

`cleanWord(_:)` (also in `VocabStore.swift`) strips display annotations before
tiling/speaking: `（…）`, `［…］`, `「…」`, `[…]`, `～`, `。`. Used by Learn's
tile target, by `Challenge`'s lookalike ranking, and by every TTS path
(`Speech.utterance`).

`searchVocab(_:in:)` is a simple case-insensitive `contains` across
kanji/kana/romaji/translation — not fuzzy matching. `LessonListView` debounces
input 600ms before logging a `search_vocab` analytics event, but filtering
itself is synchronous and instant.

## Persistence split

Three storage tiers, and nothing crosses between them:

| Data | Storage | Notes |
|---|---|---|
| Vocab / Lesson / kana chart | Bundled JSON, decoded to structs | Immutable reference data — never `@Model` |
| Field-visibility, sound, per-mode order, kana tile script | `@AppStorage` | Keys centralized in `Pref` |
| App-UI language / vocab-translation language | `@AppStorage` | Two independent settings — see `05-shared-and-audio.md` |
| Intro answers + "intro seen" | `UserDefaults` via `Pref` | Written once by `IntroAnswers.save(to:)` — `09-intro-and-survey.md` |
| "Rating already asked" | `UserDefaults` via `Pref` | One-shot flag, `06-monetization.md` |
| Kana mastery (`KanaResult`) | **CloudKit-backed SwiftData** | One row per romaji, upserted on every answer |
| Challenge progress (`ChallengeResult`) | **CloudKit-backed SwiftData** | One row per rung, best-only — `02-challenge-ladder.md` |
| Saved words (`Bookmark`) | **CloudKit-backed SwiftData** | One row per starred word, newest wins on merge |
| Study days (`StudyDay`) | **CloudKit-backed SwiftData** | One `yyyymmdd` row per studied day — the streak's raw data |
| Today's deck | **nothing** | Derived from progress on every appear; see below |
| Today's snapshot for the widget/watch | App Group `UserDefaults` + WatchConnectivity | `Shared/TodayShared.swift` — a cache of a derived value, not state |

### `Pref` — the whole key registry (`nihongo/Prefs.swift`)

`Pref` is the single registry of `@AppStorage`/`UserDefaults` key strings; the file
comment explains why — a typo in an inline string literal would silently create a
brand-new, disconnected setting instead of erroring. The full set:

| Key constant | Stored key | Read by |
|---|---|---|
| `appLanguage` | `appLanguage` | `L.current`, `RootView.id(...)` |
| `translationLanguage` | `translationLanguage` | every lesson-resolving view |
| `soundOn` | `isSoundOn` | `SoundToggle`, every auto-play |
| `ordered` | `isOrdered` | Learn's order picker (defaults **true**) |
| `trainOrdered` | `trainOrdered` | Train's order picker (defaults **false**) |
| `kanjiShown` / `kanaShown` / `romajiShown` / `translationShown` | `isKanjiShown` / … | `CardOptionsBar`, Learn, Today |
| `kanaTileScript` | `kanaTileScript` | `KanaBrowserView` — index into its script table (`03-kana.md`) |
| `analyticsExcluded` | `analyticsExcluded` | `Track.setExcluded`, `AppBootstrap` |
| `ratingAsked` | `ratingAsked` | `RatingPrompt.hasAsked` |
| `introAnswered` | `introAnswered` | `RootView`'s first-launch cover |
| `knowsKana` | `knowsKana` | `Intro.landingTab` — the only intro answer with a consumer |
| `textbookLesson` | `textbookLesson` | **nothing — recorded only** |
| `goal` | `goal` | **nothing — recorded only** |

Note that `ordered` and `trainOrdered` are two keys on purpose: Learn defaults to
ordered, Train to random, so sharing one switch would force one of them to open in the
wrong mode.

**There is no `Pref.todayLesson` and no `Pref.todaySelection`.** Earlier releases
persisted a chosen lesson and a saved 7-word selection; Today now derives its deck from
challenge progress on every appear (`TodayView.studyLesson()` → the first lesson with an
unpassed rung, then `Challenge.pool` for that rung) and stores nothing. Being a pure
function of progress is what lets it advance the instant a rung is passed without a
migration or a reset path. Orphaned `todayLesson`/`todaySelection` values still sit in
old simulator plists, which is how the claim survived in this doc for a while — nothing
in the app reads them.

### The SwiftData layer — two models, one CloudKit container

`nihongoApp.swift:19` registers `Schema([KanaResult.self, ChallengeResult.self])` in a
**single** `ModelContainer` configured with `cloudKitDatabase: .private("iCloud.com.kfpun.nihongo")`,
so kana mastery and challenge progress follow the user across devices. It falls back to a
plain local store when CloudKit refuses — no iCloud entitlement in an open-source clone,
no signed-in simulator account — because progress still matters locally; only a failure
of *both* is fatal.

```swift
@Model final class KanaResult {          // nihongo/KanaResult.swift
    var romaji: String
    var isCorrect: Bool
    var timestamp: Date
    static func record(romaji:isCorrect:context:)   // upsert
}
```

**Neither model carries `@Attribute(.unique)`, and that is forced, not sloppy:
CloudKit-backed SwiftData forbids unique constraints.** So "one row per kana" and "one
row per rung" are conventions maintained by each model's `record` upsert, and a two-device
offline merge *can* leave duplicates. Every reader is written to tolerate that, with a
resolution rule that matches the store's own semantics:

- `KanaResult` — **latest `timestamp` wins**, which is also literally what the store
  means ("the most recent answer"). `record` updates the newest matching row, and
  `KanaBrowserView`'s `byRomaji` map merges duplicates by timestamp rather than
  first-wins.
- `ChallengeResult` — **the strongest row wins**, via `better(_:_:)`. Detailed in
  `02-challenge-ladder.md`.

`KanaResult` drives the green/red tile borders in `KanaBrowserView` and the Write mode's
verdict, and it's the only per-item mastery record in the app: there is no vocab
equivalent, no bookmarking and no spaced-repetition schedule.

## Data integrity — what the tests actually pin down

`nihongoTests/nihongoTests.swift` is the living contract for the generated data and will
fail loudly if `build-minna-data.py`'s output shape changes. `DataTests` pins: exactly
2089 vocab entries across lessons 1…50, all of them with a bundled audio clip,
globally-unique `Vocab.id`, at least 4 distinct kana readings per lesson (a quiz needs 4
options), one named clip that actually decodes, a bundled clip for *every* kana cell, and
non-empty translations for lesson 1 in all 19 languages. `KanaTests` pins the 46/25/33
chart counts and the 74-entry pools; `KanaSketchTests.strokeCountsCoverEveryDrawableKana`
pins a stroke count on every drawable cell.

Two caveats when reading them:

- `everyLessonSupportsGameplay` asserts `entries.count >= 7` with the comment "the Today
  tab picks 7 words". That comment is stale — Today deals a rung's pool, which is ≥ 10 by
  construction. The assertion is still a useful floor, just not for the stated reason.
- These counts must be updated **together with** a data regeneration, not
  independently — that's the point of them being canaries.

Whole-suite size is around 78 tests (`run-tests` skill); re-count before quoting it.
