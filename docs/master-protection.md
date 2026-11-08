# `main` protection (proposed, FOX-169)

**Status: proposed, not applied.** The repository has **no ruleset and no branch
protection** today (`gh api repos/7kfpun/SwiftUI-Japanese/rulesets` lists none). It allows
squash merges only. The owner applies the ruleset with the commands below **after** the
FOX-169 PR is merged. Applying it first would block every open PR, because `PR policy`,
`Public text` and `LGTM` only exist on branches that contain the FOX-169 workflows.

## What the proposal adds

[`master-ruleset.json`](master-ruleset.json) is the whole ruleset. The file name stays from
the TWAQI original; the ruleset targets the default branch, `main`.

| Rule | Setting | Why |
|---|---|---|
| `deletion`, `non_fast_forward`, `required_linear_history` | on | No force-push, no deleting `main`, no merge commits. |
| `pull_request` | required, 0 approvals, squash only | Blocks direct pushes. 0 approvals because the account that opens every PR can't approve its own; the `LGTM` status takes the place of an approval. |
| `required_status_checks` | `strict: true` | The branch must be up to date with `main` before merging, so stacked PRs merge in order and each is tested against what is on `main`. |
| required: `Tests` | `ci.yml` | iOS unit tests. Green in seconds when only paths the iOS tests cannot see changed (the **skip** level, [ci-cd-guardrails.md](ci-cd-guardrails.md#tests-levels)). |
| required: `Android` | `android.yml` | ktlint, lint, JVM tests and a debug build. Green at once when nothing Android reads changed. |
| required: `Vulnerabilities` | `ci.yml` | Fails on a verified secret only; **and** now on a lockfile the scanner could not read. Known vulnerabilities are warnings. |
| required: `PR policy` | `pr-policy.yml` | Branch type prefix, a `FOX-nn` ticket, `Depends on #N` merged first. |
| required: `Public text` | `public-text.yml` | The repository is public: no private hosts, IPs or emails. |
| required: `LGTM` | `lgtm.yml` | Commit status set from another agent's review (below). |
| `bypass_actors` | none | Every agent uses the owner's admin account; an admin bypass would exempt them too. |

`integration_id: 15368` is GitHub Actions: those checks can only be satisfied by a workflow.
`LGTM` is a commit *status*, not a check run, and is left without an `integration_id` on
purpose: if a ruleset does not match a status posted with `GITHUB_TOKEN` to the Actions app,
every PR would be blocked. The trade-off is that a status posted by hand with a personal
token would also count. Optional hardening once the ruleset is live: add
`"integration_id": 15368` to that entry, then confirm on one PR that a real agent review
still unblocks the merge; remove the id again if it doesn't.

**Skipped counts as passing.** A required check whose job is skipped (`Tests`, `Public
text` and `Vulnerabilities` skip on drafts) satisfies the ruleset. What never satisfies it
is a check that does not report at all, which is why none of these workflows has a `paths`
filter and why `Tests` decides its level inside the job instead.

`Claude Code Review` (check name `review`) stays advisory, not required: it depends on an
external token and quota, and its findings reach the merge decision through the reviewer's
verdict anyway.

## The LGTM approach

GitHub won't let an account approve its own PR, and every PR here is opened from the
owner's account. A second approver account would need another seat and its credentials. The
chosen approach is a status gated on a reviewer's LGTM: a pull request review or comment
counts when its first line is "LGTM", optionally after one word naming the reviewer, with
nothing after it but punctuation or a `(head <sha>)` note (`**Grok LGTM**`,
`**Codex LGTM** (head abc1234)`, `LGTM`). "LGTM?", "LGTM, but …" and a negating word in the
name slot ("Never LGTM", "Almost LGTM") don't count. The gate keeps no list of agents.

[`lgtm.yml`](../.github/workflows/lgtm.yml) runs on every push to the PR, every review and
every PR comment, for PRs into `main` or any `feature/*` branch.
[`tools/lgtm_gate.py`](../tools/lgtm_gate.py) then sets the `LGTM` status on the head commit:

- **pending** until an LGTM exists, when a later "changes needed" overrides it, and again
  when the branch changes after it.
- **success** when the latest verdict is an LGTM left on the head commit, or on an earlier
  commit with the same net change. That covers a rebase or "Update branch" with no edits of
  its own. "Same net change" compares the PR's own added and removed lines per file against
  the merge base, ignoring blob ids, hunk positions and unchanged context. Resolving a
  conflict or any other edit of the branch's own changes needs a fresh LGTM.
- A review is tied to its commit. A comment is tied to the commit in its `(head <sha>)`
  note; without a note it covers the head only when written at or after that commit.
- Dismissing a review withdraws it. A first line of "changes needed" or "changes
  requested", or a review in GitHub's `CHANGES_REQUESTED` state, sets the status back to
  pending until a newer LGTM.

Limits, stated plainly: the agents and the owner share one GitHub account, so the gate
checks the review's first line, not a separate login. A bot counts when its first line is a
verdict, except `claude[bot]`, whose review is advisory and whose progress comment appears
before it has reviewed anything. A person counts only with owner, member or collaborator
access. The gate script runs from the base branch's copy, so a PR can't loosen its own gate,
but a PR that edits `.github/` or `tools/` still deserves a careful read.

The agent review loop (the `review-routine` and `ticket-routine` skills) already posts
`<Agent> LGTM` comments with a merge-risk label; `LGTM` is the CI side of that.

## Apply (after the FOX-169 PR is merged)

There is nothing to replace, so this *creates* the ruleset.

```sh
# 0. Nothing live today; confirm.
gh api repos/7kfpun/SwiftUI-Japanese/rulesets --jq '.[] | [.id, .name, .enforcement] | @tsv'

# 1. Create it. Start in evaluate mode if you want a dry run first (see below).
gh api --method POST repos/7kfpun/SwiftUI-Japanese/rulesets --input docs/master-ruleset.json

# 2. Check it.
gh api repos/7kfpun/SwiftUI-Japanese/rulesets --jq '.[] | [.id, .name, .enforcement] | @tsv'
id=$(gh api repos/7kfpun/SwiftUI-Japanese/rulesets --jq '.[] | select(.name == "main") | .id')
gh api "repos/7kfpun/SwiftUI-Japanese/rulesets/$id" --jq '.rules[].type'
#    deletion, non_fast_forward, required_linear_history, pull_request, required_status_checks
```

Dry run: set `"enforcement": "evaluate"` in the JSON before the POST (evaluate mode needs a
GitHub plan that supports it; if the POST is refused, use `"active"`), watch a PR or two,
then PUT the file back with `"active"`.

Before applying, create the label the test-level rule reads, and confirm both secrets exist:

```sh
gh label create ci-full-tests --color 5319e7 \
  --description "Run the iOS unit tests even when only skippable paths changed"
gh secret list    # MINNA_DEPLOY_KEY and CLAUDE_CODE_OAUTH_TOKEN
```

Then, on the next PR:

- `Tests`, `Android`, `Vulnerabilities`, `PR policy`, `Public text` and `LGTM` (pending)
  should all report, on a `fix/` branch as well as a `feature/` one.
- Leave a review or comment whose first line is `**<Name> LGTM**`. The status should turn
  green and the merge box should stop listing `LGTM` as expected.
- Any PR opened before this change has to be updated from `main` once so that it picks up
  the new checks.

## Rollback

```sh
# Remove the ruleset entirely: back to no protection, as before FOX-169.
id=$(gh api repos/7kfpun/SwiftUI-Japanese/rulesets --jq '.[] | select(.name == "main") | .id')
gh api --method DELETE "repos/7kfpun/SwiftUI-Japanese/rulesets/$id"
```

For an emergency without deleting it, keep the ruleset but stop enforcing it:

```sh
id=$(gh api repos/7kfpun/SwiftUI-Japanese/rulesets --jq '.[] | select(.name == "main") | .id')
gh api "repos/7kfpun/SwiftUI-Japanese/rulesets/$id" \
  | jq '{name, target, enforcement: "disabled", conditions, bypass_actors, rules}' \
  | gh api --method PUT "repos/7kfpun/SwiftUI-Japanese/rulesets/$id" --input -
# Set "enforcement" back to "active" with the same PUT afterwards.
```

## Adding a required check later

A required check must report on every PR, drafts included, or it blocks the merge. Add the
job with no `paths` filter, merge it, let one PR run it, and only then add its `context` to
the ruleset (a PR runs the workflows of its merge with `main`, so before the merge no other
PR would report it):

```sh
id=$(gh api repos/7kfpun/SwiftUI-Japanese/rulesets --jq '.[] | select(.name == "main") | .id')
gh api "repos/7kfpun/SwiftUI-Japanese/rulesets/$id" > ruleset.before.json   # keep for rollback
jq --arg c "New check" '{name, target, enforcement, conditions, bypass_actors, rules: [.rules[]
      | if .type == "required_status_checks"
        then .parameters.required_status_checks |=
          (map(select(.context != $c)) + [{"context": $c, "integration_id": 15368}])
        else . end]}' ruleset.before.json \
  | gh api --method PUT "repos/7kfpun/SwiftUI-Japanese/rulesets/$id" --input -
```
