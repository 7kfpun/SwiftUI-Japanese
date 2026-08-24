#!/usr/bin/env python3
"""Compile the `minna` submodule into bundled app resources (fast incremental builds).
Source of truth = ./minna/ (git submodule). Re-run after `git submodule update`.

Outputs under nihongo/Resources/ (all git-ignored — regenerated, never committed):
  - MinnaData.json                    one file: 50 lessons + 18 languages; each
                                      entry's `audio` = bundled clip basename.
  - audio/vocab/<lesson>-<slug>.m4a   Kyoko clips, flat + unique so the synchronized
                                      group bundles them as individual (incrementally
                                      copied) resources without name collisions.
  - audio/examples/ex-<lesson>-<slug>.m4a  the word's example sentence, PRIMARY voice
                                      only. `ex-` prefixed because the bundle is flat —
                                      see the copy below.
  - audio/kana/kana-<romaji>.m4a      one clip per kana cell.
  - audio/cheer/cheer-<key>.m4a       the Challenge result screen's spoken reactions,
                                      one per phrase in `Cheer` (Pronouncer.swift),
                                      in both voices like vocab.

The vocab/kana split is a *target membership* boundary, not organisation. The
`nihongo` folder is listed by the jlpt target too, and 22MB of Minna vocab clips
have no business in a JLPT binary — but 2089 files can't be excluded one at a time,
so they need a folder the pbxproj can name. Kana is shared by both apps and stays
included. Subfolders inside a synchronized group flatten into the bundle root, so
`Bundle.main.url(forResource:)` is unaffected by the extra level.
"""
import glob, json, os, shutil
REPO = os.path.join(os.path.dirname(__file__), "..")
# The submodule holds two independent datasets side by side — minna/ (this app's 50
# lessons, joined on romaji) and jlpt/ (7972 words, joined on a content-hash id and
# translated into only en, zh, zh-Hant and vi). Only the first is bundled.
#
# Two bases, deliberately: data files are read from SRC (one level down), but the
# `audio.<voice>` values inside them are stored relative to the submodule *root* and
# carry their own "minna/" prefix — so joining them onto SRC silently resolves to
# nothing, copies zero clips, and still writes a valid-looking MinnaData.json.
SUB  = os.path.join(REPO, "minna")
SRC  = os.path.join(SUB, "minna")
ROOT = os.path.join(REPO, "nihongo", "Resources")
VOCAB_DST = os.path.join(ROOT, "audio", "vocab")
KANA_DST  = os.path.join(ROOT, "audio", "kana")
# Example-sentence clips, `PRIMARY` voice only. The alternate exists upstream but is
# not copied: it is there so the Challenge ladder can alternate voices on a *listening*
# rung, and no rung asks a sentence — a second copy would be 47MB for nothing.
EXAMPLE_DST = os.path.join(ROOT, "audio", "examples")
LANGS = ["en", "zh", "zh-Hant", "vi", "de", "th", "my", "es", "fr", "ru", "bn", "hi", "ta", "te", "ne", "it", "fil", "id", "ko"]

# Voices. The submodule ships three for minna: `kyoko` (macOS `say`, concatenative) and
# two VOICEVOX neural voices. VOICEVOX is a generation ahead on naturalness and pitch
# accent, which is what a vocabulary app is actually teaching, so it is now the default.
#
# ALT exists for one reason: the Challenge ladder's listening rungs. With a single voice
# a learner can pass by recognising the waveform rather than the word — the clip becomes
# the answer key. Alternating two voices makes the rung test comprehension again.
#
# PRIMARY clips keep the bare `<lesson>-<slug>` name, so `Vocab.audio` and every call
# site are unchanged; ALT clips take a suffix that `Speech.Voice` mirrors exactly.
# Kana gets PRIMARY only — the ladder is vocabulary, and a second kana set would be
# ~800KB for nothing.
PRIMARY = "whitecul"
ALT = "kenzaki"
ALT_SUFFIX = f"-{ALT}"
os.makedirs(VOCAB_DST, exist_ok=True)
os.makedirs(KANA_DST, exist_ok=True)
os.makedirs(EXAMPLE_DST, exist_ok=True)

