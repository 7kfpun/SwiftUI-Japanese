---
name: build-and-deploy-web
description: Regenerate the promo website (web/, one localized page per app language) from scripts/build-web.py, verify the generated HTML/inline JS is well-formed, then deploy to Firebase Hosting scoped to --only hosting. Use whenever scripts/build-web.py or its `T` copy dict is edited, a new localized page is needed, or the user asks to "update the website" / "deploy the site" / "push the promo page" / "change the landing page copy". Also read this before any `firebase deploy` in this repo — firebase.json declares firestore.rules too, so an unscoped deploy publishes security rules by accident.
when_to_use: build the website, deploy the website, update the promo site, publish web changes, firebase deploy, rebuild web pages, edit landing page copy, update the FAQ on the site, promo page translations, firebase hosting
allowed-tools: Bash
---

# Regenerate and deploy the promo website

`web/index.html` and `web/<lang>/index.html` are **generated** by
`scripts/build-web.py` — one big Python template plus a translations dict.
**Never hand-edit a generated `index.html`; edit the script and re-run it.**
`web/privacy.html` and `web/terms.html` are the exception: they are **not**
touched by the generator at all, and they are the **live App Store Connect
privacy/terms URLs** — do not regenerate, template, or otherwise disturb them
as a side effect of anything in this workflow.

## 1. Regenerate

Run from the **repo root**:

```sh
python3 scripts/build-web.py --all
```

`--all` rebuilds every locale in the script's `LANG_META` table — the English
root `web/index.html` plus one folder per other locale, and `web/sitemap.xml` +
`web/robots.txt`. Derive the locale list from `LANG_META`, not from memory; it
tracks the app's language set and grows with it. **A bare `python3 scripts/build-web.py` with no
flag only rebuilds English** — the `else` branch at the bottom of the script
says "translations paused", which is stale: all 18 locales are fully translated
in the `T` dict. Use `--all` unless you specifically only want to touch the
English page.

There is **no `--check` mode** in this script (unlike
`fastlane/generate_framed_screenshots.py`, which has one). `--all` and an
optional nothing-else is the whole CLI. Step 2 below is the substitute.

Two things the generator reads, so both must exist and be current first:

- `nihongo/Resources/MinnaData.json` — the interactive quiz's Lesson 1 words and
  their per-language meanings (`load_quiz_words`). It is **git-ignored and
  regenerated**, so on a fresh clone or after `make clean` it doesn't exist —
  run `make data` (see the `refresh-data` skill) before this.
- `nihongo/UIStrings.json` — a handful of shared strings (`Correct!`, `Next`,
  `Privacy Policy`, …) are borrowed straight from the app so web and app agree
  (`load_app_strings`). A locale missing from it falls back to `en` silently.

**Copy lives in the `T` dict only** — one `dict(...)` per locale, every locale
carrying the same key set (`grep -n '^T = {' scripts/build-web.py` finds it).
You don't need a parity check for it: the page is built with
`string.Template.substitute`, so a key missing from one locale raises `KeyError`
and the build fails loudly on that locale. Running `--all` *is* the parity check.

## 2. Verify before deploying

The generator is one big f-string/Template assembly over 18 languages — it's
easy for a template edit to silently unbalance a tag or break inline JS in
one locale while looking fine in English. Check both:

**Tag balance** — count open vs. close tags per file, ignoring void elements
(`meta`, `link`, `img`, `br`, `input`, `hr`, `source`):

```sh
for f in web/index.html web/ko/index.html web/es/index.html web/zh-Hant/index.html; do
  python3 -c "
import re
html = open('$f', encoding='utf-8').read()
opens = re.findall(r'<([a-zA-Z][a-zA-Z0-9]*)(?:\s[^>]*)?(?<!/)>', html)
closes = re.findall(r'</([a-zA-Z][a-zA-Z0-9]*)>', html)
void = {'meta','link','img','br','input','hr','source'}
from collections import Counter
o = Counter(t for t in opens if t not in void)
c = Counter(closes)
diff = {k: o[k]-c.get(k,0) for k in o if o[k]-c.get(k,0)!=0}
print('$f', 'OK' if not diff else diff)
"
done
```

