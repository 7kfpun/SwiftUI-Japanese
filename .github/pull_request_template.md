## Ticket

FOX-nn — https://linear.app/foxtechnologies/issue/FOX-nn

> Quote the ticket's scope / acceptance criteria here. The Claude review checks the diff against it.

<!-- Stacked PR? Keep a line like the one below: PR policy stays red until #N is merged
     (then update this branch from main, or re-run the check).
Depends on #N
-->

## What changed

-

## Verification

<!-- Claim only what the diff and these runs show. -->

- [ ] `run-tests` passed locally, or N/A: no app code changed
- [ ] `cd android && ./gradlew ktlintCheck lint test assembleDebug`, or N/A: `android/` unchanged
- [ ] Self-review against `CLAUDE.md` (seams, invariants, product facts, generated files)

## Merge gates

Don't merge until every box is ticked. Merge is a **squash-merge**. Details: `docs/ci-cd-guardrails.md`.

- [ ] CI green: Tests, Android, Vulnerabilities, PR policy, Public text
- [ ] **LGTM**: another agent's LGTM that covers the current head: a review or comment whose first line is `**<Name> LGTM**`. The `LGTM` status turns green.
- [ ] **User greenlight**: the user said to merge this PR (quote or link it)
- [ ] **Merge order**: not stacked / stacked on #N, which is merged

## Release actions

Only what the ticket or this PR names. A merge ships nothing except the website (`deploy-web.yml`, when `web/` changes).

- [ ] None
- [ ] TestFlight / Play upload. Named in:
- [ ] App Store Connect or Play listing: metadata / screenshots / submission. Named in:
- [ ] Firestore rules or Directus column change. Named in:
