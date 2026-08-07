# 07 — UX / UI

The visual identity carried over from the original RN app — near-monochrome +
one teal accent, green/red reserved strictly for answer feedback — rebuilt with
idiomatic SwiftUI components and full Dynamic Type / Dark Mode / VoiceOver
support the RN app never had. Source of truth: `nihongo/Theme.swift`.

## Color (`Theme`, dynamic per light/dark)

`Theme.dynamic(_:_:)` picks a different `UIColor` per `userInterfaceStyle`,
not just a semantic system color — the identity colors need per-mode tuning
that a single fixed value can't provide (the originals were designed against
a white background):

| Token | Light | Dark | Role |
|---|---|---|---|
| `accent` | `#0FB0BE`-ish teal | brightened teal | active state, primary tint, `.tint(Theme.accent)` at the root |
| `correct` | `#2ECC40`-ish green | softened green | right-answer border, everywhere |
| `wrong` | `#FF4136`-ish red | softened red | wrong-pick border, everywhere |
| `surface` | `.systemBackground` (white) | `.secondarySystemBackground` | card/tile fill |
| `canvas` | `.secondarySystemBackground` | `.systemBackground` | screen background behind cards |
| `line` | `.separator` | white @ 22% alpha | card/tile hairline |
| `shadow` | black @ 10% alpha | `.clear` | card drop shadow |

Two things worth understanding, not just copying:

- **`surface`/`canvas` swap their underlying system-color roles between light
  and dark.** Cards must sit *lighter* than the screen in both modes — white
  card on light-gray screen in Light Mode, but an *elevated* gray card on a
  near-black screen in Dark Mode. The plain system semantic pair inverts that
  relationship in dark (black card on gray screen), so `Theme` deliberately
  swaps which system color plays which role per appearance rather than using
  the "obvious" `.systemBackground`/`.secondarySystemBackground` pairing
  uniformly.
- **Feedback colors are softened, not just recolored, in dark** — full-
  saturation `#2ECC40`/`#FF4136` on near-black reads as neon glow; the dark
  variants are toned down so they still read as "right"/"wrong" without
  fighting the background.
- Green/red stay **exclusive to answer feedback** — that restraint (no other
  use of saturated color anywhere in the UI) is most of what makes the app
  still feel like the RN original.

## Typography

Three named fonts, all through `Theme.jp/.jpBold/.jpStrokes(_ size:)`:

- **`Theme.jp`** — `HiraMaruProN-W4`, iOS's built-in rounded Hiragino Maru
  Gothic. Used for most Japanese body/headword text (Learn's assembled
  answer, Lessons Quiz prompt, Flashcard faces, Today's card). No bundled font
  file — if a rounded bundled typeface (e.g. Zen Maru Gothic) is ever wanted
  instead, this is the one place to change it.
- **`Theme.jpBold`** — `HiraginoSans-W6` (the Maru face has no bold weight on
  iOS). Used for kana glyphs in the Kana tab (tile browser, quiz option text).
- **`Theme.jpStrokes`** — **`KanjiStrokeOrders`**, a bundled third-party font
  (BSD-licensed — see `context/../nihongo/Legal` and `LegalDoc.licenses`)
  whose glyphs render with visible numbered stroke-order annotations. Used
  deliberately for the Kana quiz prompt (Classic/Swipe) — so a learner absorbs
  stroke order passively while quizzing — and as the drawing/scoring template
  in Kana Write (`KanaSketch`, see `03-kana.md`), where the baked-in digits are
  stripped before display or scoring.

Everything else uses Dynamic Type text styles (`.headline`, `.subheadline`,
`.caption`, etc.) rather than fixed point sizes, so large-text accessibility
settings work for free.

## The Tinder-like swipe UI — one shared visual language, several screens

The most distinctive interaction pattern in the app, and it's genuinely
**one implementation** (`FlashcardScreen` in `Flashcards.swift`,
`CardPager` in `CardPager.swift`) reused across contexts, not four separate
similar-looking screens:

- **Lessons Flashcards** and **Kana Flashcards** are the literal same
  `FlashcardScreen<Element, Face>` generic, instantiated over `Vocab` and `K`
  respectively.
- **Kana Swipe quiz** hand-rolls its own drag gesture (2 fixed options instead
  of a pass/fail grade) but borrows the same `CardStackPeek` backdrop,
  `SwipeStamp` corner previews, and `choiceChip` chrome so it visually matches
  the flashcard screens.
- **Today** uses `CardPager` (the ordered-paging half of the pattern, not the
  swipe-to-grade half) over the same `CardStackPeek` backdrop, so paging
  through the day's 7 words reads as "a stack of cards" too, consistent with
  Flashcards.
- **Learn** (ordered mode) also uses `CardPager` for its next/prev card swipe.

Concretely: drag horizontally with a slight rotation proportional to drag
distance; past a threshold (80–100pt depending on screen), the card flings
fully off-screen and the next one enters from the opposite side; a corner
`SwipeStamp` previews the outcome you're dragging toward, scaled by how far
past the threshold you are.

## Interaction & feedback principles (kept from the original)

1. **Border-color feedback, not fills** — green correct / red wrong as a
   stroke around cards/tiles/buttons, never as a background fill. Consistent
   across Kana browser tiles, every quiz's option buttons, and Kana Write's
   score readout.
2. **Answer then lock** — every multiple-choice screen disables its options
   the instant one is picked, until the learner explicitly advances
   ("Next"). No accidental double-answers.
3. **Progressive disclosure** — `CardOptionsBar`'s per-field visibility
   toggles (kanji/kana/romaji/translation/sound) let a learner hide fields to
   self-test; default is all-visible.
4. **Tap-anywhere-to-hear** — every vocab/kana surface (list row, tile, card,
   quiz prompt) is a pronunciation trigger, routed through `Pronouncer`.
5. **Memory in the UI** — Kana tiles carry their last quiz/write result color
   so progress is visible ambiently, without a separate stats screen.

## Iconography

SF Symbols throughout — no bundled icon font. Notably the Kana tab uses SF
Symbol `character.book.closed`, not the RN app's あ text glyph (a deliberate
choice made during the rebuild: consistent with every other tab using an SF
Symbol, and VoiceOver-correct without a custom accessibility label).

## Layout notes worth knowing

- **Kana browser tiles and Learn's tile grid both compute an explicit square
  size from a measured container width** (`onGeometryChange` +
  `width - spacing*(cols-1)) / cols`) rather than relying on
  `.aspectRatio(1, contentMode: .fit)` inside a flexible grid — the aspect-
  ratio approach doesn't reliably divide space into *even* squares across
  sibling cells in this layout shape, so both screens use the same
  measure-then-divide pattern instead.
- **Per-tab ad banners live in a `VStack`, not `.safeAreaInset`** — see
  `00-overview.md` for why (a `NavigationStack`-pushed screen doesn't see an
  ancestor's safe-area inset, so a bottom-anchored control like Quiz's "Next"
  button used to render under the ad).
