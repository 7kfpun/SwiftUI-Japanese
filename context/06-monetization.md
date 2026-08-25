# 06 — Monetization: store, paywall, rating, ads

Two revenue paths, one entitlement flag. `Store.isPremium` unlocks lessons 6–50 *and*
removes every ad, so there is exactly one thing to buy and one boolean to check.

| File | Owns |
|---|---|
| `nihongo/Store/Store.swift` | Product IDs, `Gating`, StoreKit 2 entitlement + purchase |
| `nihongo/Store/PaywallView.swift` | The offer: plan rows, price maths, legal links |
| `nihongo/Store/RatingPrompt.swift` | The star row, its threshold, the feedback fork |
| `nihongo/Ads/` | `AdConfig` unit IDs, `BannerAd`, `Interstitial`, `AppBootstrap` |

## The product lineup

`PremiumProduct` (`Store.swift:7`):

| Group | IDs | Status |
|---|---|---|
| Lifetime | `com.kfpun.nihongo.premium.lifetime` | non-consumable, sold |
| Subscriptions | `…premium.1m`, `…premium.3M`, `…premium.6M`, `…premium.12M` | sold |
| Legacy | `…premium.3m`, `…premium.6m`, `…premium.12m` | **restore only, never sold** |

`purchasable = subscriptions + [lifetime]` is what the paywall fetches;
`all = purchasable + legacy` is what the entitlement scan accepts. So five things are
sellable — **1, 3, 6 and 12 months, plus lifetime**. The 12-month plan returned as
uppercase `12M` in 2026-08; the lowercase `12m` remains history only — an RN-era
subscriber who restores keeps working, but nothing can sell one.
`PremiumTests.lineupInvariants` pins both directions (purchasable is disjoint from
legacy; `all` is a superset of each).

**The uppercase M is not a typo and cannot be fixed.** App Store Connect product IDs
are case-sensitive *and* immutable, and the lowercase 2019 IDs stay reserved forever —
so the replacement products had to differ from `3m`/`6m` by something, and case was it.
Renaming either side breaks restores for one cohort or sales for the other.
`Store.tierLabel` lowercases the last ID component, so `…premium.3M` reports as tier
`"3m"` in analytics and `…premium.lifetime` as `"lifetime"` — the analytics tier and the
product ID are deliberately *not* the same string.

## Gating: one rule, two documented ways past it

```swift
enum Gating {
    static var freeLessonLimit: Int { Course.current.freeLessonLimit }   // 5, both courses

    static func isLocked(lesson number: Int, isPremium: Bool,
                         earnedFirstGroup: Bool = false) -> Bool {
        !isPremium && number > freeThrough(earnedFirstGroup: earnedFirstGroup)
    }
}
```

`earnedFirstGroup` defaults to `false` so a caller that hasn't looked it up fails
**closed** — a lock a tap can clear, never a lesson handed out unearned.

**Lessons 1–5 are free in full** — every practice mode, every rung of the ladder — and
6–50 need premium. There is no card quota and no per-mode allowance: a free user can
*finish* the early lessons, fill the progress bar, earn the stars, and meets the paywall
carrying that momentum instead of being cut off mid-practice.

Five exemptions, all deliberate:

- **Vocab List is free on every lesson** (`SelectModeView.swift:33` navigates it
  unconditionally), so browsing and search never lock.