lessons, audio_copied, alt_copied, example_copied = [], 0, 0, 0
for n in range(1, 51):
    data = json.load(open(f"{SRC}/vocab/{n}.json"))["data"]
    out = []
    for e in data:
        entry = {"kanji": e["kanji"], "kana": e["kana"], "romaji": e["romaji"]}
        if "dictionary" in e: entry["dictionary"] = e["dictionary"]
        if e.get("useKana"):  entry["useKana"] = True
        # The example sentence: three index-aligned phrase arrays (one element per
        # bunsetsu — kanji over kana over romaji, zipped into columns by the UI).
        # Grammar-ceilinged upstream (a lesson-N sentence uses only lessons 1..N).
        #
        # The upstream `example.audio` paths are dropped and the clip is addressed by
        # the *word's* own name instead — one clip per entry, same lesson and slug as
        # its vocab clip, so `Vocab.audio` locates both and the JSON carries no second
        # path. Nothing to keep in sync when a slug changes.
        if e.get("example"):
            ex = e["example"]
            entry["example"] = {"kanji": ex["kanji"], "kana": ex["kana"],
                                "romaji": ex["romaji"]}
        clips = e.get("audio") or {}
        rel = clips.get(PRIMARY)
        if rel:
            name = f"{n}-{os.path.splitext(os.path.basename(rel))[0]}"
            src = os.path.join(SUB, rel)
            if os.path.exists(src):
                shutil.copyfile(src, os.path.join(VOCAB_DST, f"{name}.m4a"))
                entry["audio"] = name
                audio_copied += 1
                # The alternate is addressed by suffix rather than recorded in the JSON:
                # one name in the data, and `Speech.Voice` derives the rest. A voice
                # missing upstream then falls back to PRIMARY at playback instead of
                # needing a per-entry flag nothing else would read.
                alt_rel = clips.get(ALT)
                if alt_rel and os.path.exists(os.path.join(SUB, alt_rel)):
                    shutil.copyfile(os.path.join(SUB, alt_rel),
                                    os.path.join(VOCAB_DST, f"{name}{ALT_SUFFIX}.m4a"))
                    alt_copied += 1
                # The sentence clip, under the same name in its own folder — so a word
                # with a clip but no sentence recording simply has no file, and playback
                # falls back to the synthesiser without needing a flag in the data.
                #
                # **`ex-` prefixed**, and that prefix is load-bearing. Xcode's
                # synchronized folders add every resource individually and the bundle is
                # therefore *flat*: `audio/vocab/1-watashi.m4a` and
                # `audio/examples/1-watashi.m4a` would both want to be `1-watashi.m4a`
                # at the root, and one would silently win — words playing sentences, or
                # the reverse, with nothing in the data to show why. It is the same
                # reason the kana and cheer clips carry `kana-` and `cheer-`.
                ex_src = os.path.join(SUB, "minna", "audio", "examples", PRIMARY,
                                      str(n), os.path.basename(rel))
                if entry.get("example") and os.path.exists(ex_src):
                    shutil.copyfile(ex_src, os.path.join(EXAMPLE_DST, f"ex-{name}.m4a"))
                    example_copied += 1
        out.append(entry)
    lessons.append({"number": n, "entries": out})

translations = {L: {str(n): json.load(open(f"{SRC}/{L}/{n}.json")) for n in range(1, 51)} for L in LANGS}

# Example-sentence translations exist for a subset of languages (en, zh, zh-Hant so
# far). Derived from the folders actually present, not a list here — a new language
# upstream should appear by regenerating, not by editing this script.
EX_SRC = os.path.join(SRC, "examples")
example_langs = sorted(d for d in os.listdir(EX_SRC)
                       if os.path.isdir(os.path.join(EX_SRC, d))) if os.path.isdir(EX_SRC) else []
examples = {L: {str(n): json.load(open(f"{EX_SRC}/{L}/{n}.json")) for n in range(1, 51)}
            for L in example_langs}
out = {"languages": LANGS, "lessons": lessons, "translations": translations,
       "examples": examples}
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
        rel = (e.get("audio") or {}).get(PRIMARY)
        src = os.path.join(SUB, rel) if rel else None
        if src and os.path.exists(src):
            shutil.copyfile(src, os.path.join(KANA_DST, name))
            kana_made += 1
        else:
            kana_missing.append(e["romaji"])

# Cheer clips: the Challenge result screen's spoken reactions. Flat in `voices/` rather
# than per-lesson, because they belong to no lesson — the keys are `Cheer.key` in
# nihongo/Pronouncer.swift. Derived by globbing rather than from a list kept here: a
# second copy of the phrase list is a copy that drifts, and the Swift side already owns
# it. Same naming rule as vocab, so `Speech.Voice.suffix` addresses the alternate and
# nothing outside that type has to know two voices exist.
CHEER_DST = os.path.join(ROOT, "audio", "cheer")
os.makedirs(CHEER_DST, exist_ok=True)
cheer_made, cheer_alt = 0, 0
for src in sorted(glob.glob(os.path.join(SUB, "voices", f"cheer-{PRIMARY}-*.m4a"))):
    key = os.path.basename(src)[len(f"cheer-{PRIMARY}-"):-len(".m4a")]
    shutil.copyfile(src, os.path.join(CHEER_DST, f"cheer-{key}.m4a"))
    cheer_made += 1
    alt = os.path.join(SUB, "voices", f"cheer-{ALT}-{key}.m4a")
    if os.path.exists(alt):
        shutil.copyfile(alt, os.path.join(CHEER_DST, f"cheer-{key}{ALT_SUFFIX}.m4a"))
        cheer_alt += 1

msg = (f"MinnaData.json {os.path.getsize(dst)//1024}KB | entries={sum(len(l['entries']) for l in lessons)}"
       f" | example langs={len(example_langs)}"
       f" | {PRIMARY} clips={audio_copied} | {ALT} clips={alt_copied}"
       f" | example clips={example_copied} | kana clips={kana_made}"
       f" | cheer clips={cheer_made}+{cheer_alt}")
if kana_missing:
    msg += f" | MISSING kana ({len(kana_missing)}): {','.join(kana_missing)}"
print(msg)
