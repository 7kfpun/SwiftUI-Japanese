#!/usr/bin/env python3
"""Check a pull request to main (or an integration branch) against the repository's PR rules.

    REPO=owner/name PR=123 python3 tools/pr_policy.py

Fails when:
  - the head branch does not start with a known type prefix (feature/, fix/,
    chore/, docs/, ci/, refactor/, test/, perf/). CI and review now run for every
    head branch, so this is naming hygiene, not a way to skip checks;
  - neither the branch nor the title names a Linear ticket (FOX-nn);
  - the body says the PR is stacked ("Depends on #N", "Stacked on #N",
    "Merge after #N") and any PR named there is not merged yet.

Needs `gh` with a token that can read pull requests.
"""

import json
import os
import re
import subprocess
import sys

BRANCH_PREFIXES = ("feature/", "fix/", "chore/", "docs/", "ci/", "refactor/", "test/", "perf/")
TICKET = re.compile(r"\bFOX-\d+\b", re.I)
DEPENDENCY_LINE = re.compile(r"^[\s>*_-]*(depends on|stacked on|merge after)\b(.*)$", re.I | re.M)


def gh(endpoint):
    result = subprocess.run(["gh", "api", endpoint], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def dependencies(body):
    numbers = []
    for match in DEPENDENCY_LINE.finditer(body or ""):
        for number in re.findall(r"#(\d+)", match.group(2)):
            if number not in numbers:
                numbers.append(number)
    return numbers


def check(pull, lookup):
    errors, notes = [], []
    head_ref, title, body = pull["head"]["ref"], pull.get("title") or "", pull.get("body") or ""
    if not head_ref.startswith(BRANCH_PREFIXES):
        errors.append(f"Head branch '{head_ref}' must start with one of: {', '.join(BRANCH_PREFIXES)}.")
    if not (TICKET.search(head_ref) or TICKET.search(title) or TICKET.search(body)):
        errors.append("Name the Linear ticket (FOX-nn) in the branch name, the PR title or the PR body.")
    for number in dependencies(body):
        other = lookup(number)
        if other is None:
            errors.append(f"Body says this PR depends on #{number}, which is not a pull request here.")
        elif not other.get("merged_at"):
            errors.append(f"Merge #{number} first: this PR is stacked on it (it is {other.get('state')}, not merged).")
        else:
            notes.append(f"#{number} is merged.")
    return errors, notes


def main():
    repo, number = os.environ["REPO"], os.environ["PR"]
    pull = gh(f"repos/{repo}/pulls/{number}")
    if pull is None:
        print(f"::error::Could not read pull request #{number}.")
        return 1
    errors, notes = check(pull, lambda n: gh(f"repos/{repo}/pulls/{n}"))
    for note in notes:
        print(note)
    if errors:
        for message in errors:
            print(f"::error::{message}" if os.environ.get("GITHUB_ACTIONS") else f"error: {message}")
        return 1
    print(f"#{number} '{pull['head']['ref']}' follows the PR rules.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
