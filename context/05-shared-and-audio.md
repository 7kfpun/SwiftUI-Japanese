# 05 — Shared components, helpers & audio

Cross-tab pieces used by Kana and Lessons.

## Card (`reference-rn/app/components/card.js`)

The shared vocab display used by Learn (and, in the original, Today). Renders, with
per-field visibility:

- **kana** slots (always the backbone; in Learn, the assembled answer overlays here)
- **kanji** — only if `(isAllShown || isKanjiShown)` **and** `kanji !== kana` (~L238)
- **romaji** — if `(isAllShown || isRomajiShown)` (~L252)
- **translation** — if `(isAllShown || isTranslationShown)` (~L262)
- tap the card → speak kana (routes to `Pronouncer`, no-op v1)
- `SaveVocab` star control at ~L273 → **omit** (bookmarking dropped)

**SwiftUI:** `VocabCard(vocab:, reveal:)` where `reveal` is the set of currently
shown fields. Kanji hidden when equal to kana. Keep it a pure view driven by the
toggle state.

## CardOptionSelector (`reference-rn/app/components/card-option-selector.js`)

Row of toggle buttons persisting to `react-native-simple-store`; loaded on mount
(~L75), toggled + saved immediately (~L111). Keys and defaults (all default `true`
on first run, guarded by `isNotFirstStart`; `isOrdered` is the exception):

| Key | Controls | Default |
|---|---|---|
| `isKanjiShown` | show kanji | true |
| `isKanaShown` | show kana | true |
| `isRomajiShown` | show romaji | true |
| `isTranslationShown` | show translation | true |
| `isSoundOn` | auto-speak | true |
| `isOrdered` | Learn: ordered vs random nav | (per screen) |

**SwiftUI:** back each with `@AppStorage`:

```swift
@AppStorage("isKanjiShown")       var showKanji       = true
@AppStorage("isKanaShown")        var showKana        = true
@AppStorage("isRomajiShown")      var showRomaji      = true
@AppStorage("isTranslationShown") var showTranslation = true
@AppStorage("isSoundOn")          var soundOn         = true
@AppStorage("isOrdered")          var ordered         = true
```

A `CardOptionsBar` view = a row of SF-Symbol toggle buttons bound to these. No
first-run seeding needed — `@AppStorage` defaults handle it.

## CircleButton (`reference-rn/app/components/circle-button.js`)

Press-and-hold reveal control (Today's reveal-all). Today is dropped; if a
reveal-all affordance is wanted in Learn, model it as a `.gesture` setting a
`revealAll` `@State` on press-in / clearing on press-out.

## Helpers (`reference-rn/app/utils/helpers.js`) → Swift equivalents

| RN helper | Line | Swift |
|---|---|---|
| `shuffle(a)` Fisher-Yates | ~L26 | `Array.shuffle()` / `.shuffled()` |
| `cleanWord(text)` | ~L39 | port verbatim (see `01-data-model.md`) |
| `range(start, stop, step)` | ~L49 | `stride(from:to:by:)` |
| `choice(arr)` | ~L65 | `Array.randomElement()` |
| `randomInt(max)` | ~L68 | `Int.random(in: 0..<max)` |
| `getRandom(arr, n)` (Learn tiles) | `assessment.js` ~L152 | `Array(arr.shuffled().prefix(n))` (throw/guard if `n > count`) |

## Audio — deferred, but designed in

**Status: not implemented in v1.** Every "speak" path goes through one protocol so
audio can be added later without touching views.

```swift
protocol Pronouncer {
    func speak(_ vocab: Vocab)
    func speak(kana: String)
    func stop()
}

/// v1: does nothing. Injected via environment so views can call it freely.
struct SilentPronouncer: Pronouncer {
    func speak(_ vocab: Vocab) {}
    func speak(kana: String) {}
    func stop() {}
}
```

Inject through the environment (`.environment(\.pronouncer, SilentPronouncer())`) so
Vocab List tap, Kana tile tap, Quiz speaker button, Listening prompt, and Read All
all call the same seam.

### Planned real implementations (later)

RN behavior to reproduce (`utils/helpers.js → ttsSpeak` ~L83): rate **0.4**, language
`ja`, speak `cleanWord(kana)` (kana is the safe, unambiguous reading; RN spoke kana
on Android / kanji on iOS unless `useKana` — the rebuild should just always speak
**kana** to avoid kanji reading ambiguity).

1. **`SystemTTS`** — live `AVSpeechSynthesizer`, voice `ja-JP` (Kyoko), rate ≈ 0.4.
   Zero assets, offline, but synthetic. Simplest drop-in.
2. **`BundledAudio`** — pre-generated clips shipped in the bundle. **Confirmed
   feasible on this Mac:** `say -v Kyoko` is installed (`ja_JP`), and `afconvert` is
   present for AAC. Generate once from the bundled `minna` data:

   ```bash
   # one-time, run on macOS; writes Resources/minna/audio/{lesson}_{safeRomaji}.m4a
   say -v Kyoko -o out.m4a --data-format=aac "<cleanWord(kana)>"
   ```

   Key it by `lesson_romaji` (romaji is only unique within a lesson) or dedup by the
   spoken kana string (identical readings → one file). ~2089 clips, roughly tens of
   MB at AAC. Note: `say`'s Kyoko is the **same engine** as `AVSpeechSynthesizer`'s
   Kyoko — the win of pre-generating is consistency + offline + no on-device voice
   dependency (and the option to use an *enhanced* voice at generation time), not raw
   quality.

When audio lands, swap `SilentPronouncer` → `SystemTTS` or `BundledAudio`; that also
switches on **Listening** and **Read All** (see `04-lessons.md`).
