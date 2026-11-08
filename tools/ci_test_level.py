#!/usr/bin/env python3
"""Whether a pull request needs the iOS `Tests` job (FOX-169, after TWAQI's FOX-79).

Two levels, decided from the PR's changed files. The highest level wins:

  skip   only paths the iOS unit tests cannot see changed: android/, web/, web-jlpt/,
         fastlane/, screenshots/, context/, docs/, tools/, .claude/, Markdown, and
         .github/ other than the iOS CI workflow and its build action. Nothing is built
         and the check is green.
  test   anything else (Swift, strings, resources and audio, asset catalogs, project
         files, the minna submodule pointer, scripts that feed the bundled data, the
         dependency pins) or the CI workflow itself: build and run `nihongoTests`.

Unlike TWAQI, which runs a subset of its suites, this repo's job always runs the whole
`nihongoTests` target, so there is no "build only" level.

The PR label `ci-full-tests`, an empty file list, or a failed API call give `test`: the
job never skips on doubt. Whatever is not listed as skippable is `test`, so a new
top-level folder fails safe.

Usage:
  ci_test_level.py decide --files FILE [--labels FILE] [--api-error]
  ci_test_level.py check     # every SKIP_PREFIXES entry exists in the repo, so a renamed
                             # folder cannot leave a stale rule behind
Tests: python3 -m unittest discover -s tools -p 'test_ci_test_level.py'
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath

SKIP, TEST = "skip", "test"
RANK = {SKIP: 0, TEST: 1}

FORCE_LABEL = "ci-full-tests"

# Changing how the job runs, or what it builds against, runs the whole job.
ALWAYS_TEST = (
    ".github/workflows/ci.yml",
    ".github/actions/unit-tests-build/**",
    "ci_scripts/**",
    "tools/ci_test_level.py",
    "tools/test_ci_test_level.py",
    "Gemfile.lock",
    "**/Package.resolved",
)

# Scripts that only produce Android, web or store output. The other scripts generate the
# bundled data the iOS tests read, so they are not listed and run the tests.
SKIPPABLE_SCRIPTS = (
    "scripts/build-android-strings.py",
    "scripts/build-web.py",
    "scripts/build-web-jlpt.py",
    "scripts/check-play-listing.py",
    "scripts/extract-track-events.py",
    "scripts/asc_update_subscriptions.rb",
)

# Folders none of the iOS targets read. `.github/` is skippable except ALWAYS_TEST above.
SKIP_PREFIXES = (
    "android/",
    "web/",
    "web-jlpt/",
    "fastlane/",
    "screenshots/",
    "context/",
    "docs/",
    "tools/",
    ".claude/",
    ".github/",
)
DOC_SUFFIXES = {".md", ".markdown"}

# Directories never searched by `check`.
IGNORED_DIRS = {".git", "DerivedData", "node_modules", "build", ".build"}


def normalize(path: str) -> str:
    path = path.strip().replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def glob_regex(pattern: str) -> re.Pattern[str]:
    """`*` and `?` stay inside one path segment; `**/` spans any directories."""
    pattern = normalize(pattern)
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    # Case-insensitive: the Mac file system is, so a case-only rename must still match.
    return re.compile("".join(out) + r"\Z", re.IGNORECASE)


def matches(path: str, patterns) -> bool:
    path = normalize(path)
    return any(glob_regex(pattern).match(path) for pattern in patterns)


def classify(path: str) -> str:
    path = normalize(path)
    if matches(path, ALWAYS_TEST):
        return TEST
    lowered = path.lower()
    if lowered in SKIPPABLE_SCRIPTS or lowered.startswith(SKIP_PREFIXES):
        return SKIP
    if PurePosixPath(lowered).suffix in DOC_SUFFIXES:
        return SKIP
    return TEST


@dataclass
class Decision:
    level: str
    reason: str
    files: list[str] = field(default_factory=list)  # the files that decided it


def decide(files, labels=(), api_error=False) -> Decision:
    files = [normalize(path) for path in files if path.strip()]
    labels = {label.strip() for label in labels if label.strip()}
    if api_error:
        return Decision(TEST, "the pull request's files or labels could not be read")
    if FORCE_LABEL in labels:
        return Decision(TEST, f"the pull request has the {FORCE_LABEL} label")
    if not files:
        return Decision(TEST, "no changed files were listed")
    levels = {path: classify(path) for path in files}
    level = max(levels.values(), key=RANK.__getitem__)
    reason = {
        TEST: "app, data, project or CI files changed",
        SKIP: "only Android, web, fastlane, screenshots, docs, tools, .github or Markdown files changed",
    }[level]
    return Decision(level, reason, [path for path in files if levels[path] == level])


def repo_files(root: Path) -> list[str]:
    found = []
    for directory, subdirs, names in os.walk(root):
        subdirs[:] = [name for name in subdirs if name not in IGNORED_DIRS]
        for name in names:
            found.append(Path(directory, name).relative_to(root).as_posix())
    return found


def check(root: Path) -> list[str]:
    """Problems that would leave a skip rule pointing at nothing; empty when in step."""
    files = repo_files(root)
    problems = []
    for prefix in SKIP_PREFIXES:
        if not any(path.lower().startswith(prefix) for path in files):
            problems.append(f"SKIP_PREFIXES entry matches no file: {prefix}")
    for script in SKIPPABLE_SCRIPTS:
        if script not in files:
            problems.append(f"SKIPPABLE_SCRIPTS entry is not a file: {script}")
    for pattern in ALWAYS_TEST:
        if not any(matches(path, [pattern]) for path in files):
            problems.append(f"ALWAYS_TEST entry matches no file: {pattern}")
    return problems


def read_lines(path: str | None) -> list[str]:
    if not path:
        return []
    return Path(path).read_text().splitlines()


def main(argv=None) -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    commands = parser.add_subparsers(dest="command", required=True)
    decide_cmd = commands.add_parser("decide", help="print the level for a list of changed files")
    decide_cmd.add_argument("--files", required=True, help="file with one changed path per line")
    decide_cmd.add_argument("--labels", help="file with one PR label per line")
    decide_cmd.add_argument("--api-error", action="store_true", help="the file or label list could not be read")
    commands.add_parser("check", help="the skip rules still point at real files")
    args = parser.parse_args(argv)

    if args.command == "check":
        problems = check(root)
        for problem in problems:
            print(f"::error::{problem}")
        if not problems:
            print("The skip rules match the repository.")
        return 1 if problems else 0

    files = [] if args.api_error else read_lines(args.files)
    decision = decide(files, read_lines(args.labels), api_error=args.api_error)
    print(f"Test level: {decision.level} ({decision.reason})")
    if decision.files:
        print("Files that decided it:")
        print("\n".join(f"  {path}" for path in decision.files))
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as handle:
            handle.write(f"level={decision.level}\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(f"**Tests level: `{decision.level}`**: {decision.reason}.\n\n")
            for path in decision.files[:50]:
                handle.write(f"- `{path}`\n")
            if len(decision.files) > 50:
                handle.write(f"- … {len(decision.files) - 50} more\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
