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

Three Japanese faces plus one title face, all through `Theme` —
`jp/jpBold/jpStrokes(_ size:)` and `title(_ style:weight:)` /
`display(_ size:)` / `titleUIFont(...)`:

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

**All three Japanese faces have full Latin coverage, and that is a trap.**
Verified with CoreText: `HiraMaruProN-W4` and `HiraginoSans-W6` render Latin,
Cyrillic and Western European accents from their own glyph tables, and the
bundled `KanjiStrokeOrders` file has real glyphs for a–z, A–Z and 0–9 too. So
romaji or a translation drawn with one of them came out *plain*, never as tofu
— which is why several slots sat on the wrong face unnoticed. The rule is that
**the face follows the content's script at runtime, not the screen**, and the
two enums that own a switchable slot say so in one place each: `KForm.isJapanese`
(hiragana/katakana yes, romaji no) and `VForm.isJapanese` (kana/kanji yes,
romaji and translation no). Every switchable slot reads one of those:

| Slot | Japanese | Latin |
|---|---|---|
| Kana browser tile (26) and its toolbar glyph (15) | `jpBold` | `display` |
| Kana quiz prompt, Classic (120) / Swipe (150) | `jpStrokes` | `display` |
| Kana quiz options, Classic (26) / Swipe (30) | `jpBold` | `display` |
| Train prompt (44) | `jp` | `display` (romaji) · system `.largeTitle` (translation) |
| Challenge prompt (38) | `jp` | `display` (romaji) · system `.title` (translation) |

A *translation* is the one case that doesn't take `display`: it's prose in the
UI language, so it takes the plain system font at a Dynamic Type style — the
same neutral treatment every other translation gets. `KanjiStrokeOrders` is
never used for romaji: stroke order is the entire reason it's there, and Latin
letters have none.

- **`Theme.title(_ style:weight:)`** — **SF Rounded** (`design: .rounded`), no
  bundled file. Every heading in the app: screen and card headings, navigation
  titles (via `titleUIFont`, below), the intro cards' headlines, result/verdict
  headlines, section prompts, list section headers, row names, the paywall's
  price table, the flashcard grade buttons, Kana Write's score row.
- **`Theme.display(_ size:)`** — the same face at a **fixed** point size: the
  Latin counterpart to `jp`/`jpBold`/`jpStrokes`, for slots sized like a
  Japanese glyph rather than styled like text. Two kinds of caller, both
  deliberately outside the Dynamic Type contract:
  - *Layouts with no slack* — the Challenge result percentage (56) between a
    stars row and a verdict line, and Kana Write's romaji prompt (40) directly
    above a drawing canvas. Through `title(.largeTitle)` they'd shrink to 34pt
    and then grow until they pushed their neighbours off screen.
  - *The Latin half of a script-switchable slot* — the table above. Those must
    take the **same** point size as the Japanese face they alternate with, or
    switching script would resize the card.
- **`Theme.titleUIFont(size:weight:relativeTo:upTo:)`** — the UIKit twin, used
  for navigation bar titles only (see below).

Everything else uses Dynamic Type text styles (`.headline`, `.subheadline`,
`.caption`, etc.) rather than fixed point sizes, so large-text accessibility
settings work for free.

### Why the titles are rounded, and where the line is

`Theme.jp` is *already* a rounded face (Hiragino Maru Gothic), so the Latin
headings were the half that was out of step: a card whose Japanese word was
soft and whose heading above it was plain SF Pro. Rounding the headings closes
that gap from the Latin side, without touching the Japanese faces.

`design: .rounded` rather than a bundled display font, deliberately — a
Latin-only font file would break both Dynamic Type scaling and the system's
per-script fallback for the 10 non-Latin UI languages.

**Descriptions stay on the system font.** `.subheadline`, `.footnote`,
`.caption`, list-row subtitles, explanatory paragraphs — all neutral. The
hierarchy *is* the contrast between a rounded heading and a plain sentence; a
rounded paragraph would just read as a skin. Answer options (`QuizOptionButton`,
`SwipeOptionChip`) are content, not headings, and stay neutral too.

**Navigation titles are included, via UIKit.** SwiftUI has no
`.navigationTitle(_:font:)` and `.font()` on the surrounding view doesn't reach
the bar, so the only route is `UINavigationBarAppearance` — installed once at
launch by `NavigationBarTitle.install()` in `AppBootstrap.swift`. The appearance
proxy *does* reach SwiftUI's bars: `NavigationStack` reads
`UINavigationBar.appearance()` as it builds one.

Three details there are load-bearing, and all three look arbitrary enough to be
"cleaned up" into bugs:

- **The `UIFontMetrics` call in `Theme.titleUIFont`.** A font from
  `scaledFont(for:maximumPointSize:)` with *no* trait collection stays
  *scalable* — each label re-resolves it against its own trait collection on
  every layout, so a nav title follows a Dynamic Type change made long after
  launch and honours the maximum when it does. Resolve it against a trait
  collection, or hand over a plain `systemFont`, and it freezes at whatever the
  text size was at launch.
