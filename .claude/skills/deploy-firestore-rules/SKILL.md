---
name: deploy-firestore-rules
description: Publish firestore.rules to the kf-nihongo Firebase project with `firebase deploy --only firestore:rules`, and keep the rules in step with Survey.Context in the app. Use whenever a field is added to or removed from Survey.Context / Survey.Intro / Survey.Rating / Survey.Feedback, whenever firestore.rules is edited, whenever SurveyTests.contextKeysMatchThePublishedRules fails, or when survey/feedback/rating writes are being rejected ("survey_failed", "write failed", "Missing or insufficient permissions"). The rules close every collection's field set with hasOnly/hasAll, so one unpublished field rejects every write silently.
when_to_use: deploy firestore rules, publish security rules, firestore:rules, survey writes failing, survey_failed, feedback not arriving in Firestore, permission denied on write, added a field to Survey.Context, contextKeysMatchThePublishedRules failing, App Check
allowed-tools: Bash, Read, Edit
---

# Publishing `firestore.rules`

`firestore.rules` (repo root) governs the app's **only** server write —
`nihongo/Survey.swift`, three write-only collections: `survey_intro`,
`survey_rating`, `survey_feedback`. `context/09-intro-and-survey.md` documents
the design; this skill is about not breaking it.

## The trap, in one paragraph

Every collection is closed by `hasExactly(data, own)`, which is
`keys().hasOnly(context() + own) && keys().hasAll(context() + own)`. **Both
halves.** So the field set the app sends must equal the field set the rules
declare, exactly — an extra field fails `hasOnly`, a missing one fails `hasAll`.
Add one key to `Survey.Context.fields` without republishing and **every write to
all three collections is rejected**, not just the new one. And the rejection is
nearly invisible:

- The write **appears to succeed at the call site.** Firestore's offline
  persistence applies it locally and only learns it was refused on flush, so the
  error arrives in the completion handler, later.
- All you get is a DEBUG `print` (`survey: <collection> write failed — …`) and a
  `survey_failed` analytics event. No crash, no UI, nothing in TestFlight.

This has been hit three times in one day. Assume it will be hit again.

## Hard rule: the rules ship *with* the build

`CLAUDE.md`: **Firestore rules must ship with the app.** Publishing the rules and
shipping the app that matches them are one change, in this order:

