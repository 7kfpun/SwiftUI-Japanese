"""Tests for ci_test_level.py: python3 -m unittest discover -s tools -p 'test_ci_test_level.py'"""

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
import ci_test_level as lvl  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def level(*files, labels=(), api_error=False):
    return lvl.decide(list(files), list(labels), api_error=api_error).level


class Classify(unittest.TestCase):
    def test_docs_only_skips(self):
        self.assertEqual(level("context/README.md", "CLAUDE.md", "docs/ci-cd-guardrails.md"), lvl.SKIP)

    def test_android_only_skips(self):
        self.assertEqual(
            level("android/app/src/main/kotlin/com/kfpun/japanesedaily/Foo.kt", "android/README.md"),
            lvl.SKIP,
        )

    def test_web_fastlane_and_screenshots_skip(self):
        self.assertEqual(level("web/index.html", "web-jlpt/en.html", "fastlane/Fastfile", "screenshots/a.png"), lvl.SKIP)
        self.assertEqual(level("scripts/build-web.py", "scripts/build-android-strings.py"), lvl.SKIP)

    def test_workflows_other_than_ios_ci_skip(self):
        self.assertEqual(level(".github/workflows/android.yml", ".github/workflows/lgtm.yml"), lvl.SKIP)

    def test_ios_ci_workflow_and_build_action_run_the_tests(self):
        self.assertEqual(level(".github/workflows/ci.yml"), lvl.TEST)
        self.assertEqual(level(".github/actions/unit-tests-build/action.yml"), lvl.TEST)
        self.assertEqual(level("tools/ci_test_level.py"), lvl.TEST)

    def test_app_sources_and_data_run_the_tests(self):
        for path in (
            "nihongo/Store.swift",
            "nihongo/UIStrings.json",
            "nihongo/Resources/audio/vocab/a.m4a",
            "nihongo/Resources/MinnaData.json",
            "nihongo/Assets.xcassets/x/icon.png",
            "nihongoTests/nihongoTests.swift",
            "Apps/jlpt/Resources/JLPTData.json",
            "nihongo.xcodeproj/project.pbxproj",
            "WatchApp/ContentView.swift",
            "minna",
            "scripts/build-minna-data.py",
            "ci_scripts/ci_post_clone.sh",
        ):
            self.assertEqual(level(path), lvl.TEST, path)

    def test_dependency_pins_run_the_tests(self):
        self.assertEqual(level("nihongo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"), lvl.TEST)
        self.assertEqual(level("Gemfile.lock"), lvl.TEST)

    def test_unknown_top_level_path_fails_safe(self):
        self.assertEqual(level("brand-new-folder/file.txt"), lvl.TEST)

    def test_highest_level_wins(self):
        self.assertEqual(level("docs/a.md", "android/x.kt", "nihongo/Store.swift"), lvl.TEST)

    def test_case_insensitive(self):
        self.assertEqual(level("Android/App/Foo.kt"), lvl.SKIP)


class Doubt(unittest.TestCase):
    def test_label_forces_tests(self):
        self.assertEqual(level("docs/a.md", labels=["ci-full-tests"]), lvl.TEST)

    def test_empty_list_runs_tests(self):
        self.assertEqual(level(), lvl.TEST)

    def test_api_error_runs_tests(self):
        self.assertEqual(level("docs/a.md", api_error=True), lvl.TEST)

    def test_decision_names_the_deciding_files(self):
        decision = lvl.decide(["docs/a.md", "nihongo/Store.swift"])
        self.assertEqual(decision.files, ["nihongo/Store.swift"])


class Repository(unittest.TestCase):
    def test_skip_rules_match_the_repository(self):
        self.assertEqual(lvl.check(ROOT), [])


if __name__ == "__main__":
    unittest.main()
