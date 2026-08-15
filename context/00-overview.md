# 00 — Overview

**Japanese Daily 每日日本語** is a native SwiftUI + SwiftData iOS app that teaches
the **Minna no Nihongo** textbook vocabulary (50 lessons, 2089 entries) plus the
hiragana/katakana kana syllabaries. It replaced an older React Native app of the
same name; that RN app still exists at `~/Documents/OwnWorkspace/JapaneseBak` if
anyone ever needs to check original behavior, but nothing from it is vendored into
this repo anymore. The SwiftUI rebuild is feature-complete.

This folder documents the app **as it exists today** — not a porting plan. It
deliberately describes durable structure rather than release status, which rots
fastest: at the time of writing `MARKETING_VERSION` is 3.0.0, which was rejected once
for a missing Terms of Use link on the paywall (since fixed — see `06-monetization.md`)
and is pending resubmission. Check App Store Connect, not this file, for where a build
actually is.

## Tab structure

`RootView` (`nihongo/RootView.swift`) is a 5-tab `TabView`:

```
TabView
├─ Today     → TodayView            (daily 7-word card browser + widget)
├─ Kana      → KanaBrowserView      → KanaQuizModeView → {Flashcards|Classic|Swipe|Listening|Write}
├─ Lessons   → LessonListView       → SelectModeView    → {Vocab List|Flashcards|Train|Learn}
│                                                       + Challenge ladder (rungs 1…N)
├─ Progress  → StatsView            (streak, days, challenges, kana) → BookmarksView
└─ Settings  → SettingsView         (languages, premium, reminders, legal, feedback)
```

Every tab is wrapped in `RootView.banner(_:_:)`, which stacks a `BannerAd` below
the tab's content in a plain `VStack` — **not** `.safeAreaInset`. That's a
deliberate fix: screens pushed onto a `NavigationStack` don't see an ancestor's
safe-area inset, so a `.safeAreaInset`-based banner used to render *underneath*
bottom-anchored controls — the "Next" button on `ChallengeView` and `KanaQuizView` is the
case that surfaced it. The `VStack` reserves real layout space instead.

The whole tab tree is `.id(appLanguage)`-keyed in `RootView`, so switching the
interface language rebuilds the entire view hierarchy instantly rather than
requiring a relaunch.

## Data model in one sentence

Everything the app displays — vocab, translations, audio clip names, the kana
chart — is compiled ahead of time by `scripts/build-minna-data.py` from the
`minna` git submodule into two bundled JSON files (`MinnaData.json`,
`KanaChart.json`) plus a flat folder of `.m4a` clips; see `01-data-model.md`.

## Premium model

Defined in `nihongo/Store/Store.swift` (`Gating` enum):

- **Lessons 1–5 are free forever** (`Gating.freeLessonLimit = 5`). Lessons 6–50
  are premium.
- **Kana (all of it — browser + every quiz mode) is always free.** There is no
  Kana gating anywhere in the code.
- **One whole-lesson rule.** A locked lesson's practice modes and challenges are
  simply locked; the row opens the paywall instead of navigating (`SelectModeView`
  is where that is enforced). The earlier 5-card-trial design is gone: a free user
  can *finish* lessons 1–5 — fill the progress bar, earn the stars — and meets the
  paywall carrying that momentum, rather than being cut off mid-practice by a card
  quota.
- **One exception, and only one: the meaning preview.** On a locked lesson, "Play
  with meanings" reads `Gating.freeMeaningPreview` (7) words and then shows the
  paywall (`Gating.wordsToRead`, `VocabListView`). Plain "Play all" is Japanese
  only and stays free on every lesson. Don't generalise this into a second gating
  concept — see `06-monetization.md` for why it earns its exception.
- **Vocab List stays free on every lesson**, so browsing and search never lock.
- **Today is never paywalled.** Its deck is derived from progress and walks all
  50 lessons whatever the subscription says — meeting the words is free, being
  *tested* on them is what premium buys. Its "Ready for Challenge N?" capsule
  stops at the Lessons list when the lesson is locked.

Purchases are **StoreKit 2**, on-device only — no server, no shared secret.
`PremiumProduct` in `Store.swift` lists a lifetime non-consumable
(`com.kfpun.nihongo.premium.lifetime`) plus a current subscription lineup
(`…premium.1m/3M/6M` — note the case-sensitive uppercase M) and a `legacy` array
of RN-era subscription IDs (`…premium.3m/6m/12m`) that are no longer sold but
are still honored so pre-existing buyers restore correctly. `Store.isPremium`
is derived from `Transaction.currentEntitlements` and drives both lesson
gating and ad visibility everywhere (`BannerAd`, `Interstitial`). So four things are
sellable — 1m, 3M, 6M and lifetime — and 12m exists only for restores. Full detail,
including the price maths and why plan names never come from App Store Connect, in
`06-monetization.md`.

## Monetization

Detailed in `06-monetization.md`; the shape of it:

