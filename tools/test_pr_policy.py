"""Tests for pr_policy.py: python3 -m unittest discover -s tools -p 'test_pr_policy.py'"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import pr_policy  # noqa: E402


def pull(head="feature/fox-1-x", title="feat: x (FOX-1)", body=""):
    return {"head": {"ref": head}, "title": title, "body": body}


def errors(pr, others=None):
    others = others or {}
    return pr_policy.check(pr, lambda n: others.get(n))[0]


class PrPolicy(unittest.TestCase):
    def test_every_branch_type_passes(self):
        for head in ("feature/fox-1-x", "fix/fox-1-x", "chore/fox-1", "docs/fox-1", "ci/fox-1"):
            self.assertEqual(errors(pull(head=head)), [], head)

    def test_unknown_prefix_fails(self):
        self.assertEqual(len(errors(pull(head="wip/thing"))), 1)

    def test_ticket_in_branch_title_or_body(self):
        self.assertEqual(errors(pull(head="fix/x", title="fix: x", body="Closes FOX-9")), [])
        self.assertEqual(errors(pull(head="fix/fox-9-x", title="fix: x")), [])
        self.assertEqual(len(errors(pull(head="fix/x", title="fix: x"))), 1)

    def test_stacked_pr_waits_for_its_base(self):
        body = "Depends on #5"
        self.assertEqual(len(errors(pull(body=body), {"5": {"state": "open", "merged_at": None}})), 1)
        self.assertEqual(errors(pull(body=body), {"5": {"state": "closed", "merged_at": "2026-11-01"}}), [])
        self.assertEqual(len(errors(pull(body=body))), 1)


if __name__ == "__main__":
    unittest.main()
