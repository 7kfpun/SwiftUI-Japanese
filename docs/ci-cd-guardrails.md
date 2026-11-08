# CI/CD guardrails (FOX-169)

How a change gets from a ticket to `main`, and what enforces each step. Ported from
SwiftUI-TWAQI's guardrails (its FOX-38, FOX-65 and FOX-79), cut down to what this repo has:
one iOS test target, an Android app, a public website and two store listings.

```
Linear FOX-nn → Orca codes on a feature/ or fix/ branch → draft PR → self-review → CI green → ready
  → another agent's review (LGTM) → user greenlight → squash-merge
  → (only if the ticket names it) TestFlight · App Store Connect · Play · Firebase Hosting
```

A merge ships nothing to users, except that `deploy-web.yml` deploys the site when `web/`
changes. Every other release step is a separate, deliberate action, taken only when the
ticket or request names it (see the root `CLAUDE.md`).

## Which PRs get checks

Every pull request **into `main` or any `feature/*` integration branch**, whatever its head
branch is called. Two rules replaced the old "head must start with `feature/`, base must be
`main` or `feature/fox-145-android`":

- **Head branch: no filter.** `fix/…` PRs (#28, #30) used to skip the iOS tests and the
  review without a word. Naming is enforced by `PR policy` instead, which fails a head that
  lacks a known prefix (`feature/`, `fix/`, `chore/`, `docs/`, `ci/`, `refactor/`, `test/`,
  `perf/`), so a skip can no longer happen quietly.
- **Base branch: `main` or `feature/**`.** A new integration branch needs no workflow edit:
  name it `feature/…` and its PRs are covered. A base that is neither (say `release/1.0`)
  gets no workflows at all. To cover another prefix, add it to the `branches:` list in each
  workflow (`ci.yml`, `android.yml`, `claude-code-review.yml`, `lgtm.yml`, `pr-policy.yml`,
  `public-text.yml`) and to `is_gated_base` in `tools/lgtm_gate.py`.

## Checks on a PR

| Check | Workflow | Runs on | Fails when |
|---|---|---|---|
| `Tests` | `ci.yml` | non-draft | the level script's tests fail, the build fails, or `nihongoTests` fails. Green in seconds at the **skip** level ([levels](#tests-levels)). |
| `Android` | `android.yml` | every PR, drafts too (green at once when nothing Android reads changed) | ktlint, Android lint, JVM tests or the debug build fail in `android/`; generated strings, the analytics catalog or the Play listing text are stale. |
| `Vulnerabilities` | `ci.yml` | non-draft | the dependency scan could not read `Gemfile.lock` or `Package.resolved` ([below](#vulnerability-scan)). Known vulnerabilities and a gitleaks finding are warnings and a PR comment. |
| `PR policy` | `pr-policy.yml` | every PR, drafts too, again on a title or body edit | the head branch has no known type prefix; no `FOX-nn` in the branch, title or body; a `Depends on #N` PR isn't merged. |
| `Public text` | `public-text.yml` | non-draft, again on each description edit | the title, description, a commit message or an added line names a non-website host, an IP or network range, a private email, or network-exposure details (`tools/public_text_check.py`). See [Public repo](#public-repo-what-stays-out). |
| `LGTM` (status) | `lgtm.yml` | every push, review and PR comment | pending until a reviewer's LGTM covers the head: a review or comment whose first line is `**<Name> LGTM**`. A rebase or update from `main` with no change of its own keeps it; a later "changes needed" resets it; the advisory `claude[bot]` doesn't count. Details: [master-protection.md](master-protection.md). |
| `review` | `claude-code-review.yml` | non-draft | advisory Claude review, never required ([below](#the-claude-review)). |
| `CI cache` | `ci-cache.yml` | push to `main`, daily, manual | fills the `Tests` caches; not a PR check. |

Which of these block a merge is set by the ruleset in
[master-protection.md](master-protection.md) (proposed, not applied).

### Tests levels

`ci.yml` first runs `tools/test_ci_test_level.py` and `tools/ci_test_level.py check`, then
decides a level from the PR's file list (`gh api …/pulls/N/files`). The highest level any
file needs wins:

| Level | PR touches only… | Runs |
|---|---|---|
| **skip** | `android/`, `web/`, `web-jlpt/`, `fastlane/`, `screenshots/`, `context/`, `docs/`, `tools/`, `.claude/`, `.github/` (except `ci.yml` and the build action), the Android/web/store scripts under `scripts/`, any `.md` | nothing more; the check is green |
| **test** | anything else: Swift, `UIStrings.json`, resources and audio, asset catalogs, `project.pbxproj`, the `minna` submodule pointer, the data-generating scripts, `ci_scripts/`, `Gemfile.lock`, `Package.resolved`, `ci.yml`, the build action, `tools/ci_test_level.py` | course data, caches, `build-for-testing`, then `nihongoTests` |

Unlike TWAQI there is no *build only* level and no guarded subset: this repo's job always
runs the whole `nihongoTests` target, so a PR is either skippable or it runs everything.
Anything not listed as skippable runs the tests, so a new top-level folder fails safe.

- The PR label **`ci-full-tests`** forces **test**. Labels are read when the job runs, so add
  the label and re-run the job (or push); adding a label alone starts no run. The label has to
  exist first (`gh label create`, see [master-protection.md](master-protection.md#apply-after-the-fox-169-pr-is-merged)).
- An empty file list, or a failed files or labels API call, gives **test**: never skip on doubt.
- The step prints the level and the files that decided it, and writes them to the job summary.
- The check is `Tests` at every level, so the ruleset's required checks are unaffected.
- `check` fails the job when a `SKIP_PREFIXES`, `SKIPPABLE_SCRIPTS` or `ALWAYS_TEST` entry
  matches nothing (a renamed folder would otherwise leave a stale rule).

### Shared build and caches

The job's data, plist, cache and build steps are one composite action,
`.github/actions/unit-tests-build`, used by `ci.yml` and by `ci-cache.yml`. Keys and build
flags live only there, so the two cannot drift apart. It:

1. generates the course data from the private `minna` submodule with `MINNA_DEPLOY_KEY`
   (`ci_scripts/ci_post_clone.sh`),
2. copies the example plists in `config/` over the gitignored ones,
3. restores the Swift package and DerivedData caches (`actions/cache/restore`),
4. runs `xcodebuild build-for-testing` for the `nihongo` scheme on iPhone 17 Pro / iOS 26.5,
5. saves each cache only when its exact key missed.

`ci.yml` then runs `test-without-building -only-testing:nihongoTests`.

A PR can read its own caches and `main`'s, never another PR's, and CI runs only on
`pull_request`, so before this every PR's first run was cold. `CI cache` runs on `main`:
on a push that changes `Package.resolved`, `project.pbxproj`, `ci_scripts/`, `ci.yml`,
`ci-cache.yml` or the action; daily at 03:17 UTC (a runner image with a new Xcode build
changes the DerivedData key; caches unused for 7 days are evicted); and by
`workflow_dispatch`. With both keys present it only restores them and stops. The DerivedData
key is exact (Xcode build + `Package.resolved`), so products built against other
dependencies are never restored, and app sources always rebuild (checkout gives them new
mtimes). A miss just downloads and builds as before.

### Vulnerability scan

`Vulnerabilities` runs gitleaks (advisory) and osv-scanner over `Gemfile.lock` and the
SwiftPM `Package.resolved`. It used to report "0 packages, lockfile format may be
unrecognized" for both and carry on green, so the Swift dependencies (Firebase, Google Mobile
Ads, …) looked scanned and weren't.

The cause was the report, not the scanner: osv-scanner reads both files (it logs
`found 16 packages` for the pins, `found 112 packages` for the gems), but its JSON lists only
packages that **have vulnerabilities**, so a clean lockfile counted as zero. The step now
takes the package count from the scanner's own "found N packages" line, and a lockfile with no
such line, a count of zero, or output that isn't JSON fails the check in the next step
(`Fail when a lockfile was not scanned`). Known vulnerabilities still only warn and post a PR
comment; there is no severity gate. The `Gemfile.lock` advisories were fixed on `main`
by #33 (fastlane 2.241.2), so the scan starts green.

### The Claude review

`claude-code-review.yml` runs `anthropics/claude-code-action` with a prompt written from this
repo's `CLAUDE.md`: severity tiers (Blocking, Should fix, Suggestion), an inline comment per
Blocking and Should-fix finding with a failure scenario and a concrete fix, and one summary
comment whose first line reads `**Claude Code Review** — <n> blocking, <n> should fix, <n> suggestions`.
It covers this repo's seams, invariants and generated-file rules, the product facts copy must
not get wrong, the store policies (Google Play In-App Review, App Store 5.x) and iOS ↔ Android
parity. When `CLAUDE.md` gains a rule that review should enforce, add it to the prompt.

**It cannot review its own change.** `claude-code-action` refuses to run unless the PR's copy
of the workflow file equals the default branch's, so a PR that edits
`claude-code-review.yml` gets no review from the new prompt. Verify a prompt change after it
merges:

1. From `main`, branch `docs/fox-nn-review-check` and make a change the prompt should flag,
   for example a UI string in `nihongo/UIStrings.json` with an English entry and none for
   the other 18 languages, or "Lessons 1–5 are free" added to a store `description.txt`
   (both are Blocking in the prompt). Nothing needs to be correct or buildable.
2. Open it as a **draft**. Confirm no review ran (drafts are skipped).
3. Mark it ready. Within a few minutes a summary comment starting `**Claude Code Review** —`
   should appear, with an inline comment on the flagged line. The `review` check should be
   green, not skipped.
4. Close the PR and delete the branch.

## Undraft race

`ci.yml` and `claude-code-review.yml` cancel superseded runs per PR, and their concurrency
key includes whether the PR is a draft. A push and "Ready for review" in the same second used
to let the push's run, whose payload still said draft and so skipped everything, cancel the
ready-for-review run, which left CI skipped. With draftness in the key, a draft run can only
cancel draft runs, so undrafting always gets a full run. `PR policy` and `LGTM` don't depend
on draftness. `android.yml` runs for drafts too.

## Stacked PRs

`PR policy` re-runs on a PR's own events, so a stacked PR stays red after its base merges
until it is updated. Update the branch from `main` or re-run the check. Once the ruleset
requires up-to-date branches, the update has to happen anyway.

## Public repo: what stays out

`Vulnerabilities` catches secrets. `Public text` catches the patterns below in a PR's
title, description, commit messages and added lines, but not in comments, reviews, or a
description edited back later, and wording slips past patterns. Commit messages, PR titles
and descriptions, review and issue comments, and docs are all public, and so is a
description's **edit history**.

Keep out of all of them:

- IP addresses, network ranges, allow-lists, and changes to network access rules.
- Security posture: what was or is reachable from anywhere, what was locked down and when.
- Incident details: attacker or scanner IPs, outage causes, what was hit or exposed.
- Secret values or any part of them (tokens, passwords, keys, DSNs), and account emails.
- **Hostnames, except the public websites.** `japanesedaily.wahthefox.com`,
  `kf-nihongo.web.app` and `jlpt-jp.web.app` are fine. Every other host, the Directus
  survey endpoint above all, is named by its role ("Directus"). The real value stays in the
  code or config that needs it (`Survey.swift`, the Android example properties, tests).

Fine to write: resource **names** a runbook or the code needs, commands with placeholders,
and test results. Where the rest goes: the Linear ticket.

If something slipped into a PR description: edit it out, then delete the older versions from
the description's edit history (the "edited" menu → the revision → **Delete revision from
history**; needs a logged-in browser, not possible through the API). In a commit message or
a file: rewrite the branch before merge; after merge, treat it as public.

## What the user has to do

None of this is applied by the PR:

1. **Ruleset.** Apply [`master-ruleset.json`](master-ruleset.json) with the commands in
   [master-protection.md](master-protection.md). Rollback is one `DELETE`.
2. **Label.** `gh label create ci-full-tests` (command in the same file).
3. **Secrets** already present: `MINNA_DEPLOY_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`. No new
   secret is needed.
4. **Verify the review workflow** on a throwaway PR after the merge ([above](#the-claude-review)).
