# context/ — how this app works now

This folder documents **Japanese Daily 每日日本語** as it currently exists: a
native SwiftUI + SwiftData iOS app, feature-complete, in App Store submission.
It is **not** a rebuild plan — the SwiftUI rebuild from the original React
Native app is done. If you need the old RN source for historical reference,
it lives outside this repo at `~/Documents/OwnWorkspace/JapaneseBak` — nothing
from it is vendored here anymore.

Read this folder cold-start, in roughly this order:

| Doc | Read this for |
|---|---|
| `00-overview.md` | The big picture: tab structure, premium model, monetization, the promo website, current shipped state. Start here. |
| `01-data-model.md` | Where the vocab/kana/audio data comes from (`minna` submodule → `scripts/build-minna-data.py` → bundled JSON), and the Swift types that consume it (`Vocab`, `K`, `KanaResult`, `VocabStore`). |
| `03-kana.md` | The Kana tab: browser, and its 5 quiz modes (Flashcards/Classic/Swipe/Listening/Write) — including the handwriting-scoring math behind Write. |
| `04-lessons.md` | The Lessons tab: browse/search, and its 5 per-lesson modes (Vocab List/Flashcards/Learn/Quiz/Listening) — including Learn's tile-reconstruction mechanic and the free/premium gating rules. |
| `05-shared-and-audio.md` | Cross-cutting pieces: the `Pronouncer` audio seam, shared quiz/flashcard UI components, the two independent language settings, `CardPager`/`FlashDeck`. |
| `07-ux-ui.md` | The visual language: color tokens (dynamic light/dark), typography, the Tinder-like swipe pattern shared across Flashcards/Kana-swipe/Today, and a few non-obvious layout decisions. |
| `08-analytics.md` | The `Track` API, the full event catalog, and the paywall source-attribution pattern. |
| `09-intro-and-survey.md` | The five-card first-launch tour and the three questions it asks; the `survey_intro` Firestore collection, its write-only security rules, and the App Check setup that guards them — the app's only server write. |

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
