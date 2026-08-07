#!/usr/bin/env python3
"""Compile the `minna` submodule into bundled app resources (fast incremental builds).
Source of truth = ./minna/ (git submodule). Re-run after `git submodule update`.

Outputs under nihongo/Resources/ (audio git-ignored, MinnaData.json tracked):
  - MinnaData.json               one file: 50 lessons + 7 languages; each entry's
                                 `audio` = bundled clip basename (no extension).
  - audio/<lesson>-<slug>.m4a    Kyoko clips, flat + unique so the synchronized
                                 group bundles them as individual (incrementally
                                 copied) resources without name collisions.
"""
import json, os, shutil
REPO = os.path.join(os.path.dirname(__file__), "..")
SRC  = os.path.join(REPO, "minna")
ROOT = os.path.join(REPO, "nihongo", "Resources")
AUDIO_DST = os.path.join(ROOT, "audio")
LANGS = ["en", "zh", "zh-Hant", "vi", "de", "th", "my", "es", "fr", "ru", "bn", "hi", "ta", "te", "fil", "id", "ko"]
os.makedirs(AUDIO_DST, exist_ok=True)

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
            src = os.path.join(SRC, rel)
            if os.path.exists(src):
                shutil.copyfile(src, os.path.join(AUDIO_DST, f"{name}.m4a"))
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
        src = os.path.join(SRC, rel) if rel else None
        if src and os.path.exists(src):
            shutil.copyfile(src, os.path.join(AUDIO_DST, name))
            kana_made += 1
        else:
            kana_missing.append(e["romaji"])

msg = (f"MinnaData.json {os.path.getsize(dst)//1024}KB | entries={sum(len(l['entries']) for l in lessons)}"
       f" | vocab clips={audio_copied} | kana clips={kana_made}")
if kana_missing:
    msg += f" | MISSING kana ({len(kana_missing)}): {','.join(kana_missing)}"
print(msg)
