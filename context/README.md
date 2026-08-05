# Rebuild context — Minna no Nihongo (SwiftUI port)

This folder is the **analysis + reference** for rebuilding the old React Native app
(`7kfpun/JapaneseReactNative`, "Minna no Nihongo") as a native **SwiftUI + SwiftData**
app in this repo (`nihongo/`).

Goal: **analyze fully first, rebuild second.** These docs are the analysis. The
rebuild has not started — the app is still the default Xcode SwiftData template
(`nihongo/Item.swift`, `nihongo/ContentView.swift`).

## Scope

Learning mechanics **only**. The following are intentionally **out of scope** and
excluded from every doc:

- premium/subscription prompts, in-app purchases, ads (AdMob), push notifications
  (OneSignal), analytics/tracking, auth
- **bookmarking / star ratings** and the Bookmark tab (dropped)
- the **Today** tab (dropped/deferred)
- **About** tab and any **study reminder** / notification feature

The rebuild is a clean, offline, ad-free study app. All vocab data ships **inside
the app bundle** (see "Data source" below) — there is no backend.

## How to read this folder

| Doc | Covers |
|---|---|
| `00-overview.md` | What the app is, the tab architecture, navigation graph |
| `01-data-model.md` | The `minna` vocab schema, join key, how to load it in Swift |
| `03-kana.md` | **Kana** tab — hiragana/katakana reference + quiz |
| `04-lessons.md` | **Lessons** tab — the 5 study modes (the core engine) |
| `05-shared-and-audio.md` | Cross-tab pieces: card, visibility toggles, audio/pronunciation |
| `06-swiftui-rebuild-plan.md` | Proposed SwiftUI views + SwiftData models, phased plan |
| `07-ux-ui.md` | Visual identity (color, type, layout, feedback) + SwiftUI UI direction |

(`02-today.md` is intentionally absent — the Today tab is deferred.)

Each feature doc ends with a **"SwiftUI target"** section: the concrete views/models
to build for that feature.

## Reference source (pointers stay valid)

The original RN JavaScript is **vendored** under `reference-rn/app/` (the upstream
repo's `app/` folder, ~412K, no `node_modules`). Every `file:line` pointer in these
docs refers to that vendored copy, so the pointers never break even after the
`/tmp` clone is gone. Pointers anchor on **symbol names first, line numbers second**
(line numbers are from the vendored snapshot and may drift if the files are edited).

Example pointer: `reference-rn/app/containers/lessons/assessment.js → getTiles()
(~L231)`.

## Data source — bundle the `minna` submodule

The vocab data lives in the **`minna` git submodule** at
`nihongo/Resources/minna/` (50 lessons, 2089 entries, 7 translation languages).
Its own `SCHEMA.md` is authoritative for the data format; `01-data-model.md`
explains how to consume it from Swift.

**Decision (confirmed): the SwiftUI app bundles the `minna` submodule** as a folder
reference in the app target, so all data ships inside the `.app` and works fully
offline. The old RN app did *not* bundle it — it downloaded the JSON at build time
(`scripts/download-minna.js`). We do the opposite: no download step, no backend.
See `01-data-model.md` for the exact Xcode folder-reference + `Bundle` loading
setup.

## RN → SwiftUI tech map (quick reference)

| React Native | SwiftUI / Apple |
|---|---|
| `react-navigation` bottom tabs | `TabView` |
| `createStackNavigator` | `NavigationStack` + `navigationDestination` |
| `react-native-simple-store` (AsyncStorage) | `@AppStorage` (prefs) / SwiftData (bookmarks) |
| component `state` + `setState` | `@State` / `@Observable` view models |
| `react-native-tts` | `AVSpeechSynthesizer` behind a `Pronouncer` protocol (see `05-shared-and-audio.md`) |
| `fuse.js` fuzzy search | custom scorer or simple `localizedCaseInsensitiveContains` + ranking |
| `rn-viewpager` (IndicatorViewPager) | `TabView(.page)` or segmented `Picker` + paging |
| `Ionicons` / vector icons | SF Symbols |
| i18n `minna.{lesson}.{romaji}` JSON | `minna/{lang}/{lesson}.json` decoded to `[String:String]` |
