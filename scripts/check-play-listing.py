#!/usr/bin/env python3
"""Check the Google Play store listing text (fastlane `supply` layout) against the product rules.

    python3 scripts/check-play-listing.py

Reads fastlane/minna-android/metadata/android/<play-locale>/{title,short_description,full_description}.txt
and fails (exit 1) on any of:

* a locale folder Google Play cannot take, a missing UI language, or a missing/extra file;
* title over 30 characters, short description over 80, full description over 4000 (Play counts characters);
* a textbook trademark (Minna / みんなの) in any field (CLAUDE.md, Guideline 5.2);
* "native audio"-style claims (all the audio is synthesised), "Train" as a mode name, or Apple-only
  wording (iCloud, Apple Watch, Lock Screen, App Store) that is wrong on Android;
* a free-lesson count or a hardcoded lesson count: the only numbers a full description may carry are
  the language count (which must equal the UIStrings.json language count), the JLPT levels, "over 2,000
  words", the 1/3/6/12 month plans, the 80% pass mark and "50/50";
* a full description that omits the five mode names (taken from UIStrings.json for that language) or
  does not say a paid unlock exists.

The "native" check is a word list, not a translator: it covers the languages whose word we know.
"""

import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LISTING = ROOT / "fastlane" / "minna-android" / "metadata" / "android"
UI_STRINGS = ROOT / "nihongo" / "UIStrings.json"

TITLE_MAX, SHORT_MAX, FULL_MAX = 30, 80, 4000
FILES = ("title.txt", "short_description.txt", "full_description.txt")

# UIStrings language -> Play Console locale. Every one of these is a Play store language
# (https://support.google.com/googleplay/android-developer/answer/9844778): Play, unlike the App Store,
# takes Bangla, Burmese, Nepali, Tamil, Telugu and Filipino. Spanish and French exist only as regional
# variants. Japanese is not a UI language, so there is no ja-JP folder.
PLAY_LOCALE = {
    "en": "en-US",
    "zh": "zh-CN",
    "zh-Hant": "zh-TW",
    "vi": "vi",
    "de": "de-DE",
    "th": "th",
    "my": "my-MM",
    "es": "es-ES",
    "fr": "fr-FR",
    "it": "it-IT",
    "ru": "ru-RU",
    "bn": "bn-BD",
    "hi": "hi-IN",
    "ta": "ta-IN",
    "te": "te-IN",
    "ne": "ne-NP",
    "fil": "fil",
    "id": "id",
    "ko": "ko-KR",
}

MODE_KEYS = ("Practice", "Vocab List", "Flashcards", "Match", "Learn")

TRADEMARK = re.compile(r"minna|みんなの|大家的日语|大家的日語|민나", re.IGNORECASE)
NATIVE = re.compile(
    r"native|nativ[eo]s?\b|natif|母语|母語|母国語|ネイティブ|네이티브|носител|เจ้าของภาษา|देशी वक्ता|মাতৃভাষী",
    re.IGNORECASE,
)
APPLE_ONLY = re.compile(r"iCloud|Apple Watch|Apple ID|Lock Screen|App Store|TestFlight|\bTrain(ing)?\b")
PREMIUM = re.compile(r"Premium|プレミアム|พรีเมียม|प्रीमियम|প্রিমিয়াম|ప్రీమియం|பிரீமியம்|프리미엄|ပရီမီယံ|प्रिमियम")

ALLOWED_NUMBERS = {1, 3, 6, 12, 19, 80, 2000, 4, 5}


def ascii_digits(text):
    return "".join(str(unicodedata.decimal(c)) if c.isdigit() and unicodedata.decimal(c, None) is not None else c for c in text)


def numbers_in(text):
    text = ascii_digits(text)
    text = re.sub(r"https?://\S+", " ", text)  # the privacy URL
    text = text.replace("50/50", " ")
    text = re.sub(r"(?<=\d)[,.  ](?=\d{3}(?!\d))", "", text)  # 2,000 / 2.000 / 2 000
    return [int(n) for n in re.findall(r"\d+", text)]