- **`maximumPointSize` restores a cap the system otherwise loses.** An explicit
  font opts the bar out of the growth limit it applies to its own title
  (measured on iOS 26: stock inline runs 17 → 19 → 21pt then holds at 21). The
  ceilings match where the system itself stops — 21pt inline, 60pt large.
  Without them, 48pt of title lands in a 44pt bar, straight through the toolbar
  buttons.
- **`scrollEdgeAppearance` is deliberately left nil.** Nil means
  "`standardAppearance` with the background dropped", so the title face carries
  into the scrolled-to-top state for free. Assigning an appearance there would
  hand that state a default *background*, turning every transparent-at-the-top
  bar in the app opaque.

Fresh `UINavigationBarAppearance()` objects are used rather than mutating the
proxy's own: `UINavigationBar.appearance()` is a recorder, not a live object, so
reading `.standardAppearance` back off it returns an empty appearance and the
mutate-and-put-back shape would silently drop the bar's default background.

### What the 17 languages actually get

SF Rounded covers Latin (including Vietnamese's stacked diacritics), Cyrillic
and Greek — 2785 glyphs, verified with CoreText against every character in
`nihongo/UIStrings.json`. Fully rounded: **en, de, es, fr, vi, ru, fil, id**.
The other nine (zh, zh-Hant, th, my, bn, hi, ta, te, ko) render their digits,
Latin and punctuation rounded and fall back per-script for the rest — to
PingFang, Thonburi, Myanmar Sangam, SF Bangla / Devanagari / Tamil / Telugu and
Apple SD Gothic Neo respectively. **Every fallback is the same face those
scripts already use under the plain system font**, so no non-Latin language
changes appearance and nothing anywhere renders as tofu.

iOS 26 ships rounded variants for exactly five scripts — Latin/Cyrillic/Greek
(`SFUIRounded`) plus Arabic, Armenian, Georgian and Hebrew — and none for Thai,
Myanmar, CJK, Hangul or any Indic script, so there is nothing friendlier to
switch those nine to without bundling a font. Where a rounded variant *does*
exist the cascade picks it up automatically (a rounded base resolves Hebrew to
`SFHebrewRounded`, not `SFHebrew`), so adding Arabic or Hebrew to the 17 later
would get a rounded heading for free.

### Line heights per script, and what that costs a fixed-height box

Measured with CoreText over every string in `UIStrings.json` and all 35 513
vocabulary translations in `MinnaData.json`. Line box = ascent + descent +
leading, which is the baseline-to-baseline distance SwiftUI's `Text` uses.

| Script | Line box @17pt | vs Latin | Headroom to its own ink |
|---|---|---|---|
| Latin, Han, Hangul | 20.0–20.5pt | 1.00× | 3.3–4.6pt (fr/vi: **0.06–0.44pt**) |
| Thai | 23.4pt | 1.17× | **−0.28pt** |
| Devanagari, Bengali, Tamil, Telugu | 26.1pt | 1.30× | 1.4–5.5pt |
| Myanmar | 37.1pt | **1.85×** | 11.0pt |

Two results that contradict the obvious guess:

- **Burmese does not clip.** Noto Sans Myanmar reserves 37pt of box for 26pt of
  ink, so its stacked marks have more room than any other script here. What
  Burmese breaks is *height budgets*, not leading: one Burmese line costs what
  two Latin lines cost, so it's the language that decides whether a fixed-height
  container works.
- **Thai is the only script whose ink exceeds its own box** — by 0.28pt at 17pt,
  between the deepest descender (ญ/ฐ) and the tallest tone-over-vowel stack. It's
  a touch, not a clip, and it only shows where a Thai paragraph runs to several
  lines (the paywall terms, Settings descriptions, the intro body copy). Nothing
  in the app sets `lineSpacing`, deliberately: the fix is a root-level
  `.lineSpacing(2)`, but a global 2pt also costs the 154.5×54pt quiz option box —
  it takes its tail-truncating share from 0.13% to 0.25% — so it's a trade to
  make on purpose rather than a bug to patch.

Consequence for the two shrink-to-fit answer controls, which hold *translations*
and therefore meet all 17 scripts:

- **`QuizOptionButton`** — `OptionGrid` rows are a fixed 74pt, so the text box is
  154.5×54pt. `minimumScaleFactor` is **0.65**, not 0.5: at 0.5 the worst glosses
  rendered at 8.5pt (Burmese) and 8.8pt (German, Vietnamese); 0.65 holds every
  language at ≥11.2pt. The price is 46 glosses that tail-truncate instead of
  shrinking rather than 14 — 0.13% of the data instead of 0.04%.
- **`SwipeOptionChip`** — `minHeight`, not a fixed height, so it may grow;
  `lineLimit(4)` and `minimumScaleFactor(0.6)` let it. At the old `(3, 0.4)` the
  worst cases in en/fr/de/vi/my all bottomed out on the 8pt floor because three
  lines was all they were allowed; `(4, 0.6)` never renders below 12pt and moves
  the tail-truncating share only from 0.08% to 0.16%.

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
