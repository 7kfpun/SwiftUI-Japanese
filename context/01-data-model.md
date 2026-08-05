# 01 — Data model & bundling the `minna` submodule

This is the foundation: every screen reads from this data. Get the models and the
loader right first.

## Source of truth

Submodule at **`nihongo/Resources/minna/`**. Authoritative format spec:
`nihongo/Resources/minna/SCHEMA.md`. Summary:

```
Resources/minna/
  vocab/{1..50}.json                       Japanese source of truth
  en|zh|zh-Hant|vi|de|th|my/{1..50}.json   translations, keyed by romaji
```

- **50 lessons**, **2089 entries total**, **7 translation languages**.
- **`romaji` is the join key.** Each language file is a flat `{ romaji: translation }`
  map whose key set exactly equals that lesson's `vocab/` romaji set.

### `vocab/{lesson}.json`

```json
{
  "data": [
    { "kanji": "わたし",   "kana": "わたし",       "romaji": "watashi" },
    { "kanji": "飼います", "kana": "かいます", "dictionary": "飼う", "romaji": "kaimasu" },
    { "kanji": "～君",     "kana": "～くん",       "romaji": "~kun", "useKana": true }
  ]
}
```

| Field | Req | Meaning |
|---|---|---|
| `kanji` | ✅ | Headword as written (polite ます form for verbs) |
| `kana` | ✅ | Reading, kana only. May carry a bracketed example: `のります［でんしゃに～］` |
| `romaji` | ✅ | Join key, unique **within a lesson** (not globally) |
| `dictionary` | — | Alternate/plain form where the source recorded one (284 entries) |
| `useKana` | — | `true` → display kana instead of kanji (32 entries) |

### language file `en/{lesson}.json`

```json
{ "watashi": "I", "watashitachi": "we", "anata": "you" }
```

## Swift models (`Codable`)

These decode the JSON directly. Keep them value types; they are immutable reference
data, **not** SwiftData models (see persistence note below).

```swift
struct VocabEntry: Codable, Identifiable, Hashable {
    let kanji: String
    let kana: String
    let romaji: String
    let dictionary: String?
    let useKana: Bool?

    var id: String { romaji }          // unique within its lesson
}

private struct VocabFile: Codable { let data: [VocabEntry] }

struct Lesson: Identifiable, Hashable {
    let number: Int                    // 1...50
    let entries: [VocabEntry]
    var id: Int { number }
}
```

A vocab item enriched with its translation (what the UI actually renders and what
search indexes — mirrors RN `vocab-helpers.js`, which pre-joins translation + lesson
onto every item):

```swift
struct Vocab: Identifiable, Hashable {
    let lesson: Int
    let kanji: String
    let kana: String
    let romaji: String
    let dictionary: String?
    let useKana: Bool
    let translation: String            // resolved from the active language file
    var id: String { "\(lesson)/\(romaji)" }   // globally unique
}
```

## ⚙️ IMPLEMENTATION NOTE (what was actually built)

The plan below described a raw **folder reference**. During the build we discovered
the Xcode project uses **file-system-synchronized groups** (Xcode 26), which *flatten*
resource subfolders → `vocab/1.json` and `en/1.json` (all 50 numbers × 8 folders)
would collide on identical output names. So the shipped design instead:

- The **submodule was relocated to the repo root `minna/`** (out of the synchronized
  `nihongo/` source folder) and is now pure **source-of-truth**, not bundled directly.
- `scripts/build-minna-data.py` **compiles it into a single `nihongo/Resources/
  MinnaData.json`** (708 KB, all 50 lessons + 7 languages) — one file, no collisions,
  auto-bundled by the synchronized group. Re-run the script when the submodule updates.
- `VocabStore` loads that one file via `Bundle.main.url(forResource:"MinnaData",
  withExtension:"json")` — see `nihongo/VocabStore.swift`.

The rest of this section (models, `cleanWord`, persistence split) is accurate as built.
The raw per-directory loader below is superseded by the single-file loader.

## Loading from the bundle (original plan — superseded, see note above)

### Xcode setup (do this once)

