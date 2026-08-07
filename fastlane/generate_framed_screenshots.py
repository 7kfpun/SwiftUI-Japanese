#!/usr/bin/env python3
"""Composite the raw iOS Simulator screenshots — iPhone captures in
fastlane/screenshot_sources/raw/iphone/*.png (1206x2622 on the "iPhone 17 Pro"
simulator), iPad captures in fastlane/screenshot_sources/raw/ipad/*.png
(2064x2752 on the "iPad Pro 13-inch (M5)" simulator) — into framed, titled App
Store marketing screenshots: gradient background + bold rounded headline +
official Apple device frame, rendered at the exact pixel resolutions App Store
Connect / fastlane `deliver` require. Pure Pillow, no ImageMagick (frameit's own
tool needs ImageMagick's `convert`, which isn't installed on this machine and
needs sudo/brew doctor fixes to install — this script reimplements the same idea
directly with Pillow).

Note the split between the two trees: everything this script reads and writes
lives under fastlane/screenshot_sources/, and only the final staged copies go in
fastlane/screenshots/. That's deliberate — `deliver` treats *every* subdirectory
of its screenshots_path as a locale folder (see Deliver::Loader::LanguageFolder),
so working directories must not live there.

Usage:
    arch -x86_64 python3 fastlane/generate_framed_screenshots.py [filter]

Run from the repo root. Pass an optional substring filter (e.g. "01-today")
to render just one screenshot while iterating on copy/layout.

NOTE on architecture: the Pillow wheel installed on this machine is x86_64
only; plain `python3` on Apple Silicon resolves to the arm64 slice and can't
load Pillow's compiled extension. Always run this via `arch -x86_64 python3`
(or reinstall an arm64-native Pillow with `pip install --force-reinstall
--no-binary :all: pillow` if you'd rather fix that properly).

Outputs go to fastlane/screenshot_sources/framed/<locale>/6.9/*.png,
.../6.3/*.png, and .../ipad13/*.png — matching the APP_IPHONE_67 "6.9-inch"
mandatory/largest bucket, the APP_IPHONE_61 "6.1-6.3-inch" bucket, and the
APP_IPAD_PRO_3GEN_129 "13-inch iPad" bucket. To stage them for `fastlane
screenshots` (the `deliver` lane in fastlane/Fastfile), copy them into
fastlane/screenshots/<locale>/ with unique filenames per device (deliver
detects the target device purely by each PNG's pixel resolution, not by
filename, but every file in a locale folder needs a unique name) — e.g.:

    for locale in en-US de-DE zh-Hant zh-Hans; do
      for dev in 6.9 6.3 ipad13; do
        for f in fastlane/screenshot_sources/framed/$locale/$dev/*.png; do
          cp "$f" "fastlane/screenshots/$locale/$(basename "$f" .png)-$dev.png"
        done
      done
    done

zh-Hans has no copy of its own in LOCALES below; it reuses zh-Hant's rendered
images (plain file copy after generating), same as the iPhone buckets already do.

Apple/deliver caps each device-size screenshot set at 10 images per locale,
so with 14 source screenshots only the first 10 alphabetically (01-10) will
upload per device size — trim COPY below to <=10 entries, or rename/reorder,
if you want a different 10 featured.

Device frame assets (official, Facebook Design-redrawn Apple device frames,
used by fastlane's own `frameit` action) are vendored in
fastlane/screenshot_frames/. If missing, they're fetched from
https://fastlane.github.io/frameit-frames/latest/<filename> (the same public,
versioned CDN frameit itself downloads from — see
fastlane's frameit/lib/frameit/frame_downloader.rb for reference).
"""
import os
import sys
import urllib.parse
import urllib.request

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "fastlane/screenshot_sources/raw/iphone")
IPAD_RAW_DIR = os.path.join(ROOT, "fastlane/screenshot_sources/raw/ipad")
FRAMES_DIR = os.path.join(ROOT, "fastlane/screenshot_frames")
OUT_DIR = os.path.join(ROOT, "fastlane/screenshot_sources/framed")
FRAMES_CDN = "https://fastlane.github.io/frameit-frames/latest"

FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
FONT_SUB = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"

# Brand colors: BLUE sampled from nihongo/Assets.xcassets/AppIcon.appiconset/AppIcon.png,
# TEAL read from nihongo/Assets.xcassets/AccentColor.colorset/Contents.json (also
# hardcoded as --accent: #0FB0BF in scripts/build-web.py) — keeps the App Store
# screenshots on-brand with the app icon and the marketing site.
BLUE = (12, 83, 148)
TEAL = (15, 176, 191)

# Device targets. `off` / `off_w` come from frameit-frames' offsets.json: where
# (in the frame PNG's own native pixel grid) the screenshot layer must be
# pasted, and how wide it must be resized to, before the frame art is
# layered on top.
DEVICES = {
    "6.9": dict(canvas=(1320, 2868), frame="Apple iPhone 17 Pro Max Silver.png",
                off=(75, 66), off_w=1320),
    "6.3": dict(canvas=(1206, 2622), frame="Apple iPhone 17 Pro Silver.png",
                off=(72, 69), off_w=1206),
    # 13-inch iPad (ASC's APP_IPAD_PRO_3GEN_129 bucket). Raw captures come from
    # the "iPad Pro 13-inch (M5)" simulator at its native 2064x2752 — the canvas
    # matches that 1:1. No frameit-frames asset exists yet for the M4/M5 13-inch
    # panel, so this reuses the 12.9-inch (4th gen) frame (2048x2732, near-identical
    # aspect) purely as decorative device art; it doesn't affect the required
    # output pixel size.
    "ipad13": dict(canvas=(2064, 2752), frame="Apple iPad Pro (12.9-inch) (4th generation) Silver.png",
                   off=(96, 102), off_w=2048, raw_dir=IPAD_RAW_DIR),
}

# headline, subtitle for each raw screenshot (<raw dir>/<key>.png), per App
# Store Connect locale. The screenshots themselves are the same
# English-UI captures for every locale (re-capturing the app UI in each
# language is out of scope here — "just the frame") — only the marketing
# title/subtitle overlay is localized.
#
# Curated to exactly 10 — Apple/deliver caps each device-size screenshot set
# at 10 images per locale, so all 10 of these upload cleanly with nothing
# skipped. Dropped from the original 14 (still available as raw captures in
# fastlane/screenshot_sources/raw/iphone/*.png if you want to swap any back in):
#   05-kana-swipe        - redundant with quiz/flashcards, generic UX pattern
#   10-lesson-flashcards - redundant with kana flashcards + lesson-learn
#   13-settings          - settings screens don't sell an app
#   14-paywall           - best practice: never lead with your paywall
LOCALES = {
    "en-US": {
        "01-today": ("Track your progress", "Every day, at a glance"),
        "02-kana-table": ("Hiragana & Katakana", "The complete kana charts"),
        "03-kana-flashcards": ("Kana flashcards", "Flip, listen, remember"),
        "04-kana-quiz-classic": ("Kana quizzes", "Test yourself, kana by kana"),
        "06-kana-listening": ("Listening practice", "Train your ear with native audio"),
        "07-kana-write": ("Write practice", "Real stroke order, real memory"),
        "08-lessons": ("50 Minna no Nihongo lessons", "Every lesson, right on your phone"),
        "09-vocab-list": ("We speak your language", "Every word explained in 17 languages"),
        "11-lesson-learn": ("Learn mode", "Swipe through new words with audio"),
        "12-lesson-quiz": ("Lesson quizzes", "Check what you've really learned"),
    },
    "de-DE": {
        "01-today": ("Verfolge deinen Fortschritt", "Jeden Tag auf einen Blick"),
        "02-kana-table": ("Hiragana & Katakana", "Die kompletten Kana-Tabellen"),
        "03-kana-flashcards": ("Kana-Karteikarten", "Umdrehen, hören, merken"),
        "04-kana-quiz-classic": ("Kana-Quiz", "Teste dich, Kana für Kana"),
        "06-kana-listening": ("Hörverständnis", "Trainiere dein Ohr mit Originalaudio"),
        "07-kana-write": ("Schreibübung", "Echte Strichfolge, echtes Gedächtnis"),
        "08-lessons": ("50 Minna-no-Nihongo-Lektionen", "Jede Lektion direkt auf deinem Handy"),
        "09-vocab-list": ("Wir sprechen deine Sprache", "Jedes Wort erklärt in 17 Sprachen"),
        "11-lesson-learn": ("Lernmodus", "Neue Wörter mit Audio durchblättern"),
        "12-lesson-quiz": ("Lektionsquiz", "Prüfe, was du wirklich gelernt hast"),
    },
    "zh-Hant": {
        "01-today": ("追蹤你的學習進度", "每天一目了然"),
        "02-kana-table": ("五十音", "完整的平假名與片假名表"),
        "03-kana-flashcards": ("五十音字卡", "翻牌、聆聽、記住"),
        "04-kana-quiz-classic": ("五十音測驗", "一個一個考考自己"),
        "06-kana-listening": ("聽力練習", "用母語發音訓練耳朵"),
        "07-kana-write": ("書寫練習", "正確筆順，真正記住"),
        "08-lessons": ("50 課大家的日本語課程", "每一課都在你的手機裡"),
        "09-vocab-list": ("我們懂你的語言", "17 種語言，逐字講解"),
        "11-lesson-learn": ("學習模式", "滑動瀏覽新單字並聽發音"),
        "12-lesson-quiz": ("課程測驗", "檢查你真正學到了什麼"),
    },
}