- **AdMob banners** (`nihongo/Ads/AdBanner.swift`) — one per tab, five in total
  (`AdSlot.today/.progress/.kana/.lessons/.about`; the enum's other three names are
  unused leftovers), hidden entirely for premium users. Progress had shared Today's
  unit until the two were split, which blended their impressions into one report. The SDK
  is wrapped in `#if canImport(GoogleMobileAds)` so the app builds and runs before the
  package is even added to the project; without it (or without `Secrets.plist`) DEBUG
  builds render a placeholder label instead of a real ad.
- **AdMob interstitial** (`nihongo/Ads/Interstitial.swift`) — shown at most once
  every 3 minutes, non-premium only, on leaving **Train** (if anything was answered) or
  **a Challenge run** (only if it finished — never mid-run).
- **A rating ask**, offered to anyone who has just passed their 21st rung, at most
  once every two months:
  the app's own star row first, and only 4★+ hands off to Apple's review sheet.
- **Firebase Analytics + Crashlytics** — see `08-analytics.md`.
- Ships with **no App Tracking Transparency prompt**: AdMob is explicitly
  configured non-personalized (`publisherPrivacyPersonalizationState = .disabled`
  in `AppBootstrap.swift`) so there's no IDFA use and nothing to declare in App
  Privacy — a deliberate trade of ad revenue for a simpler privacy posture.

## Promo website

`web/` is a static, statically-generated marketing site (`scripts/build-web.py`,
one big Python template — never hand-edit the generated HTML). It builds
English by default; `--all` regenerates all 17 language folders. Hosted on
**Firebase Hosting** (`kf-nihongo` project, `web` as the `public` dir — see
`firebase.json` / `.firebaserc`) at `kf-nihongo.web.app`. The same `firebase.json` also
declares `firestore.rules`, so the survey ruleset (`09-intro-and-survey.md`) deploys from
this repo rather than only through the console. `web/privacy.html`
and `web/terms.html` are **not** touched by the generator — they're the live
App Store Connect privacy/terms URLs and must be edited by hand if ever
changed. See `build-and-deploy-web` skill.

## Shipped feature state (current)

- **Kana**: segmented Seion/Dakuon/Youon browser with green/red mastery tiles.
  The tile script rotates hiragana → katakana → romaji on one toolbar tap. 5 quiz
  modes (Flashcards, Classic 4-option, Swipe 2-option, Listening,
  Write-with-scoring), all free.
- **Lessons**: 50 lessons in 4 groups + debounced `contains` search. **Four**
  untested practice modes per lesson (Vocab List, Flashcards, Train, Learn
  tile-reconstruction) **plus a scored Challenge ladder** — 10 questions a rung,
  80% to pass, up to 3 stars, each rung unlocked by passing the one below. Quiz
  and Listening are no longer per-lesson modes: Listening became a question form
  inside the ladder, and the old shared model is now `TrainModel`.
- **Today**: card browser dealing the next unpassed rung's pool (its new words
  plus the review window) — derived from progress, never chosen. Feeds the
  Lock-Screen/Home-Screen widget via an App Group and the watch over
  WatchConnectivity; both rotate hourly off the wall clock
  (`TodayShared.rotationIndex`).
- **First launch**: a five-card intro tour that also asks three questions —
  see `09-intro-and-survey.md`.
- **Settings**: separate app-UI language vs. vocabulary-translation language
  (17 languages each), premium management, legal docs, feedback link. Two hidden
  developer affordances on the version footer: 7 taps toggles analytics
  exclusion, long-press replays the intro.
- **Audio**: all 2089 words have a pre-generated Kyoko (`say -v Kyoko`) clip
  bundled, with a live `AVSpeechSynthesizer` fallback for bare kana tiles and for
  any word whose clip is absent. These are TTS, **not native-speaker recordings** —
  marketing copy must not claim otherwise.
- **Sync**: kana mastery (`KanaResult`) and challenge progress (`ChallengeResult`) are
  the app's only two `@Model` types, both in one CloudKit-backed SwiftData container
  (`iCloud.com.kfpun.nihongo`), so they follow the user across devices — and neither can
  carry `@Attribute(.unique)`, which is why every reader is merge-tolerant
  (`01-data-model.md`).
- **Server**: one write, ever — the intro survey to Firestore, guarded by App Check
  (`09-intro-and-survey.md`). Purchases, progress and preferences never leave the device
  or the user's own iCloud.
- Around 78 unit tests (`nihongoTests`) + UI smoke/screenshot tests (`nihongoUITests`)
  pass — re-count before quoting the number; the `run-tests` skill's own figure is stale.
  Deployment target iOS 26.5; developed against the iPhone 17 Pro (iOS 26.5) simulator.

## Where to go next

See `context/README.md` for the full file index. The short version: data model
→ `01`, the Challenge ladder → `02`, Kana → `03`, Lessons → `04`, shared UI/audio →
`05`, monetization → `06`, visual language → `07`, analytics → `08`, first launch → `09`.
