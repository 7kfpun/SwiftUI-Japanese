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
LANGS = ["en", "zh", "zh-Hant", "vi", "de", "th", "my"]
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

# Kana clips: copy minna's Kyoko kana recordings → flat `kana-<romaji>.m4a`.
# The app romanizes じ/ぢ→"ji" and ず/づ→"zu", matching minna's ji.m4a / zu.m4a.
KANA_SRC = os.path.join(SRC, "audio", "kana", "kyoko")
KANA = ["a","i","u","e","o","ka","ki","ku","ke","ko","sa","shi","su","se","so",
        "ta","chi","tsu","te","to","na","ni","nu","ne","no","ha","hi","fu","he","ho",
        "ma","mi","mu","me","mo","ya","yu","yo","ra","ri","ru","re","ro","wa","wo","n",
        "ga","gi","gu","ge","go","za","ji","zu","ze","zo","da","de","do",
        "ba","bi","bu","be","bo","pa","pi","pu","pe","po",
        "kya","kyu","kyo","sha","shu","sho","cha","chu","cho","nya","nyu","nyo",
        "hya","hyu","hyo","mya","myu","myo","rya","ryu","ryo","gya","gyu","gyo",
        "ja","ju","jo","bya","byu","byo","pya","pyu","pyo"]
kana_made, kana_missing = 0, []
for romaji in KANA:
    src = os.path.join(KANA_SRC, f"{romaji}.m4a")
    if os.path.exists(src):
        shutil.copyfile(src, os.path.join(AUDIO_DST, f"kana-{romaji}.m4a"))
        kana_made += 1
    else:
        kana_missing.append(romaji)

msg = (f"MinnaData.json {os.path.getsize(dst)//1024}KB | entries={sum(len(l['entries']) for l in lessons)}"
       f" | vocab clips={audio_copied} | kana clips={kana_made}")
if kana_missing:
    msg += f" | MISSING kana ({len(kana_missing)}): {','.join(kana_missing)}"
print(msg)