1. **Neither ordering alone is safe.** Rules declaring the new field reject the
   already-shipped app (`hasAll` wants a key it doesn't send); rules declaring the
   old set reject the new app (`hasOnly` sees an extra key). Whichever you publish
   first, some live version is broken until the other side catches up — and the
   old version stays live for as long as users take to update, which is not a
   window you control.
2. **So prefer not to move the key set at all.** A sentinel value in an existing
   field (`''`, `0`, `'unanswered'`) is the pattern this schema already uses
   everywhere, and `v` is a schema version int that exists precisely so a later
   field can be added "without making every existing document ambiguous". Reach
   for those first.
3. **If the key set must move, publish a transition rule set** that accepts both
   payloads, rather than swapping one closed set for another. `hasExactly` can't
   express it, so widen `hasOnly` and narrow `hasAll` for one release:

   ```
   // transition: accept the shipped payload and the next one
   d.keys().hasOnly(context().concat(own).concat(['new_field']))
     && d.keys().hasAll(context().concat(own))
   ```

   Publish that, ship the app, then tighten back to `hasExactly` with
   `new_field` folded into `context()` once the old version's traffic is gone.
   Two publishes, no rejection window. `SurveyTests` moves with the **app**, not
   with either publish — it pins `Survey.Context.keys`, so it gains `new_field`
   in the same change the app does.

## The guard: `SurveyTests.contextKeysMatchThePublishedRules`

`nihongoTests/nihongoTests.swift`'s `SurveyTests` transcribes the rules' own
lists into Swift and pins them against the app:

- `ruleContextKeys` — a hand-copy of `context()` in `firestore.rules`; asserted
  equal to `Survey.Context.keys`, and to `context.fields.keys` **plus `at`**
  (the server stamps `at` via `FieldValue.serverTimestamp()`, so the app's map is
  the declared set minus that one key).
- `ruleFeedbackKeys` — a hand-copy of `survey_feedback`'s own-field list,
  asserted against the payload `FeedbackDraft.submission(source:)` actually
  builds. A field named in the rules but never sent fails `hasAll` just as loudly
  as an unexpected one fails `hasOnly`, so both directions are checked.
- `feedbackEnumsAreWithinWhatTheRulesAccept` — the closed value sets
  (`Feedback.Source`, `Feedback.Area`, `kind`) against the rules' `in [...]`
  lists. A value the app can produce but the rules reject is a submission that
  vanishes.

**These are hand-transcriptions. Nothing reads the `.rules` file at test time.**
So when you change `firestore.rules`, you must also change `SurveyTests`, and the
test comment says as much ("Update both together, never one"). Run it:

```sh
xcodebuild test -scheme nihongo -project nihongo.xcodeproj \
  -destination "id=5250BD7F-D8E3-484D-A209-23CCD0523399" \
  -only-testing:nihongoTests/SurveyTests -only-testing:nihongoTests/FeedbackTests
```

A green `SurveyTests` means the app and the *file* agree. It says nothing about
what is **published** — that is the deploy below, and there is no test for it.

## Validate, then publish — only when asked

`CLAUDE.md`: **never publish or deploy without being asked.** Firestore rules are
outward-facing. Write the rules, update `SurveyTests`, run them, and stop.

There is **no `firebase` on the PATH** on this machine (`which firebase` fails).
Use the npx cache binary — v15.26.0, logged in as `710kfpun@gmail.com`:

```sh
FB=/Users/kf/.npm/_npx/7750544ccf494d8b/node_modules/.bin/firebase
$FB --version && $FB login:list
```

Dry run first. It compiles the rules server-side and reports errors without
publishing anything:

```sh
$FB deploy --only firestore:rules --dry-run
```

Then, when asked:

```sh
$FB deploy --only firestore:rules
```

**`--only firestore:rules` is mandatory.** `firebase.json` declares hosting as
well:

```json
{ "hosting": { "public": "web", ... }, "firestore": { "rules": "firestore.rules" } }
```

so a bare `firebase deploy` would also push whatever is currently in `web/` —
possibly a stale generation, since `web/**` is tracked source generated by
`scripts/build-web.py` (see `build-and-deploy-web`). Scope it. Project is
`kf-nihongo` (`.firebaserc`).

## Troubleshooting: writes are being rejected

Work down this list; the first two are by far the most common.

1. **Field-set drift.** Diff the app against the file before suspecting anything
   else:

   ```sh
   grep -n "static let keys" -A 10 nihongo/Survey.swift
   sed -n '/function context()/,/}/p' firestore.rules
   ```

   If they differ, that's it. If they agree, the *published* rules may still be
   older than the file — the Firebase console's Firestore → Rules tab shows what
   is live, with a version history.
2. **A value outside a closed set**, not a missing key. `hasOnly`/`hasAll` pass
   and `validContext` still fails: `appearance` must be `light`/`dark`,
   `platform` must be `iOS`, `knows_kana` ∈ `none|hiragana|both|unanswered`,
   `goal` ∈ `travel|jlpt|work|culture|other|unanswered`, `textbook_lesson` in
   -1…50, `message` 1…2000 chars, `stars` 0…5 (1…5 for `survey_rating`),
   `lesson` 0…50, `item` ≤ 60 chars, and every string has its own size cap. A new
   `Feedback.Area` case added in Swift without adding it to the rules' `in [...]`
   list rejects only the reports that pick it — the subtlest version of this bug.
3. **`at`.** The rules require `at == request.time`, so the app must send
   `FieldValue.serverTimestamp()`, never a device date. Device clocks lie and the
   offline queue can flush hours late.
4. **App Check.** Enforcement (Firebase console → App Check → Firestore) is what
   makes these collections write-only-by-attested-builds rather than
   write-by-anyone; there is no Firebase Auth in this app on purpose (no accounts,
   no install ID, no ATT). A debug build without a registered App Check debug
   token is rejected before the rules are even evaluated, which looks identical to
   a rules failure from the app's side. `context/09-intro-and-survey.md` covers
   the setup.
5. **No Firebase at all.** `Survey.submit` returns early when
   `FirebaseApp.app() == nil` — a clone with no `GoogleService-Info.plist` writes
   nothing and logs nothing. Not a rules problem.

Note that `Survey` deliberately does **not** honour the analytics opt-out or skip
`#if DEBUG` (a volunteered answer isn't telemetry, and an unexercised write path
breaks unnoticed). So development submissions land in the same collections as real
ones, distinguishable only by the `debug` field — useful when reading the console,
and a reason not to test rules changes casually.