# CJK titles need a font with CJK glyph coverage — Arial Rounded Bold has none.
# "Heiti TC" (bundled in STHeiti Medium.ttc, a stable base macOS system font)
# covers Traditional Chinese cleanly at a reasonably bold weight.
CJK_FONT_BOLD = "/System/Library/Fonts/STHeiti Medium.ttc"
CJK_LOCALES = {"zh-Hant", "zh-Hans"}


def ensure_frame(filename: str) -> str:
    path = os.path.join(FRAMES_DIR, filename)
    if os.path.exists(path):
        return path
    os.makedirs(FRAMES_DIR, exist_ok=True)
    url = f"{FRAMES_CDN}/{urllib.parse.quote(filename)}"
    print(f"downloading missing frame asset from {url}")
    urllib.request.urlretrieve(url, path)
    return path


def make_gradient(w, h, top, bottom):
    top_a = Image.new("RGB", (w, h), top)
    bot_a = Image.new("RGB", (w, h), bottom)
    mask = Image.new("L", (1, h))
    for y in range(h):
        mask.putpixel((0, y), int(255 * (y / (h - 1)) ** 0.85))
    mask = mask.resize((w, h))
    return Image.composite(bot_a, top_a, mask)


def draw_centered_text(draw, cx, top_y, text, font, fill, max_width, line_gap=1.08, wrap="word"):
    # CJK text has no spaces between words, so word-wrapping leaves it
    # overflowing the canvas width — wrap by individual character instead.
    units = list(text) if wrap == "char" else text.split(" ")
    sep = "" if wrap == "char" else " "
    lines, cur = [], ""
    for u in units:
        trial = (cur + sep + u).strip() if sep else (cur + u)
        if draw.textlength(trial, font=font) <= max_width or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = u
    if cur:
        lines.append(cur)

    ascent, descent = font.getmetrics()
    line_h = int((ascent + descent) * line_gap)
    y = top_y
    for ln in lines:
        w = draw.textlength(ln, font=font)
        draw.text((cx - w / 2, y), ln, font=font, fill=fill)
        y += line_h
    return y  # bottom y after last line