- **The whole Kana tab is free.** There is no `Gating` call anywhere under `nihongo/Kana`.
- **Today is never paywalled.** Its deck is derived from progress and walks all 50
  lessons whatever the subscription says — meeting the words is free, being *tested* on
  them is what premium buys. Both entry points that could dead-end a free user (the
  Today capsule, the widget's "Ready for Challenge N?" link) stop at the Lessons list
  when the lesson is locked, rather than one screen deeper on a paywall.
- **The first band can be earned rather than bought** — three stars on every challenge
  of lessons 1…`freeLessonLimit` opens Minna's "Beginning 1" (13 lessons) or JLPT's "N5"
  (19), free. Three stars is a clean 100%, so it is a real bar; a pass would be none,
  because the ladder already requires one to advance. Decided by
  `Gating.hasEarnedFirstGroup`, carried by the `Unlock` observable beside `Store`, and
  surfaced in three places so it isn't a secret: the Challenge section footer on a free
  lesson (with a progress bar), a line on the paywall itself, and a one-time celebration
  that suppresses the rating and share prompts for that run.
- **Endless playback is premium.** `Gating.loopsForever` is now simply `isPremium`: a
  free listener hears the lesson through once, in any mode, and the player stops. The
  loop is what the feature is really for — a lesson running while someone washes up —
  and it costs nothing to give and everything to give away. The whole lesson still
  plays: what is withheld is the repeat.
- **Read along's speed dial is premium; the feature is not.** Free listeners hear the
  whole lesson at `Gating.normalRate` (1.0×) and see the dial with a lock on it; 0.8×
  (shadowing) and 1.2×/1.5× (review laps) are the paid part. Gated through
  `Gating.rate(_:isPremium:)` rather than a bare `isPremium` check, because the honest
  failure is the *lapsed* subscriber: 1.2× stays in `Pref.playbackRate` after a
  subscription ends, and reading it straight back would keep granting a paid benefit.
  The preference is remembered, not honoured, so resubscribing restores it exactly
  (`PremiumTests.playbackSpeedIsPremiumButNormalSpeedIsNot`). Tapping it logs
  `locked_speed` and opens the paywall with source `playback_speed` — Read along now has
  two gates behind one sheet, and they report separately or the funnel says nothing.
- **Read along's "Japanese + meaning" is premium on every lesson**, and previews rather
  than refuses — the one partial trial in the
  app. On a locked lesson it reads `Gating.freeMeaningPreview` (7) words in full and
  *then* shows the paywall — for anyone without a subscription, on a free lesson as much
  as a locked one. It keyed off `isLocked` until 2026-08, which meant the same paid
  feature played in full on lessons 1–5 and previewed after them; a learner who never
  left the free lessons never met the gate at all. "Japanese only" is free on every lesson and
  is never truncated.

`SelectModeView` enforces gating for the practice modes and the ladder (`:17`, `:88`,
`:115`): a locked row opens the paywall instead of navigating, so no practice screen has
to police access itself. `VocabListView` is the **only** other enforcement point, and it
is the exception above, not a second rule — the Vocab List itself stays free and only the
one playback mode is gated (`Gating.wordsToRead`).

`PremiumTests` pins all of it: `gatingRules` walks all 50 lessons and the 5/6 boundary,
`plainReadAllIsFreeEvenOnALockedLesson` pins that the Japanese-only mode is never cut
short, and `previewStopsShortOfEveryLesson` pins that the preview is smaller than the
smallest lesson in the course — otherwise a "preview" would play the whole lesson and
then ask for money for what had already been heard.

### Why this one gets an exception

Every other paid mode can be understood from its name and row subtitle. This one can't:
"reads the meaning aloud after each word" describes a *rhythm* — word, pause, meaning,
pause — that means nothing described and everything heard. The lesson's Vocab List is
already free and already on screen, so the preview withholds nothing the user couldn't
read; only the voice is new. That is what makes it safe to give away seven words of.

Do not generalise it. A partial trial on Practice or the ladder cuts someone off
mid-practice, which is exactly what the whole-lesson rule exists to prevent.

## `Store` — StoreKit 2, on device, no server

`@Observable @MainActor final class Store`. No receipt server, no shared secret:
transactions are verified on-device and restore is `AppStore.sync()`.

- A `Transaction.updates` listener runs for the app's lifetime, so renewals,
  revocations, Ask-to-Buy approvals and restores made on another device all land without
  the user reopening the paywall.
- `refreshEntitlement()` scans `Transaction.currentEntitlements`, skipping anything with
  a `revocationDate`, and calls `Track.setPremium` — which is what keeps the
  `user_type`/`premium_tier` user properties and the per-event `is_premium` param honest
  (`08-analytics.md`).
- **`isLoadingProducts` and `didAttemptLoad` exist because `products.isEmpty` can't tell
  "still loading" from "loaded nothing".** Without the distinction a failed fetch renders
  as an eternal spinner; with it, `productsUnavailable` drives a named error state and a
  Try again button. `PaywallView` also re-fetches in `.task` if products are empty,
  because products load once at launch and a user who started offline would otherwise
  face an empty paywall for the entire session.
- `subscriptions` / `lifetime` split the fetched products by whether
  `product.subscription` is nil, which is how the paywall can lay them out differently
  without hardcoding IDs in the view.

## The paywall

`PaywallView` takes a `source: String` it uses for nothing except tagging its own two
events — see the attribution pattern in `08-analytics.md`.

**Plan names are built from `subscriptionPeriod`, never from App Store Connect's
`displayName`** (`PaywallView.swift:212-227` explains it at length). ASC localizations
resolve by App Store *storefront* — the Apple ID's region — while this app has its own
in-app language picker, so ASC text cannot follow it. Reading it produced an English
"6 Months / Premium, billed every 6 months." sitting beside a Chinese "最超值" on the
same row, and StoreKit hands back one localization rather than all of them, so there is
no hybrid that works. Anything that must match the in-app language comes from
`UIStrings.json`.

**Prices are the exception and stay with StoreKit.** `displayPrice` and
`priceFormatStyle` render ¥/€/₩ correctly per storefront, which is right: currency
follows where you *pay*, not what language you read.

Layout decisions worth keeping:

- Rows arrive cheapest-first (`Store.load` sorts by price ascending), each showing the
  term, the total, and — the point of the row — the **monthly equivalent plus what it
  saves**. Four bare totals made the reader do the arithmetic to find the cheaper deal,
  which mostly means they didn't.
- `bestValue` is computed as the lowest per-month cost among multi-month plans, so the
  badge stays honest if the lineup or prices change. `savingsPercent` suppresses anything
  under 5% — no advertising a rounding error.
- **Lifetime sits below a divider, not as a fourth row.** It's a different kind of
  commitment; mixed in among the subscriptions it read as "the expensive one" rather
  than "the other option".
- The free-lesson line is interpolated from `Gating.freeLessonLimit`, so the offer on
  screen can't drift from the rule the app enforces.
- The auto-renewal disclosure plus **Terms of Use and Privacy Policy links are required
  by App Review** and open the same bundled `LegalView` sheets Settings uses. (Version
  3.0.0 was rejected for a missing Terms of Use link; that is what this block is.)
- The sheet dismisses itself on `store.isPremium` becoming true, from wherever the
  entitlement arrived.

## The rating prompt

`RatingPrompt` + `RatingSheet`, called from `ChallengeView.askForRatingIfEarned`.

```swift
static let challengesRequired = 15
static func shouldAsk(isPremium: Bool, passed: Bool, passedCount: Int) -> Bool {
    isPremium && passed && passedCount >= challengesRequired && !hasAsked
}
```

Two conditions, each ruling out a different bad moment:

- **A rung they just passed**, not one they failed — asking after a failure asks how they
  feel about failing.
- **21 rungs cleared** (`ChallengeResult.totalPassed`, deduped by id so a sync merge
  can't fire it early), i.e. several lessons of real use — high enough that the ask lands
  on people who stayed rather than people who looked.
- **Not again for 60 days** (`Pref.ratingAskedAt`), which still sits inside Apple's own
  cap of about three review impressions a year rather than fighting it.

It used to be **subscribers only**, on the reasoning that a free user's most likely
rating is about the paywall. That was dropped: it silenced the ask for the large
majority of users, so almost nobody was ever asked, and the rungs-cleared bar already
selects for people who have used the app rather than bounced off it. `shouldAsk` still
*takes* `isPremium` and ignores it — the free-versus-paid split is worth reading on the
feedback sheet's `Survey.Context`, which is where a low star pick lands.

**The design point: the app's own star row runs *before* Apple's review sheet.**
`AppStore.requestReview` gives no signal about what was submitted and is rate-limited to
a handful of impressions a year, so spending one on someone about to leave two stars
wastes the only asks the app gets. So:

| Star row result | Destination |
|---|---|
| 4–5★ | `AppStore.requestReview` — Apple's real sheet |
| 1–3★ | The Airtable feedback form, `Feedback.url(source: "rating")` |
| "Not now" / dismissed | nowhere — `onRate` is simply never called |

This is **not a rating gate**: the App Store prohibits making a review path conditional
on sentiment, and nothing here blocks anyone — the star row is the app's own question,
every answer leads somewhere, and the App Store page stays reachable from Settings.

Two mechanics that look incidental and aren't:

- **Routing happens in the sheet's `onDismiss`, not in the star tap**
  (`ChallengeView.swift:105`). Both destinations replace the star row and asking to
  present either while it's still animating away is silently dropped.
- **A "no answer" and a low score are different populations.** Leaving `onRate` uncalled
  is how the caller tells them apart, and only one of them wants a follow-up. The
  feedback URL carries `prefill_Source` for the same reason: Settings is someone
  choosing to write in, a low star is someone we sent.

## Ads

Everything AdMob is behind `#if canImport(GoogleMobileAds)`, so the app builds and runs
before the package is added, and every call site gates on `!store.isPremium`.

**Banners.** `AdSlot` (`AdConfig.swift:5`) declares eight slot names, but only five are
wired — `RootView.banner(_:_:)` attaches one per tab: `.today`, `.progress`, `.kana`,
`.lessons`, `.about`. `selectMode`, `vocabList` and `search` are unused names inherited
from the RN config.

**A new slot needs a key in *both* apps' `Secrets.plist`.** `AdSlot` and `RootView` are
shared, so adding a case creates the slot in Minna and JLPT at once, and
`AdConfig.banner(_:)` falls back to Google's public **test** unit for any slot with no
key. That fallback is deliberate — a missing key should fail visibly — but visible still
means shipped, so create the AdMob units as part of building the screen.

- **The banner lives in a plain `VStack`, not `.safeAreaInset`** (`RootView.swift:61`).
  A screen pushed onto a `NavigationStack` doesn't see an ancestor's safe-area inset, so
  an inset-based banner rendered *underneath* bottom-anchored controls like a quiz's Next
  button. The `VStack` reserves real layout space.
- Height is dynamic: the `BannerView` keeps its full ad size internally (the SDK refuses
  to load into a zero-sized view) while the outer frame shows 0pt until an ad actually
  arrives, so there's no blank gap and no overlap.
- A no-fill collapses to 0pt but logs `ad_failed` — silent no-fill on a fresh unit looks
  identical to "ads are broken".
- UI-test runs launched with `-SCREENSHOTS` hide banners entirely, so marketing shots
  stay clean.

**Interstitial.** `Ads.preloadInterstitial()` / `showInterstitialIfReady()` wrap a
throttled singleton (`Interstitial.swift`): `minInterval = 180`, i.e. **at most once
every 3 minutes**, reloading itself after each presentation. Exactly two screens use it,
both preloading on `onAppear` and showing on `onDisappear`:

| Screen | Shown when |
|---|---|
| `PracticeView` | leaving, if anything was graded or answered |
| `ChallengeView` | leaving, only if the run actually finished — **never mid-run** |

**Unit IDs.** `AdConfig` splits prod/test so the repo can stay open-source. A fresh
clone has no `Secrets.plist` and falls back to Google's public test units; DEBUG *always*
uses test units, because dev clicks on real ads violate AdMob policy and brand-new real
units can no-fill for days (`AdConfigTests.debugBuildsUseTestUnitsOnly`). `.today` used
to alias the vocab-list unit because `Secrets.plist` predated the Today tab — that alias
is gone, so a missing key now fails visibly (test ads) instead of silently serving the
wrong unit on the landing tab.

**No App Tracking Transparency prompt.** `AppBootstrap` sets
`publisherPrivacyPersonalizationState = .disabled`, so ads are non-personalized, there's
no IDFA use, nothing to declare in App Privacy and no ATT dialog — a deliberate trade of
eCPM for a simpler privacy posture that the survey path also depends on
(`09-intro-and-survey.md`).

## What's deliberately not here

- **No server-side receipt validation.** No backend exists at all; `currentEntitlements`
  is the source of truth and the failure mode (a jailbroken device faking an
  entitlement) costs less than running and securing a validation service.
- **No introductory offer, free trial or promo codes** configured in code — the paywall
  renders whatever `Product.products` returns, so adding one is an ASC change plus
  copy, not a code change.
- **No rewarded ads and no "watch an ad to unlock a lesson" path.** The gate is one
  boolean; making it partially defeatable would need a second notion of entitlement.
- **No paywall A/B testing hook.** `source` attributes *where* a paywall opened, not
  which variant was shown — and the known gap is that `source` doesn't reach the
  purchase events (`08-analytics.md`).
