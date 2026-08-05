# Minna no Nihongo (native SwiftUI)

A native **SwiftUI + SwiftData** rebuild of the Minna no Nihongo study app
(Kana + Lessons), ported from the original React Native app. Offline, ad-free.

## Requirements

- **Xcode 26+** (iOS 26 SDK)
- **Python 3** (builds the bundled data)
- **git** with SSH access to the private **`minna`** data submodule

## Getting started

```sh
git clone <this repo> && cd nihongo
make setup          # fetches the `minna` submodule + builds bundled data
open nihongo.xcodeproj
# then Build & Run (⌘R) on an iOS 26 simulator
```

`make setup` does two things:
1. `git submodule update --init minna` — pulls the vocabulary data.
2. `python3 scripts/build-minna-data.py` — compiles it into the app's bundled
   resources.

> First run only: a fresh clone has no bundled data (`MinnaData.json` + audio) until
> you run `make setup` — they're generated from the submodule, not committed (see below).

## Data pipeline

The Japanese vocabulary + audio live in the **`minna`** git submodule (repo root),
which is the single source of truth. A build step turns it into app-bundle
resources:

```
minna/                         (submodule — source of truth)
  vocab/{1..50}.json           kanji / kana / romaji
  en|zh|zh-Hant|vi|de|th|my/   translations, keyed by romaji
  audio/kyoko/{lesson}/*.m4a   pronunciation clips
        │
        │  scripts/build-minna-data.py   (via `make data`)
        ▼
nihongo/Resources/
  MinnaData.json               one file: all lessons + 7 languages
  audio/{lesson}-{slug}.m4a    flat, uniquely-named clips
```

Why generated files instead of bundling the submodule directly: the flat,
individually-added resources are copied **incrementally** by Xcode, so rebuilds stay
fast (a whole-folder reference re-copies ~75 MB every build). Everything under
`nihongo/Resources/` (`MinnaData.json` + `audio/`) is **generated and git-ignored** —
regenerate any time with `make data`. The `minna` submodule is the single source of truth.

## Common tasks

```sh
make            # == make setup
make refresh    # pull latest `minna` and rebuild bundled data
make data       # rebuild MinnaData.json + audio from the current submodule
make clean      # remove generated resources
make help       # list targets
```

Run the tests from Xcode (⌘U) or:

```sh
xcodebuild test -scheme nihongo -only-testing:nihongoTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Settings

Two independent language pickers in the app's **Settings** tab:
- **App language** — the interface (7 languages).
- **Vocabulary language** — what Japanese words are translated into.

## Ads & analytics (optional)

AdMob banners + Firebase Analytics/Crashlytics are integrated behind
`#if canImport(...)` guards, so the app builds and runs **without** them. To turn
them on (add the Swift Packages, drop in the git-ignored real keys), see
[`config/README.md`](config/README.md). No real keys are committed — a fresh clone
uses Google test ad IDs and skips Firebase.

## Architecture / analysis

Design notes and the reverse-engineered spec of the original RN app live in
[`context/`](context/) — start with `context/README.md`.