def compose_device(raw_shot: Image.Image, frame_path: str, off_x, off_y, off_w) -> Image.Image:
    frame = Image.open(frame_path).convert("RGBA")
    scale = off_w / raw_shot.width
    shot_w = off_w
    shot_h = round(raw_shot.height * scale)
    shot_resized = raw_shot.convert("RGBA").resize((shot_w, shot_h), Image.LANCZOS)

    # Round the screenshot's corners so its square corners don't peek out past
    # the frame's rounded screen cutout (plain screenshots are rectangles;
    # the physical display has rounded corners).
    radius = round(shot_w * 0.10)
    mask = Image.new("L", (shot_w, shot_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot_w - 1, shot_h - 1], radius=radius, fill=255)
    shot_resized.putalpha(mask)

    canvas = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    canvas.paste(shot_resized, (off_x, off_y), shot_resized)
    canvas.alpha_composite(frame)
    return canvas


def process(locale, key, dev_key, dev):
    raw_path = os.path.join(dev.get("raw_dir", RAW_DIR), f"{key}.png")
    if not os.path.exists(raw_path):
        return None
    raw = Image.open(raw_path)

    W, H = dev["canvas"]
    frame_path = ensure_frame(dev["frame"])
    off_x, off_y = dev["off"]
    off_w = dev["off_w"]

    device_img = compose_device(raw, frame_path, off_x, off_y, off_w)

    bg = make_gradient(W, H, BLUE, TEAL).convert("RGBA")
    draw = ImageDraw.Draw(bg)

    title, subtitle = LOCALES[locale][key]
    font_path = CJK_FONT_BOLD if locale in CJK_LOCALES else FONT_BOLD
    sub_font_path = CJK_FONT_BOLD if locale in CJK_LOCALES else FONT_SUB
    title_font = ImageFont.truetype(font_path, round(W * 0.088))
    sub_font = ImageFont.truetype(sub_font_path, round(W * 0.045))

    wrap_mode = "char" if locale in CJK_LOCALES else "word"
    top_y = round(H * 0.065)
    max_text_w = W * 0.88
    bottom_of_title = draw_centered_text(draw, W / 2, top_y, title, title_font,
                                          (255, 255, 255, 255), max_text_w, line_gap=1.05, wrap=wrap_mode)
    sub_top = bottom_of_title + round(H * 0.012)
    bottom_of_sub = draw_centered_text(draw, W / 2, sub_top, subtitle, sub_font,
                                        (255, 255, 255, 220), max_text_w, line_gap=1.1, wrap=wrap_mode)

    # Scale the composed device to fill most of the canvas width; let it
    # bleed off the bottom edge (matches the reference marketing-screenshot
    # style rather than shrinking to show the whole device).
    frame_target_w = round(W * 0.94)
    scale2 = frame_target_w / device_img.width
    frame_target_h = round(device_img.height * scale2)
    device_scaled = device_img.resize((frame_target_w, frame_target_h), Image.LANCZOS)

    device_top_y = bottom_of_sub + round(H * 0.035)
    device_left_x = round((W - frame_target_w) / 2)
    bg.alpha_composite(device_scaled, (device_left_x, device_top_y))

    out_dir = os.path.join(OUT_DIR, locale, dev_key)
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{key}.png")
    bg.convert("RGB").save(out_path, "PNG")
    return out_path


if __name__ == "__main__":
    # Usage: generate_framed_screenshots.py [locale-or-key-substring-filter]
    # e.g. "de-DE" renders only German, "01-today" renders that screenshot
    # for every locale, "de-DE:01-today" combines both filters.
    arg = sys.argv[1] if len(sys.argv) > 1 else None
    locale_filter, key_filter = (None, None)
    if arg:
        if ":" in arg:
            locale_filter, key_filter = arg.split(":", 1)
        elif arg in LOCALES:
            locale_filter = arg
        else:
            key_filter = arg

    for locale, copy in LOCALES.items():
        if locale_filter and locale != locale_filter:
            continue
        for key in copy:
            if key_filter and key_filter not in key:
                continue
            for dev_key, dev in DEVICES.items():
                out = process(locale, key, dev_key, dev)
                # None = no raw capture for this key on this device (e.g. only a
                # couple of screens were ever captured on the iPad simulator).
                print("wrote", out) if out else print(f"skip  {locale}/{dev_key}/{key} (no raw capture)")
