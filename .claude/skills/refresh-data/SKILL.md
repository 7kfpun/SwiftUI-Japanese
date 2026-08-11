---
name: refresh-data
description: Pull the latest vocab/kana/audio data from the `minna` git submodule, regenerate the bundled MinnaData.json/KanaChart.json/audio resources, and run the unit tests to confirm nothing broke. Use when the `minna` submodule has upstream changes to bring in, or after any edit to `scripts/build-minna-data.py`, or whenever bundled data (vocab, translations, kana chart, audio clips) looks stale.
when_to_use: refresh data, update minna, pull minna, regenerate MinnaData, rebuild bundled data, sync submodule, update vocab data, make data, make refresh, missing audio clip, DataTests failing, entry count changed
allowed-tools: Bash
---

# Refresh bundled data from the `minna` submodule

`minna/` (repo root) is a git submodule — the single source of truth for
vocab, translations, and the kana chart (see `context/01-data-model.md`).
Nothing reads it directly at runtime: `scripts/build-minna-data.py` compiles
it into flat, bundle-friendly files. Whenever the submodule moves, those
generated files go stale until this workflow is re-run.

## Steps

**1. Fast-forward the submodule** — fetch and merge only if it's a clean
fast-forward (never force, never rebase):

```sh
cd minna && git fetch origin && git merge --ff-only origin/main
```

If `git merge --ff-only` refuses (diverged history), stop and surface that to
the user rather than forcing anything — the submodule pin is deliberate
version control, not a moving pointer.

**2. Regenerate the bundled resources** — from the **repo root** (not from
inside `minna/`):

```sh
make data          # == python3 scripts/build-minna-data.py
```

`make data` is the name the code refers to (`DataTests.generatedDataShape`'s own
comment says "update together with `make data`"), so prefer it. There is also a
`make refresh`, which does step 1 as `git submodule update --init --remote minna`
and then `make data` — **that is not the same as step 1 above**: `--remote`
moves the pin to the upstream branch tip whatever its shape, where the `--ff-only`
merge refuses a diverged history. Use `make refresh` only when you already know
the submodule is a clean fast-forward.

This writes:

| Output | Tracked? |
|---|---|
| `nihongo/Resources/MinnaData.json` | yes — 50 lessons + 17 languages, one file |
| `nihongo/Resources/KanaChart.json` | yes — `minna/vocab/kana.json` copied verbatim |
| `nihongo/Resources/audio/vocab/*.m4a` | **no**, git-ignored — regenerated every run |
| `nihongo/Resources/audio/kana/*.m4a` | **no**, git-ignored — shared by both apps |

The second dataset has its own script, `scripts/build-jlpt-data.py` → `Apps/jlpt/Resources/`
(`JLPTData.json` + `audio/<id>.m4a`, both git-ignored). Run it after the same
`git submodule update`; it reads `minna/jlpt/` and touches nothing under `nihongo/`.

(The script's own docstring says "7 languages". It's stale — `LANGS` in the same
file lists 17. Don't propagate the 7.)

Watch the script's one summary line. It looks like

```
MinnaData.json 1618KB | entries=2089 | vocab clips=2089 | kana clips=102
```

and it grows a ` | MISSING kana (n): …` suffix when a kana romaji in
`minna/vocab/kana.json` has no `audio.kyoko` source. That is an upstream data
problem, not a re-run problem: `DataTests.everyKanaHasABundledClip` asserts a
clip for **every** cell of `seion` + `dakuon` + `youon`, so a missing one fails
the suite. Note that じ/ぢ and ず/づ share a romaji and therefore a clip (first
one wins), which is why the kana clip count is lower than the cell count.

**3. Run the unit tests.** `DataTests` and `KanaTests` exist as canaries for
exactly this script, so they are the verification step, not an afterthought:

```sh
xcodebuild test -scheme nihongo -project nihongo.xcodeproj \
  -destination "id=5250BD7F-D8E3-484D-A209-23CCD0523399" \
  -only-testing:nihongoTests/DataTests -only-testing:nihongoTests/KanaTests
```

then the whole target (`-only-testing:nihongoTests`) before you call it done —
`SearchTests`, `LearnTests`, `TrainTests`, `ChallengeTests` and `TodayTests` all
read the bundled data too.

What each canary is actually protecting, in `DataTests`:

- **`generatedDataShape`** — `allVocab().count == 2089`,
  `filter { $0.audio != nil }.count == 2089` (every word now has a clip; the two
  `～` placeholders got theirs upstream in `13675e0`. `CLAUDE.md` states clip
  coverage as a product fact, so this is copy-relevant, not just a test number),
  and `lessons().map(\.number) == Array(1...50)`.
- **`idsAreGloballyUnique`** — romaji repeat across lessons, so `Vocab.id` must
  keep its lesson prefix.
- **`everyLessonSupportsGameplay`** — every lesson needs ≥7 entries (Today picks
  7) and ≥4 distinct kana (the quiz needs 4 options). A trimmed lesson upstream
  breaks screens, not just counts.
- **`vocabClipIsNamedAndDecodes`** — the flat `<lesson>-<slug>` naming scheme
  (`1-watashi`), and that the file actually decodes as audio.
- **`translationsSwitchWithLanguage`** — every one of the 17 languages resolves a
  non-empty translation for every entry of lesson 1.

If a count assertion fails, that is usually the data genuinely having changed.
**Update the assertion deliberately and change all its readers together.** The
entry count 2089 is quoted in `CLAUDE.md`, `context/01-data-model.md`,
`context/00-overview.md` and the website's `T` dict (`scripts/build-web.py`); the
*clip* count is quoted everywhere except `build-web.py`, which only ever states
how many **words** there are. Never relax an assertion to `>=` to make a red
suite green.

## The submodule has two datasets, and clip paths use a different base

Since `5874aca` the submodule root holds `minna/` (this app's data) beside `jlpt/`
(a separate 7972-word dataset this app does not bundle). So the script reads JSON
from `SRC` = `minna/minna`, one level below the submodule root.

**But `audio.kyoko` values inside that JSON are relative to the submodule *root***
and carry their own `minna/` prefix — `minna/audio/kyoko/1/watashi.m4a`. They must
be joined onto `SUB` (the root), not `SRC`. Getting this wrong is silent: every
`os.path.exists` misses, **zero clips copy**, and the script still writes a
structurally valid `MinnaData.json` and reports success. The only visible symptom
is `vocab clips=0 | kana clips=0` in the summary line and, later, a failing
`generatedDataShape`. Read the summary line every run.

## Hard rules and flakes

Data looks right in the app or it doesn't, and it is tempting to go and look —
don't. `CLAUDE.md`'s first hard rule holds here: **tests only**, never
`xcodebuild build` and never a simulator launch. Ask the user to check in Xcode
instead.

Never commit the regenerated files either — `MinnaData.json` and `KanaChart.json`
are tracked and *will* show up in `git status` after every run, which makes
"just commit the data" a very natural mistake. Stage if asked; the user commits.

## If `xcodebuild test` flakes

See the `run-tests` skill for the Mach error -308 retry procedure — don't
reach for `simctl shutdown all` as the first move.