Add `Resources/minna` to the app target as a **folder reference** (blue folder,
"Create folder references" — *not* a group). This copies the whole tree into the
`.app` **preserving subdirectories**, so `vocab/`, `en/`, … survive as real
directories in the bundle. This is what makes the romaji-join layout work at runtime.

> **Bundling caveat (verified):** the submodule root also contains non-data files —
> `SCHEMA.md`, `.gitignore`, a `.claude/` dir, and a `.git` gitlink file. A folder
> reference copies everything. It's only ~a few KB of junk against 1.9 MB / 400 JSON
> of real data, so the pragmatic choice is **ship the whole folder** (harmless). If
> you want a spotless bundle, add only the data subdirs (`vocab` + the language dirs
> you ship) as separate references instead — but then adjust `subdirectory:` paths
> (they'd be `vocab`/`en` at bundle root, not `minna/vocab`). Recommend: ship the
> whole folder, don't over-engineer.
>
> **Languages:** all 7 (`en zh zh-Hant vi de th my`) total 1.9 MB — fine to bundle
> all. Default `en`.

Lookup then uses `subdirectory:`:

```swift
Bundle.main.url(forResource: "1", withExtension: "json",
                subdirectory: "minna/vocab")
Bundle.main.url(forResource: "1", withExtension: "json",
                subdirectory: "minna/en")
```

### Loader (mirrors RN `utils/items.js` + `utils/i18n.js` + `vocab-helpers.js`)

```swift
enum VocabStore {
    static let lessonNumbers = Array(1...50)

    static func lesson(_ n: Int, language: String = "en") -> [Vocab] {
        let base: VocabFile = decode("minna/vocab", "\(n)")
        let tr: [String: String] = decode("minna/\(language)", "\(n)")
        return base.data.map { e in
            Vocab(lesson: n, kanji: e.kanji, kana: e.kana, romaji: e.romaji,
                  dictionary: e.dictionary, useKana: e.useKana ?? false,
                  translation: tr[e.romaji] ?? "")
        }
    }

    /// Flattened 2089-item index for search (RN `vocabs` array in vocab-helpers.js).
    static func allVocab(language: String = "en") -> [Vocab] {
        lessonNumbers.flatMap { lesson($0, language: language) }
    }

    private static func decode<T: Decodable>(_ dir: String, _ name: String) -> T {
        let url = Bundle.main.url(forResource: name, withExtension: "json",
                                  subdirectory: dir)!
        return try! JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
```

Consider caching `allVocab()` once (it is static reference data) rather than
re-decoding per view.

### RN translation lookup this replaces

RN resolves translations via i18n keys `I18n.t("minna.\(lesson).\(romaji)")`
(`reference-rn/app/utils/i18n.js`, which `require`s every `minna/{lang}/{n}.json`
into `I18n.translations[lang].minna[lesson][romaji]`). In Swift we skip i18n and read
the same JSON straight into a `[String: String]` dictionary per lesson.

## Text cleaning — `cleanWord` (needed by Kana Learn & audio)

RN `reference-rn/app/utils/helpers.js → cleanWord` (~L39) strips display annotations
before tiling/speaking. Port it verbatim:

```swift
func cleanWord(_ text: String) -> String {
    var s = text
    for pattern in ["（.*?）", "［.*?］", "「.*?」", "\\[.*\\]"] {   // full/half brackets
        s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
    s = s.replacingOccurrences(of: "～", with: "")
    s = s.replacingOccurrences(of: "。", with: "")
    return s
}
```

Removes: `（…）`, `［…］`, `「…」`, `[…]`, `～`, `。`. Used to derive the
reconstruct-target in Learn mode and the spoken string.

## Persistence split (SwiftUI)

| Data | RN storage | SwiftUI |
|---|---|---|
| Field toggles (`isKanaShown`, `isKanjiShown`, `isRomajiShown`, `isTranslationShown`, `isSoundOn`, `isOrdered`) | `react-native-simple-store` keys | `@AppStorage` |
| Kana quiz result per kana (`kana.assessment.{romaji}` → bool, `.timestamp`) | same | SwiftData model `KanaResult` (see `03-kana.md`) |
| Bookmarks (`lessons.assessment.{romaji}` → 1\|2\|3) | same | **dropped** |

`Vocab`/`Lesson` are immutable bundle data → plain structs, **not** `@Model`.
