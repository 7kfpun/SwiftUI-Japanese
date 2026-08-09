---
name: app-store-screenshots
description: Generate the framed, titled App Store marketing screenshots in fastlane/screenshots/ with fastlane/generate_framed_screenshots.py — which must run under `arch -x86_64 python3` because the installed Pillow is x86_64-only — and audit the localized copy with its `--check` mode before rendering. Use when asked to "regenerate the screenshots", "update the screenshot titles/captions", "add a locale to the screenshots", "the Russian screenshots look wrong / show boxes", or when a headline is clipped or renders as tofu. Also documents how the raw simulator captures are produced, and that per-locale fonts are chosen for glyph coverage, not taste.
when_to_use: regenerate App Store screenshots, framed screenshots, screenshot captions, screenshot titles, add a screenshot locale, tofu boxes in screenshots, clipped headline, Pillow architecture error, arch -x86_64, incompatible architecture x86_64 arm64, capture raw screenshots, generate_framed_screenshots
allowed-tools: Bash, Read, Edit
---

# Generating the framed App Store screenshots

`fastlane/screenshots/<locale>/<key>-<device>.png` is **generated** by
`fastlane/generate_framed_screenshots.py` from the hand-captured raw shots in
`fastlane/screenshot_raw/`. `CLAUDE.md` lists it as a generated tree: never touch
the PNGs, edit the script.

Pure Pillow, no ImageMagick (frameit's own tool needs `convert`, which isn't
installed here). It writes final upload filenames straight into the locale folders
with no staging step.

## Hard rule: `arch -x86_64 python3`, always

The Pillow wheel installed on this machine is x86_64-only. Plain `python3` on this
Apple Silicon box resolves to the arm64 slice and dies at import:

```
ImportError: dlopen(.../PIL/_imaging.cpython-312-darwin.so, 0x0002):
  (mach-o file, but is an incompatible architecture (have 'x86_64', need 'arm64e'…))
```

That error is about the *interpreter*, not the script, and reinstalling Pillow
"to fix it" is a bigger change than it looks. Prefix every invocation:

```sh
arch -x86_64 python3 fastlane/generate_framed_screenshots.py --check
arch -x86_64 python3 fastlane/generate_framed_screenshots.py
```

## 1. `--check` before you render

`--check` renders nothing. It audits every string in `LOCALES` against the font
that locale is assigned in `LOCALE_TYPOGRAPHY`, at the real font size for each of
the three device canvases, and catches the two failures that are **invisible at
render time**:

1. a character with no glyph in that font → tofu boxes in the uploaded image
2. a wrapped line wider than the 88% text column → text runs off the canvas

```sh
arch -x86_64 python3 fastlane/generate_framed_screenshots.py --check          # all locales
arch -x86_64 python3 fastlane/generate_framed_screenshots.py --check ru       # one locale
```

It exits non-zero on failure and prints, per locale and device, the face in use
and how close the worst line came:

```
ru: SFNSRounded.ttf index=0 weight=Bold wrap=word
  6.9: 1320px canvas, 20 strings / 21 rendered lines, widest 91% of the 1162px text column - ok
```

Anything above ~95% is worth shortening — it's fitting, but only just, and the
next copy edit in that locale will overflow. Run `--check` after **any** copy or
font edit. It currently passes for all seven locales.

## 2. Render

```sh
arch -x86_64 python3 fastlane/generate_framed_screenshots.py            # everything
arch -x86_64 python3 fastlane/generate_framed_screenshots.py de-DE      # one locale
arch -x86_64 python3 fastlane/generate_framed_screenshots.py 01-today   # one screen, all locales
arch -x86_64 python3 fastlane/generate_framed_screenshots.py de-DE:01-today
```

Use a filter while iterating on copy or layout; a full run writes 154 files.
`skip …(no raw capture)` lines are expected — only two screens were ever captured
on the iPad simulator, so most keys have no `ipad13` output.

Three device buckets, and `deliver` resolves which bucket a file belongs to from
its **pixel size alone** (the `-6.9` / `-6.3` / `-ipad13` suffix only keeps names
unique within a folder):

| suffix | canvas | ASC bucket |
|---|---|---|
| `6.9` | 1320×2868 | `APP_IPHONE_67`, the mandatory largest size |
| `6.3` | 1206×2622 | `APP_IPHONE_61` |
| `ipad13` | 2064×2752 | `APP_IPAD_PRO_3GEN_129` |

## Per-locale fonts are glyph coverage, not taste

`LOCALE_TYPOGRAPHY` overrides `DEFAULT_TYPOGRAPHY` per locale. Every entry there
exists because the default face physically cannot draw that locale:

