---
name: check-i18n-parity
description: Verify every language in nihongo/UIStrings.json has exactly the same set of keys as English after adding, renaming, or removing a localized string. Use after any edit that adds a new UI string, adds a new key to CardOptionsBar/KanaBrowserView/etc., or touches nihongo/UIStrings.json directly — a missing key in one language silently falls back to English (or the raw key) at runtime instead of erroring, so this only gets caught by checking, not by the compiler.
when_to_use: check translations, verify UIStrings, i18n parity, localization check, add a new UI string, missing translation key
allowed-tools: Bash
---

# Check `UIStrings.json` translation parity

`nihongo/Localization.swift` (`L.t`) falls back English → the raw key string
whenever a language is missing a key — which means a missing translation
**never crashes and never shows an obviously-broken string**, it just quietly
under-translates one language. The only way to catch that is to explicitly
diff every language's key set against English, every time a string is added,
renamed, or removed.

This is a **different file** from the vocabulary translations
(`minna/<lang>/{1..50}.json`, compiled into `MinnaData.json`'s `translations`
map — see `context/01-data-model.md`). `UIStrings.json` is the app's own UI
text (buttons, titles, toggles); don't confuse the two when someone says
"check translations."

## The check

Run from the repo root after any `UIStrings.json` edit:

```sh
python3 -c "
import json
d = json.load(open('nihongo/UIStrings.json'))
base = set(d['en'])
print('langs', len(d), '| keys', len(base), '|',
      'parity OK' if all(set(d[l]) == base for l in d) else 'PARITY FAIL')
"
```

`langs` should be **17** (en, zh, zh-Hant, vi, de, th, my, es, fr, ru, bn, hi,
ta, te, fil, id, ko — the same set as `VocabStore.availableLanguages`). If it
prints `PARITY FAIL`, find exactly which language/key diverges:

```sh
python3 -c "
import json
d = json.load(open('nihongo/UIStrings.json'))
base = set(d['en'])
for lang in d:
    missing = base - set(d[lang])
    extra = set(d[lang]) - base
    if missing or extra:
        print(lang, 'missing:', sorted(missing), 'extra:', sorted(extra))
"
```

## Fixing a gap

Add the missing key with a real translation for **every** language in the
file, not just a placeholder copy of the English text — dropping in an
English string for `zh`/`th`/`my`/etc. defeats the point and is easy to forget
to revisit later. When adding a brand-new UI string, add it to all 17
language blocks in the same edit.

After fixing, re-run the parity check above, then confirm the test suite
agrees — `nihongoTests` has a standing test for exactly this
(`LocalizationTests.uiStringsCoverEveryLanguageAndKey`):

```sh
xcodebuild test -scheme nihongo -project nihongo.xcodeproj \
  -destination "id=5250BD7F-D8E3-484D-A209-23CCD0523399" \
  -only-testing:nihongoTests/LocalizationTests
```

See the `run-tests` skill for the general test-invocation conventions
(exact destination id, never build/launch the app, Mach error retry).
