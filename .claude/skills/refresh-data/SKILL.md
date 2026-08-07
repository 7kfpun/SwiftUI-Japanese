---
name: refresh-data
description: Pull the latest vocab/kana/audio data from the `minna` git submodule, regenerate the bundled MinnaData.json/KanaChart.json/audio resources, and run the unit tests to confirm nothing broke. Use when the `minna` submodule has upstream changes to bring in, or after any edit to `scripts/build-minna-data.py`, or whenever bundled data (vocab, translations, kana chart, audio clips) looks stale.
when_to_use: refresh data, update minna, pull minna, regenerate MinnaData, rebuild bundled data, sync submodule, update vocab data
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
python3 scripts/build-minna-data.py
```

This writes `nihongo/Resources/MinnaData.json`, `nihongo/Resources/KanaChart.json`,
and the flat `nihongo/Resources/audio/*.m4a` clips (git-ignored — regenerated
every run, never committed). Watch the script's own summary line for
`MISSING kana (...)` — that means a kana romaji has no bundled audio source in
`minna/vocab/kana.json` and needs attention upstream, not just a re-run.

**3. Run the unit tests** to confirm the new data still satisfies every
invariant the app assumes (entry counts, audio-clip coverage, per-language
translation completeness, etc. — see `nihongoTests/nihongoTests.swift`'s
`DataTests`/`KanaTests`):

```sh
xcodebuild test -scheme nihongo -project nihongo.xcodeproj \
  -destination "id=5250BD7F-D8E3-484D-A209-23CCD0523399" \
  -only-testing:nihongoTests
```

If a count assertion fails (e.g. `VocabStore.allVocab().count == 2089`), that's
usually the data actually having changed — update the assertion deliberately,
don't just relax it, and note in the commit/PR what changed upstream.

## Hard rule: never build or launch the full app

This project's standing rule is **tests only** — never `xcodebuild build` the
`nihongo` app target and never launch it in a simulator. The user builds and
runs the app themselves in Xcode. If you need to sanity-check something beyond
what a unit test can express, ask the user to check it in Xcode rather than
launching the app yourself.

## If `xcodebuild test` flakes

See the `run-tests` skill for the Mach error -308 retry procedure — don't
reach for `simctl shutdown all` as the first move.