def main():
    errors = []

    def fail(where, message):
        errors.append(f"{where}: {message}")

    ui = json.loads(UI_STRINGS.read_text(encoding="utf-8"))
    languages = list(ui)
    if set(languages) != set(PLAY_LOCALE):
        fail("UIStrings.json", f"languages {sorted(set(languages) ^ set(PLAY_LOCALE))} are not mapped to a Play locale in this script")
    count = len(languages)

    present = {p.name for p in LISTING.iterdir() if p.is_dir()} if LISTING.is_dir() else set()
    wanted = set(PLAY_LOCALE.values())
    for extra in sorted(present - wanted):
        fail(extra, "not a Play store locale we ship (folder must not exist)")
    for missing in sorted(wanted - present):
        fail(missing, "missing locale folder")

    for lang, locale in PLAY_LOCALE.items():
        folder = LISTING / locale
        if not folder.is_dir():
            continue
        names = {p.name for p in folder.iterdir()}
        for extra in sorted(names - set(FILES)):
            fail(f"{locale}/{extra}", "unexpected file")
        texts = {}
        for name in FILES:
            path = folder / name
            if not path.is_file():
                fail(f"{locale}/{name}", "missing")
                continue
            raw = path.read_text(encoding="utf-8")
            if raw != raw.strip() + "\n":
                fail(f"{locale}/{name}", "must be trimmed text with exactly one trailing newline")
            if re.search(r"[ \t]+$", raw, re.MULTILINE):
                fail(f"{locale}/{name}", "trailing whitespace")
            texts[name] = raw.strip()

        limits = {"title.txt": TITLE_MAX, "short_description.txt": SHORT_MAX, "full_description.txt": FULL_MAX}
        for name, text in texts.items():
            where = f"{locale}/{name}"
            if len(text) > limits[name]:
                fail(where, f"{len(text)} characters, limit {limits[name]}")
            if not text:
                fail(where, "empty")
            if TRADEMARK.search(text):
                fail(where, "textbook trademark")
            if NATIVE.search(text):
                fail(where, "claims native-speaker audio (all audio is synthesised)")
            if APPLE_ONLY.search(text):
                fail(where, f"Apple-only or retired wording: {APPLE_ONLY.search(text).group(0)!r}")

        title, short = texts.get("title.txt", ""), texts.get("short_description.txt", "")
        if "\n" in title or "\n" in short:
            fail(locale, "title and short description are one line")
        if numbers_in(title + " " + short) and not set(numbers_in(title + " " + short)) <= {4, 5}:
            fail(locale, "title/short description carry a number other than a JLPT level")

        full = texts.get("full_description.txt")
        if not full:
            continue
        where = f"{locale}/full_description.txt"
        numbers = numbers_in(full)
        for n in sorted(set(numbers) - ALLOWED_NUMBERS):
            fail(where, f"unexpected number {n} (no lesson or free-lesson counts in store copy)")
        if count not in numbers:
            fail(where, f"does not state the interface language count ({count})")
        for wrong in sorted(n for n in set(numbers) if n >= 20 and n not in ALLOWED_NUMBERS):
            fail(where, f"number {wrong} could be a hardcoded lesson count")
        for key in MODE_KEYS:
            if f"• {ui[lang][key]}" not in full:
                fail(where, f"mode bullet for {key!r} ({ui[lang][key]!r}) missing")
        if len(re.findall(r"^• ", full, re.MULTILINE)) != len(MODE_KEYS):
            fail(where, f"expected exactly {len(MODE_KEYS)} mode bullets")
        if not PREMIUM.search(full):
            fail(where, "does not mention the paid unlock (Premium)")
        if "Google Play" not in full:
            fail(where, "does not say billing is through Google Play")

    if errors:
        print("Play listing check FAILED:")
        for line in errors:
            print(f"  {line}")
        return 1
    print(f"Play listing OK: {len(PLAY_LOCALE)} locales, {count} interface languages.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