Spot-check a handful of locales (not every one every time) — English plus 2–3
non-Latin-script ones (CJK, Thai/Burmese) tend to expose template-substitution
bugs that Latin-script locales don't.

**Inline JS syntax** — extract every inline `<script>` block that is neither
an external `src=` script nor a `ld+json` block, concatenate, and run it
through Node's syntax checker (no execution, just parse):

```sh
python3 -c "
import re
html = open('web/index.html', encoding='utf-8').read()
blocks = []
for m in re.finditer(r'<script([^>]*)>(.*?)</script>', html, re.S):
    attrs, body = m.groups()
    if 'src=' in attrs or 'ld+json' in attrs: continue
    blocks.append(body)
open('/tmp/inline_all.js','w').write('\n;\n'.join(blocks))
"
node --check /tmp/inline_all.js && echo "JS OK"
```

Only proceed to deploy once both checks pass on the pages you changed.

## 3. Deploy — only when asked

`CLAUDE.md`: **never publish or deploy without being asked.** Regenerating and
verifying is the default deliverable; stop there and say the site is ready to
deploy unless the user asked for a deploy.

There is **no `firebase` on the PATH** on this machine — `which firebase` fails.
The working CLI is the npx cache copy (v15.26.0, logged in as
`710kfpun@gmail.com`):

```sh
FB=/Users/kf/.npm/_npx/7750544ccf494d8b/node_modules/.bin/firebase
$FB deploy --only hosting:main
```

`npx --no-install firebase-tools deploy --only hosting:main` resolves to the same
binary and works too; prefer the explicit path, and always pass `--no-install`
to npx so a cache miss fails fast instead of silently pulling a different
version. `$FB login:list` prints the logged-in account from the local credential
store; if a deploy hangs on auth, `$FB login --reauth`.

**`--only hosting:main` is mandatory, not tidiness.** `firebase.json` declares two
products now:

```json
{ "hosting": { "public": "web", ... }, "firestore": { "rules": "firestore.rules" } }
```

so a bare `firebase deploy` **also publishes `firestore.rules`**. Those rules
must ship in step with the app build (`hasOnly`/`hasAll` close every collection's
field set — see the `deploy-firestore-rules` skill), so pushing them as a
side-effect of a website copy change can start rejecting every survey write from
the currently-shipped app with nothing to show for it but a `survey_failed`
event. Scope every deploy.

Validate without publishing anything:

```sh
$FB deploy --only hosting:main --dry-run
```

Project is `kf-nihongo` (see `.firebaserc`); `firebase.json` points hosting's
`public` dir at `web/`.

## Reminders

- `web/privacy.html` / `web/terms.html` are hand-maintained App Store
  compliance pages, not generated — if the user wants their content changed,
  edit them directly and they'll deploy as static files via the same
  `deploy --only hosting:main`, unaffected by `build-web.py`.
- Don't deploy without regenerating first if you touched `build-web.py` —
  `web/*/index.html` is regular (tracked) source in git, not gitignored, so a
  stale regeneration is a real drift, not just a local build artifact.
- Before writing any new marketing claim into `T`, re-read **"Product facts copy
  must not get wrong"** in `CLAUDE.md`. Every item on that list was wrong in
  shipped copy once. The three that bite the website specifically: **no free
  lesson count** on the page, **never "native audio"** (it is synthesised — VOICEVOX
  for Minna, `say -v Kyoko`
  TTS), and the textbook's name is confined to the meta description and one FAQ
  answer (Guideline 5.2).
- Editing copy in `T` means editing it in **every locale**, same as
  `UIStrings.json`. The English-only half-edit is the usual mistake; the build
  won't catch it, because every key still exists.
