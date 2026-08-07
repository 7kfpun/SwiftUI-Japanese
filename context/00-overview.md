# 00 — Overview

**Japanese Daily 每日日本語** is a native SwiftUI + SwiftData iOS app that teaches
the **Minna no Nihongo** textbook vocabulary (50 lessons, 2089 entries) plus the
hiragana/katakana kana syllabaries. It replaced an older React Native app of the
same name; that RN app still exists at `~/Documents/OwnWorkspace/JapaneseBak` if
anyone ever needs to check original behavior, but nothing from it is vendored into
this repo anymore. The rebuild is feature-complete and in App Store submission.

This folder documents the app **as it exists today** — not a porting plan.

## Tab structure

`RootView` (`nihongo/RootView.swift`) is a 4-tab `TabView`:

```
TabView
├─ Today     → TodayView            (daily 7-word card browser + widget)
├─ Kana      → KanaBrowserView      → KanaQuizModeView → {Flashcards|Classic|Swipe|Listening|Write}
├─ Lessons   → LessonListView       → SelectModeView    → {Vocab List|Flashcards|Learn|Quiz|Listening}
└─ Settings  → SettingsView         (languages, premium, legal, feedback)
```

Every tab is wrapped in `RootView.banner(_:_:)`, which stacks a `BannerAd` below
the tab's content in a plain `VStack` — **not** `.safeAreaInset`. That's a
deliberate fix: screens pushed onto a `NavigationStack` (e.g. `QuizView`) don't
see an ancestor's safe-area inset, so a `.safeAreaInset`-based banner used to
render *underneath* controls like the Quiz "Next" button. The `VStack` reserves
real layout space instead.

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

- **Lessons 1–5 are free forever.** Lessons 6–50 are premium.
- **Kana (all of it — browser + every quiz mode) is always free.** There is no
  Kana gating anywhere in the code.
- On a locked lesson, the practice modes (Flashcards, Learn, Quiz, Listening)
  give a **5-card free trial** (`Gating.freeTrialCards`) before a paywall sheet
  appears. **Vocab List stays free on every lesson** — you can always read a
  locked lesson's word list, just not drill it past 5 cards without buying in.
- **Today** can only select lessons 1–5 without premium; picking a locked lesson
  from its menu opens the paywall and the view snaps back to lesson 1
  (`TodayView.clampIfLocked()`).

Purchases are **StoreKit 2**, on-device only — no server, no shared secret.
`PremiumProduct` in `Store.swift` lists a lifetime non-consumable
(`com.kfpun.nihongo.premium.lifetime`) plus a current subscription lineup
(`…premium.1m/3M/6M` — note the case-sensitive uppercase M) and a `legacy` array
of RN-era subscription IDs (`…premium.3m/6m/12m`) that are no longer sold but
are still honored so pre-existing buyers restore correctly. `Store.isPremium`
is derived from `Transaction.currentEntitlements` and drives both lesson
gating and ad visibility everywhere (`BannerAd`, `Interstitial`).

## Monetization

- **AdMob banners** (`nihongo/Ads/AdBanner.swift`) — one per tab/screen slot
  (`AdSlot`), hidden entirely for premium users. The SDK is wrapped in
  `#if canImport(GoogleMobileAds)` so the app builds and runs before the
  package is even added to the project; without it (or without
  `Secrets.plist`) DEBUG builds render a placeholder label instead of a real ad.
- **AdMob interstitial** (`nihongo/Ads/Interstitial.swift`) — shown at most once
  every 3 minutes, on leaving a Quiz/Listening screen, non-premium only.
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
`firebase.json` / `.firebaserc`) at `kf-nihongo.web.app`. `web/privacy.html`
and `web/terms.html` are **not** touched by the generator — they're the live
App Store Connect privacy/terms URLs and must be edited by hand if ever
changed. See `build-and-deploy-web` skill.

## Shipped feature state (current)

- **Kana**: segmented Basic/Voiced/Combos browser with green/red mastery tiles,
  5 quiz modes (Flashcards, Classic 4-option, Swipe 2-option Tinder-style,
  Listening, Write-with-scoring), all free.
- **Lessons**: 50 lessons in 4 groups + debounced fuzzy-ish search, 5 modes per
  lesson (Vocab List, Flashcards, Learn tile-reconstruction, Quiz, Listening).
- **Today**: daily 7-word card browser feeding a Lock-Screen/Home-Screen widget
  via an App Group.
- **Settings**: separate app-UI language vs. vocabulary-translation language
  (17 languages each), premium management, legal docs, feedback link.
- **Audio**: ~2087 pre-generated Kyoko (`say -v Kyoko`) clips bundled in the
  app, with a live `AVSpeechSynthesizer` fallback for the ~2 clip-less words
  and for bare kana tiles.
- 21 unit tests (`nihongoTests`) + UI smoke/screenshot tests (`nihongoUITests`)
  pass. Deployment target iOS 26.5; developed against the iPhone 17 Pro (iOS
  26.5) simulator.

## Where to go next

See `context/README.md` for the full file index. The short version: data model
→ `01`, Kana → `03`, Lessons → `04`, shared UI/audio → `05`, visual language →
`07`, analytics → `08`.
