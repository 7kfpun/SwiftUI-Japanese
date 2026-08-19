---
name: check-i18n-parity
description: Add, rename or remove a localized UI string end to end — L.t(...) at the call site, an entry in every language map of nihongo/UIStrings.json, the %@ placeholder and %% percent-escaping rules — then verify parity. Use for any user-facing text change in nihongo/*.swift, any direct edit to nihongo/UIStrings.json, and whenever LocalizationTests fails. A missing key never crashes and never looks obviously broken; it quietly under-translates one language, so only checking catches it.
when_to_use: add a new UI string, add a localized string, new button label, change UI text, check translations, verify UIStrings, i18n parity, localization check, missing translation key, LocalizationTests failing, unescaped percent, placeholder mismatch, translate this string
allowed-tools: Bash, Read, Edit
---

# Adding and checking a localized UI string

`nihongo/UIStrings.json` is the app's own UI text — buttons, titles, toggles —
one map per language. Don't trust any quoted count of languages or keys — derive
both from the file itself:

```sh
python3 -c "import json; d=json.load(open('nihongo/UIStrings.json')); \
print(len(d), 'languages x', len(d['en']), 'keys')"
```

It is a
**different file** from the vocabulary translations (`minna/<lang>/{1..50}.json`,
compiled into `MinnaData.json`'s `translations` map — see
`context/01-data-model.md`). Don't confuse the two when someone says "check
translations".

`L.t` (`nihongo/Localization.swift`) falls back current language → English → the
raw key. So a missing translation **never crashes and never renders an obviously
broken string** — it silently under-translates one language, on one screen, for
users you'll never hear from. Checking is the only detector.

## The five rules

1. **`L.t(...)` only**, never a literal. `CLAUDE.md`'s strings seam. The one
   documented exception is developer-only surfaces (Diagnostics), which are
   deliberately unlocalised.
2. **The key is the English text**, verbatim, in its unescaped form —
   `"Save %@%"`, `"Lesson %@"`, `"Beat Challenge %@ to unlock"`. There is no
   separate identifier scheme, and `en`'s value is normally the key again (the
   two differ only where escaping applies, rule 4).
3. **Every language map, in the same edit.** The file's own top-level keys are
   the list — derive it (`python3 -c "import json; print(sorted(json.load(open(
   'nihongo/UIStrings.json'))))"`) rather than working from a remembered set,
   which goes stale every time a language ships. Write a **real translation** for each; a copy
   of the English text passes every check and is the failure this whole workflow
   exists to prevent. English-only additions fail the suite.
4. **A literal `%` must be written `%%` in the value.** `L.t(_:_:)` (the varargs
   overload) runs the string through `String(format:)`. A trailing bare `%` is
   eaten, so the sign vanishes; a `%` before a letter parses as a specifier
   (`% s`) applied to something that isn't one. Both are visible only by eye, in
   one language, on one screen. Hence the split: key `"Save %@%"`, value
   `"Save %@%%"`. `LocalizationTests.literalPercentSignsAreEscaped` enforces this
   for **every** value, not only format strings.
5. **`%@` counts must match English exactly** in every language — same number,
   and in an order that makes sense for that language's grammar. There are 20
   format keys today.

## The check

From the repo root after any `UIStrings.json` edit:

```sh
python3 -c "
import json
d = json.load(open('nihongo/UIStrings.json'))
base = set(d['en'])
print('langs', len(d), '| keys', len(base), '|',
      'parity OK' if all(set(d[l]) == base for l in d) else 'PARITY FAIL')
"
```

`langs` must equal the file's language count — whatever it is today — and every
map must match `en`'s key set. On `PARITY FAIL`, find exactly which language/key diverges,
and catch the three failures the suite checks separately in one pass:

```sh
python3 -c "
import json
d = json.load(open('nihongo/UIStrings.json'))
en = d['en']; base = set(en)
fmt = {k: en[k].count('%@') for k in base if '%@' in k}
for lang, dict_ in sorted(d.items()):
    missing, extra = base - set(dict_), set(dict_) - base
    if missing or extra:
        print(lang, 'missing:', sorted(missing), 'extra:', sorted(extra))
    for k, n in fmt.items():
        if k in dict_ and dict_[k].count('%@') != n:
            print(lang, repr(k), 'has', dict_[k].count('%@'), 'placeholders, wants', n)
    for k, v in dict_.items():
        if v.replace('%@', '').replace('%%', '').count('%'):
            print(lang, repr(k), 'unescaped % ->', repr(v))
        if not v.strip():
            print(lang, repr(k), 'blank')
print('done')
"
```

## Then let the suite agree

`LocalizationTests` spends most of its tests on this file, each catching
a different mistake — a green parity script is not a green suite:

| Test | Catches |
|---|---|
| `uiStringsCoverEveryLanguageAndKey` | key-set drift, a language not in `VocabStore.availableLanguages`, a blank value |
| `formatPlaceholdersSurviveTranslation` | a translation that lost or gained a `%@` |
| `literalPercentSignsAreEscaped` | a bare `%` anywhere in any value |
| `formattedPercentStringsRenderTheSign` | `%%` that doesn't round-trip — formats every `%@%` key with `"42"` and requires exactly one visible `%` |

```sh
xcodebuild test -scheme nihongo -project nihongo.xcodeproj \
  -destination "id=5250BD7F-D8E3-484D-A209-23CCD0523399" \
  -only-testing:nihongoTests/LocalizationTests
```

See the `run-tests` skill for the general conventions (that exact destination id,
never build or launch the app, the Mach error -308 retry).

## Two knock-on effects worth remembering

- **The website borrows some of these strings.** `scripts/build-web.py`'s
  `load_app_strings()` reads `UIStrings.json` directly for `Correct!`, `Wrong`,
  `Next`, `Restart`, `Privacy Policy`, `Terms of Use`. Renaming or removing one of
  those keys silently degrades the promo page to its English fallback — see the
  `build-and-deploy-web` skill.
- **Dynamic Type and long languages.** A new string is also a layout change:
  German, Vietnamese and Burmese run long, and `CLAUDE.md` forbids fixed-height
  frames and fixed point sizes for exactly this reason. Prefer the shortest
  faithful translation over a literal one.