- **Arial Rounded MT Bold** (the default, and the right face for the app's rounded
  identity) carries **241 glyphs — Latin-1 and nothing more**. No Cyrillic at all,
  no Latin Extended Additional (so none of Vietnamese's stacked-diacritic vowels
  ế ộ ữ ằ ọ), no Thai, no CJK.
- **`ru`, `vi` → SF NS Rounded**, pinned to `weight="Bold"` because that file ships
  every weight in one variable font and defaults to an anaemic Regular. It is the
  only rounded face here covering both Cyrillic and the precomposed Vietnamese
  vowels.
- **`zh-Hant`, `zh-Hans` → STHeiti Medium** (no rounded CJK face ships with macOS),
  with `wrap="char"`: Chinese has no spaces, so word-wrapping would leave one
  unbreakable overflowing line, and every Han character is its own cluster so
  breaking anywhere is safe.
- **`th` → Sukhumvit Set Bold** (face index 5), **not Thonburi**, for a mechanical
  reason. Thonburi's combining vowels and tone marks each carry a *non-zero*
  advance width and their outlines include the dotted-circle placeholder, because
  Thonburi expects Apple's AAT shaper to substitute zero-width variants. Pillow
  here is **built without libraqm and does no shaping at all**, so it renders
  Thonburi Thai as a row of dotted circles. Sukhumvit Set's marks are genuinely
  zero-advance and land correctly unshaped. Don't "upgrade" the Thai font without
  running `--check` and looking at the output.

Adding a locale means adding it to `LOCALES` **and** deciding its face — if its
script isn't Latin-1, the default will fail `--check`, which is the point.
`LOCALE_ALIASES` (`zh-Hans` → `zh-Hant`) renders one locale's copy under another
folder name.

## Two caps that silently drop work

- **10 images per device size per locale.** Apple and `deliver` both cap it, so
  `COPY`/`LOCALES` is curated to exactly 10 keys — note the deliberate gaps at
  `05` and `10`/`13`/`14`. Add an eleventh and only the first ten alphabetically
  upload, with no error.
- **Every subdirectory of `fastlane/screenshots/` is read as a locale** by
  `Deliver::Loader::LanguageFolder`. Nothing but locale folders may live there —
  that is why the raw captures sit in a separate top-level `screenshot_raw/`. Don't
  add a scratch or backup folder under `screenshots/`.

Seven locale folders exist today (`de-DE`, `en-US`, `ru`, `th`, `vi`, `zh-Hans`,
`zh-Hant`) against 13 localizations on the App Store version, so most locales show
the English-language screenshots. That's a scope decision, not a gap to fill
silently.

## Where the raw captures come from — needs explicit permission

`fastlane/screenshot_raw/iphone/*.png` and `ipad/*.png` are produced by
`nihongoUITests/ScreenshotTests.swift`, one small test per screen, each launching
the app fresh so a hiccup costs one shot rather than the run. It launches with
`-SCREENSHOTS` (hides the ad banner) and `-introAnswered YES` (skips the intro,
which is a `fullScreenCover` over the whole TabView — without it every capture
would be a picture of the tour).

**This launches the app in a simulator.** `CLAUDE.md` forbids that, with one
explicit exception: *capturing App Store screenshots, only when explicitly asked.*
So don't run it as part of "regenerate the screenshots" — regenerating means
re-framing existing raw captures. Ask first, and only if the raw captures
themselves are what's wrong.

When asked: run `nihongoUITests/ScreenshotTests` against the iPhone 17 Pro
(`6.3`-sized raws) or iPad Pro 13-inch (M5) simulator, then export the kept
attachments — each is named for its key (`01-today`, `08-lessons`, …) via
`XCTAttachment.name` with `.keepAlways`:

```sh
xcrun xcresulttool export attachments \
  --path <path>.xcresult --output-path /tmp/shots
```

That writes UUID-named files plus a `manifest.json` mapping
`suggestedHumanReadableName` → `exportedFileName`; rename by that mapping into
`fastlane/screenshot_raw/<device>/<name>.png`. `fastlane/screenshot_raw/watch/`
exists but no code path consumes it — the script has no watch device bucket.

## Uploading

Generating is not uploading. `fastlane ios screenshots` (the `deliver` lane) is the
upload, it is outward-facing, and `CLAUDE.md` says **never publish without being
asked**. It also shares both of the traps in the `push-app-store-metadata` skill —
the pinned `PATH=/usr/bin:… /usr/bin/bundle exec` invocation, and `deliver`'s
inability to see a version whose state isn't in its hardcoded filter. Read that
skill before running it, starting with its read-only `asc_state.rb`.
