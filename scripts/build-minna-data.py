#!/usr/bin/env python3
"""Compile the `minna` submodule into bundled app resources (fast incremental builds).
Source of truth = ./minna/ (git submodule). Re-run after `git submodule update`.

Outputs under nihongo/Resources/ (audio git-ignored, MinnaData.json tracked):
  - MinnaData.json                    one file: 50 lessons + 17 languages; each
                                      entry's `audio` = bundled clip basename.
  - audio/vocab/<lesson>-<slug>.m4a   Kyoko clips, flat + unique so the synchronized
                                      group bundles them as individual (incrementally
                                      copied) resources without name collisions.
  - audio/kana/kana-<romaji>.m4a      one clip per kana cell.

The vocab/kana split is a *target membership* boundary, not organisation. The
`nihongo` folder is listed by the jlpt target too, and 22MB of Minna vocab clips
have no business in a JLPT binary — but 2089 files can't be excluded one at a time,
so they need a folder the pbxproj can name. Kana is shared by both apps and stays
included. Subfolders inside a synchronized group flatten into the bundle root, so
`Bundle.main.url(forResource:)` is unaffected by the extra level.
"""
import json, os, shutil
REPO = os.path.join(os.path.dirname(__file__), "..")
# The submodule holds two independent datasets side by side — minna/ (this app's 50
# lessons, joined on romaji) and jlpt/ (7972 words, joined on a content-hash id and
# translated into only en + zh-Hant). Only the first is bundled.
#
# Two bases, deliberately: data files are read from SRC (one level down), but the
# `audio.kyoko` values inside them are stored relative to the submodule *root* and
# carry their own "minna/" prefix — so joining them onto SRC silently resolves to
# nothing, copies zero clips, and still writes a valid-looking MinnaData.json.
SUB  = os.path.join(REPO, "minna")
SRC  = os.path.join(SUB, "minna")
ROOT = os.path.join(REPO, "nihongo", "Resources")
VOCAB_DST = os.path.join(ROOT, "audio", "vocab")
KANA_DST  = os.path.join(ROOT, "audio", "kana")
LANGS = ["en", "zh", "zh-Hant", "vi", "de", "th", "my", "es", "fr", "ru", "bn", "hi", "ta", "te", "fil", "id", "ko"]
os.makedirs(VOCAB_DST, exist_ok=True)
os.makedirs(KANA_DST, exist_ok=True)

lessons, audio_copied = [], 0
for n in range(1, 51):
    data = json.load(open(f"{SRC}/vocab/{n}.json"))["data"]
    out = []
    for e in data:
        entry = {"kanji": e["kanji"], "kana": e["kana"], "romaji": e["romaji"]}
        if "dictionary" in e: entry["dictionary"] = e["dictionary"]
        if e.get("useKana"):  entry["useKana"] = True
        rel = (e.get("audio") or {}).get("kyoko")
        if rel:
            name = f"{n}-{os.path.splitext(os.path.basename(rel))[0]}"
            src = os.path.join(SUB, rel)
            if os.path.exists(src):
                shutil.copyfile(src, os.path.join(VOCAB_DST, f"{name}.m4a"))
                entry["audio"] = name
                audio_copied += 1
        out.append(entry)
    lessons.append({"number": n, "entries": out})

translations = {L: {str(n): json.load(open(f"{SRC}/{L}/{n}.json")) for n in range(1, 51)} for L in LANGS}
out = {"languages": LANGS, "lessons": lessons, "translations": translations}
dst = os.path.join(ROOT, "MinnaData.json")
json.dump(out, open(dst, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))

# Kana chart: vocab/kana.json is the source of truth (grid layout, per-script
# stroke counts, clip paths). Bundle it verbatim, and drive the clip copying from
# it — no hardcoded kana list in this script or in Swift.
kana = json.load(open(f"{SRC}/vocab/kana.json"))
shutil.copyfile(f"{SRC}/vocab/kana.json", os.path.join(ROOT, "KanaChart.json"))
kana_made, kana_missing, kana_seen = 0, [], set()
for group in kana["data"].values():
    for e in group:
        # じ/ぢ and ず/づ share a romaji (and a pronunciation): first clip wins,
        # so kana-ji.m4a comes from じ's ji.m4a, not ぢ's ji-di.m4a.
        name = f"kana-{e['romaji']}.m4a"
        if name in kana_seen:
            continue
        kana_seen.add(name)
        rel = (e.get("audio") or {}).get("kyoko")
        src = os.path.join(SUB, rel) if rel else None
        if src and os.path.exists(src):
            shutil.copyfile(src, os.path.join(KANA_DST, name))
            kana_made += 1
        else:
            kana_missing.append(e["romaji"])

msg = (f"MinnaData.json {os.path.getsize(dst)//1024}KB | entries={sum(len(l['entries']) for l in lessons)}"
       f" | vocab clips={audio_copied} | kana clips={kana_made}")
if kana_missing:
    msg += f" | MISSING kana ({len(kana_missing)}): {','.join(kana_missing)}"
print(msg)
