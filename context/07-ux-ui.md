# 07 — UX / UI

The visual identity of the RN app, extracted from source, plus a SwiftUI direction.
Scope: **Kana + Lessons** only. Source of truth for tokens:
`reference-rn/app/utils/styles.js` and per-component `StyleSheet` blocks.

## Design tokens

### Color

| Token | Value | Role |
|---|---|---|
| theme (background) | `#F7F7F7` | app background behind cards (25 uses) |
| white | `#FFFFFF` | card / tile / row surfaces |
| black | `#000000` | primary text |
| gray | `#212121` | strong text (`iOSColors.gray`, 29 uses) |
| midGray | `#484848` | header tint / secondary text |
| **accent** | `iOSColors.tealBlue` (~`#0FB0BE`) | active tab, selected states, primary accent (24 uses) |
| **correct** | `#2ECC40` (green) | right-answer border/flash (quiz + kana) |
| **wrong** | `#FF4136` (red) | wrong-pick border/flash |
| lightGray / silverGray | `iOSColors.lightGray` / `midGray` | inactive borders, placeholder |
| shadow | `#E0E0E0`, y-offset 2, radius 2, opacity .8 | subtle card elevation |

(Out-of-scope palette: `#3b5998` FB, `#dd4b39` Google, `iOSColors.yellow` bookmark
stars. Ignore.)

The palette is deliberately **near-monochrome + one teal accent**, with green/red
reserved *exclusively* for answer feedback. That restraint is the whole look.

### Typography

Font weights actually used (by frequency): **`300` dominates (34×)**, then `500`
(headers), occasional `800`/`600` for emphasis. The feel is **light and airy**.

Font-size scale (from usage counts):

| px | Use |
|---|---|
| 60 | kana quiz question (the giant prompt) |
| 26–32 | vocab headword / kana tile hiragana |
| 20–24 | card kanji, section titles |
| 16–18 | body, romaji, translation, options (most common) |
| 12–14 | captions, index numbers, tab-ish labels |
| 10 | tab bar labels |

### Shape & spacing

- Cards: `borderRadius: 16`, white on `#F7F7F7`, soft shadow. Centered content.
- Tiles / option buttons: rounded rects with a **colored border** as the state
  channel (white/none → green/red), not fills.
- Generous padding; content vertically centered on iOS.

### Iconography

`Ionicons` (`ios-*`) → map to **SF Symbols**. The Kana tab used a text glyph **あ**
rather than an icon — worth keeping as a distinctive touch.

| RN tab / icon | SF Symbol |
|---|---|
| lessons `ios-list` | `list.bullet` |
| kana `あ` glyph | **`character.book.closed`** (decided: use SF Symbol, not the あ text) |
| speaker (play) `ios-play` / volume | `speaker.wave.2.fill` |
| next / prev chevrons | `chevron.right` / `chevron.left` |
| shuffle | `shuffle` |
| search | `magnifyingglass` (free with `.searchable`) |

## Screen-by-screen layout

### Tab bar
White background, **tealBlue active / black inactive**, 10px labels, icon-over-label.
2 tabs in the rebuild (Kana, Lessons).

### Kana browser
Top segment/pager (清音 / 濁音 / 拗音) → scrollable **grid of tiles**. Each tile: big
hiragana (26px, weight 300) on top, katakana + romaji (16px, gray) beneath. Tile
**border color = last quiz result** (green/red/none). Tap = pronounce.
Grid preserves empty cells for alignment (the あいうえお shape).

### Kana quiz
Huge 60px question glyph up top; the **from/to form labels are tappable** to swap
direction. Below: **2×2 grid** of option buttons. On answer: correct → green border,
your wrong pick → red border, lock until **Next**. Score `n / total` in the header.

### Lessons browser
Grouped list (Beginning 1/2, Advanced 1/2) of tappable lesson rows; **search field**
at top. Search results = flat list of vocab rows each tagged with its lesson number.

### Select-mode
A short list/grid of mode cards (`mode-item.js`): title + icon per mode (Vocab List,
Learn, Quiz, Listening, Read All). (RN drew a lock badge for gated modes — **drop**,
all open.)

