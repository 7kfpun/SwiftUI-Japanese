# context/ — how this app works now

This folder documents **Japanese Daily 每日日本語** as it currently exists: a
native SwiftUI + SwiftData iOS app, feature-complete. It is **not** a rebuild
plan — the SwiftUI rebuild from the original React Native app is done. If you
need the old RN source for historical reference, it lives outside this repo at
`~/Documents/OwnWorkspace/JapaneseBak` — nothing from it is vendored here anymore.

These docs deliberately describe durable structure rather than release status,
which rots fastest. For where a build actually is, check App Store Connect.

Read this folder cold-start, in roughly this order:

| Doc | Read this for |
|---|---|
| `00-overview.md` | The big picture: tab structure, premium model, monetization, the promo website, current shipped state. Start here. |
| `01-data-model.md` | Where the vocab/kana/audio data comes from (`minna` submodule → `scripts/build-minna-data.py` → bundled JSON), the Swift types that consume it (`Vocab`, `K`, `VocabStore`), and the three-tier persistence split — every `Pref` key, and the two CloudKit-backed `@Model`s. |
| `02-challenge-ladder.md` | The app's core mechanic: rung sizing, the sliding review window, form tiering, star bands, the unlock chain, best-only persistence and the CloudKit merge resolver. |
| `03-kana.md` | The Kana tab: browser (its rotating tile-script button and the font-follows-script rule) and its 5 quiz modes — including the handwriting-scoring math behind Write. |
| `04-lessons.md` | The Lessons tab: browse/search, and the **four** untested practice modes per lesson (Vocab List/Flashcards/Train/Learn) plus where the ladder sits. Read with `02`. |
| `05-shared-and-audio.md` | Cross-cutting pieces: the `Pronouncer`/`Speech` audio seam, the shared quiz/flashcard/swipe components, `CardPager`, and the two independent language settings. |
| `06-monetization.md` | `Gating` and the free tier, the product lineup and its legacy IDs, the paywall's price maths, the rating prompt's star-row-before-Apple design, and every ad slot and throttle. |
| `07-ux-ui.md` | The visual language: color tokens (dynamic light/dark), the typography rules and their measurements, the Tinder-like swipe pattern shared across five screens, and a few non-obvious layout decisions. |
| `08-analytics.md` | The `Track` API, the full event catalog, the paywall source-attribution pattern, Firebase Performance, and the three kinds of notification. |
| `09-intro-and-survey.md` | The six-card first-launch tour and the three questions it asks; the `survey_intro` Firestore collection, its write-only security rules, and the App Check setup that guards them — the app's only server write. |

`02` and `06` were split out of `00`/`04` because both subjects were smeared
across several files and each is load-bearing enough to contradict quietly.

## What's not covered here

- **App Store operations** (metadata, screenshots, submission automation) —
  see `fastlane/README.md` and `fastlane/Fastfile`.
- **AdMob/Firebase one-time project setup** (adding SDKs, secrets files) —
  see `config/README.md`.
- **Reusable workflows** (refreshing data, running tests, deploying the web
  site) are captured as Claude Code skills under `.claude/skills/`, not here —
  check there before re-deriving a command from scratch.

## Keeping this folder honest

These docs describe source-of-truth files, not the other way around. If
something here and the actual Swift/Python source disagree, the source is
right — fix the doc. When a doc cites a specific number (test counts, entry
counts, event names), it was verified against the actual file at the time of
writing; re-verify before trusting it long after a large change.

A stale *number* is the common failure, and a stale *absence* is the dangerous
one: a persistence key that no longer exists, a mode that was merged into
another, a per-mode trial that became one whole-lesson rule. When rewriting,
read the code first and the existing doc second — a rewrite that paraphrases a
confidently wrong doc is worse than no rewrite.
