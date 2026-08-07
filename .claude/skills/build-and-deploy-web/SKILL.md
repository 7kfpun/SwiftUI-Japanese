---
name: build-and-deploy-web
description: Regenerate the promo website (web/) from scripts/build-web.py, verify the generated HTML/inline JS is well-formed, then deploy to Firebase Hosting. Use whenever scripts/build-web.py is edited, a new localized page is needed, or the user asks to "update the website" / "deploy the site" / "push the promo page".
when_to_use: build the website, deploy the website, update the promo site, publish web changes, firebase deploy, rebuild web pages
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

`--all` rebuilds every localized page (17 language folders, e.g. `web/ko/`,
`web/es/`, `web/zh-Hant/`, plus the English root `web/index.html`). **A bare
`python3 scripts/build-web.py` with no flag only rebuilds English** — it's
the default because translations were "paused" at some point, but don't
assume that's still desired; use `--all` unless you specifically only want to
touch the English page.

## 2. Verify before deploying

The generator is one big f-string/Template assembly over 17 languages — it's
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

Spot-check a handful of locales (not all 17 every time) — English plus 2–3
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

## 3. Deploy

```sh
npx firebase-tools deploy --only hosting
```

Project is `kf-nihongo` (see `.firebaserc`); `firebase.json` points hosting's
`public` dir at `web/`. `--only hosting` is important — this repo doesn't use
other Firebase products from the CLI, and scoping avoids touching anything
unrelated. If the command hangs on auth, `npx firebase-tools login --reauth`
first.

## Reminders

- `web/privacy.html` / `web/terms.html` are hand-maintained App Store
  compliance pages, not generated — if the user wants their content changed,
  edit them directly and they'll deploy as static files via the same
  `deploy --only hosting`, unaffected by `build-web.py`.
- Don't deploy without regenerating first if you touched `build-web.py` —
  `web/*/index.html` is regular (tracked) source in git, not gitignored, so a
  stale regeneration is a real drift, not just a local build artifact.