### Vocab list
Rows: left = kana (bold) + kanji if different; right = translation + index. Tap =
pronounce.

### Learn (tile reconstruction)
Centered **Card** (rounded 16, white): shows kana slots with the assembled answer
overlaid, plus optional kanji/romaji/translation per the toggle bar. Correct/incorrect
icon. Below the card: the **shuffled character tiles** to tap. Bottom bar: Prev/Next
(ordered) or Random, plus a reveal control. A `CardOptionsBar` of small toggle
buttons (kanji/kana/romaji/translation/sound) sits with the card.

### Quiz (MC) / Listening
Same 2×2 option grid + green/red + score as the Kana quiz. Quiz shows the prompt as
text (tappable form labels); **Listening** replaces the prompt with a large speaker
button (audio-dependent → v2).

## Interaction & feedback principles (keep these)

1. **Border-color feedback**, not fills — green correct / red wrong, everywhere.
2. **Answer then lock** — options disable after a pick until Next; no accidental
   double-answers.
3. **Progressive disclosure** — per-field visibility toggles let the learner hide
   kanji/romaji/translation to self-test; default all-visible.
4. **Tap-anywhere-to-hear** — every vocab surface is a pronunciation trigger
   (routes to the deferred `Pronouncer`).
5. **Memory in the UI** — kana tiles carry their last-result color so progress is
   ambient.

## SwiftUI direction — DECIDED: native refresh

**Native refresh that keeps the identity.** Rebuild with idiomatic iOS components
(`List` + `.searchable`, `NavigationStack`, SF Symbols, `TabView`) while preserving
the *identity*: teal accent, thin/light type, oversized kana, and the strict
green/red-border feedback. This buys **Dynamic Type, Dark Mode, VoiceOver, and iPad**
almost for free — none of which the RN app had — and feels current.

(Rejected: a faithful 1:1 port — inherits fixed sizing and no dark mode; not worth it
for a fresh codebase.)

### Concrete SwiftUI mapping for the refresh

```swift
enum Theme {
    static let accent   = Color(red: 0.06, green: 0.69, blue: 0.75)  // tealBlue
    static let correct  = Color(red: 0.18, green: 0.80, blue: 0.25)  // #2ECC40
    static let wrong    = Color(red: 1.00, green: 0.25, blue: 0.21)  // #FF4136
    static let surface  = Color(.systemBackground)                   // was #FFF
    static let canvas   = Color(.secondarySystemBackground)          // was #F7F7F7
}
// Prefer semantic system colors so Dark Mode works; keep accent/correct/wrong fixed.
```

- Set `.tint(Theme.accent)` at the root.
- Card = `RoundedRectangle(cornerRadius: 16)` fill `Theme.surface` + subtle shadow.
- Option/tile state via `.overlay(RoundedRectangle().stroke(stateColor, lineWidth:))`.
- Use **Dynamic Type** text styles (`.largeTitle` for the 60px kana prompt, `.title`
  for headwords, `.body`/`.callout` for romaji/translation) instead of fixed px.
- Keep font weight light (`.fontWeight(.light)`) to match the `300` aesthetic.
- **Add for free:** Dark Mode (semantic colors), VoiceOver labels on tiles/options,
  larger-text support, iPad multi-column via `NavigationSplitView` (optional).

## Decisions (locked)
- **Direction:** native refresh (keep identity). ✅
- **Kana tab icon:** SF Symbol `character.book.closed` (not the あ glyph). ✅
- **Kana browser paging:** **segmented `Picker`** at top, content below — not a paged
  `TabView`. For 3 labeled categories a segmented control shows all labels, allows
  random access, and reads correctly under VoiceOver. ✅
- **Tap-anywhere-to-hear:** kept as a core principle — every vocab surface (list row,
  kana tile, card, quiz prompt) is a pronunciation trigger routing to `Pronouncer`
  (no-op in v1). ✅

## Still open
- Whether Learn keeps the press-and-hold reveal (RN `CircleButton`) or a simpler
  toggle. (Minor; decide at Phase 2.)
