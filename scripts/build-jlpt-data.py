#!/usr/bin/env python3
"""Compile the `jlpt` half of the minna submodule into a bundled app resource.

Source of truth = ./minna/jlpt/ (git submodule). Sibling of build-minna-data.py, and
deliberately NOT a generalisation of it: the two datasets join on different keys
(`minna` on romaji, `jlpt` on a content-hash `id`), carry different fields, and the
shared part would be three lines of json.load.

Outputs under Apps/jlpt/Resources/ (both git-ignored):
  - JLPTData.json          201 lessons across N5…N1; meanings in whichever languages
                           the submodule ships (today en, zh, zh-Hant, vi — see LANGS).
  - audio/<id>.m4a         Kyoko clips, named by the entry's content-hash id — which
                           is already globally unique and already `Vocab.key`, so no
                           lesson prefix is needed the way minna's slugs need one.

No membership exception is required for any of this: `Apps/jlpt` is listed by the
jlpt target alone, unlike `nihongo`, which both apps share.

Romaji arrived in the submodule's `173909e` and audio in `47d51da`, so the dataset is
now complete in the same sense minna's is. Romaji still is not an identity: same-reading
words share a romaji and 159 lessons group them deliberately — see `key` below.
"""
import json, os, shutil

REPO = os.path.join(os.path.dirname(__file__), "..")
# Two bases, for the same reason build-minna-data.py carries two: the data files live
# one level down, but the `audio.kyoko` values inside them are relative to the
# submodule *root* and carry their own "jlpt/" prefix. Joining them onto SRC resolves
# to nothing, copies zero clips, and still writes a valid-looking JLPTData.json.
SUB  = os.path.join(REPO, "minna")
SRC  = os.path.join(SUB, "jlpt")
# Per-app, NOT nihongo/Resources: that folder is inside the `nihongo` synchronized
# group, which the Minna app also lists — anything written there would ship 1.1MB of
# another course's data, and 82MB of its audio, inside the Minna app invisibly.
ROOT = os.path.join(REPO, "Apps", "jlpt", "Resources")
DST  = os.path.join(ROOT, "JLPTData.json")
AUDIO_DST = os.path.join(ROOT, "audio")

# N5 first: the app numbers lessons 1…N in teaching order, and a beginner starts at N5.
LEVELS = ["n5", "n4", "n3", "n2", "n1"]

# Meaning languages, taken from whichever folders the submodule actually ships.
#
# Every language is authored upstream — nothing here is machine-translated, for the
# same reason the app doesn't claim "native audio": a derived gloss is a guess wearing
# the same clothes as a curated one, and one-word definitions of Japanese vocabulary
# are exactly where a converter's judgement is least trustworthy.
#
# Ordered by ORDER (minna's own picker order) rather than by directory listing, so the
# meanings picker doesn't reshuffle when a folder is added. Adding `minna/jlpt/zh/`
# upstream is all it takes for Simplified Chinese to appear here — no code change.
ORDER = ["en", "zh", "zh-Hant", "vi", "de", "th", "my", "es", "fr", "ru",
         "bn", "hi", "ta", "te", "fil", "id", "ko"]
LANGS = [lang for lang in ORDER if os.path.isdir(os.path.join(SRC, lang))]
assert "en" in LANGS, f"no en/ in {SRC} — is the submodule checked out?"


def lesson_files(level):
    """Lesson JSONs for a level, in numeric order — 2.json sorts before 10.json."""
    d = os.path.join(SRC, level)
    names = [f for f in os.listdir(d) if f.endswith(".json")]
    return [os.path.join(d, f) for f in sorted(names, key=lambda f: int(f[:-5]))]


os.makedirs(AUDIO_DST, exist_ok=True)

lessons, levels, translations = [], [], {L: {} for L in LANGS}
number, audio_copied = 0, 0

for level in LEVELS:
    first = number + 1
    for path in lesson_files(level):
        number += 1
        src = json.load(open(path))
        entries = []
        for e in src["data"]:
            entry = {
                "kanji": e["expression"],
                "kana": e["reading"],
                "romaji": e.get("romaji", ""),
                # The content hash. Carries identity because `expression` is NOT unique:
                # 125 entries are homographs, and lessons deliberately group same-reading
                # words, so `lesson/romaji` would collide where `lesson/key` does not.
                "key": e["id"],
            }
            rel = (e.get("audio") or {}).get("kyoko")
            if rel:
                clip = os.path.join(SUB, rel)
                if os.path.exists(clip):
                    name = os.path.splitext(os.path.basename(rel))[0]
                    shutil.copyfile(clip, os.path.join(AUDIO_DST, f"{name}.m4a"))
                    entry["audio"] = name
                    audio_copied += 1
            entries.append(entry)
        lessons.append({"number": number, "title": src.get("title", ""), "entries": entries})

        for lang in LANGS:
            rel = os.path.join(SRC, lang, level, os.path.basename(path))
            translations[lang][str(number)] = json.load(open(rel))

    levels.append({"level": level.upper(), "first": first, "last": number})

out = {"languages": LANGS, "lessons": lessons, "levels": levels, "translations": translations}
os.makedirs(os.path.dirname(DST), exist_ok=True)
json.dump(out, open(DST, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))

# Same discipline as build-minna-data.py: one summary line, and it names what is missing
# rather than reporting a clean run over incomplete data.
total = sum(len(l["entries"]) for l in lessons)
missing = {lang: sum(1 for l in lessons for e in l["entries"]
                     if not translations[lang][str(l["number"])].get(e["key"]))
           for lang in LANGS}
keys = [e["key"] for l in lessons for e in l["entries"]]
no_romaji = sum(1 for l in lessons for e in l["entries"] if not e["romaji"])
msg = (f"JLPTData.json {os.path.getsize(DST)//1024}KB | entries={total}"
       f" | lessons={len(lessons)} | levels={len(levels)}"
       f" | clips={audio_copied}"
       f" | duplicate keys={len(keys) - len(set(keys))}")
if no_romaji:
    msg += f" | MISSING romaji={no_romaji}"
if audio_copied < total:
    msg += f" | MISSING clips={total - audio_copied}"
for lang, n in missing.items():
    if n:
        msg += f" | MISSING {lang}={n}"
print(msg)
