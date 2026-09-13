#!/usr/bin/env python3
"""Fixture test for flow.py: a fake `gh` on PATH serves canned REST pages.

Run: python3 operations/metrics/tests/test_flow.py

Known answer, window 2026-01-10 .. 2026-01-20 (10 days), authors alice and bob:
  #1 clean pass           scoped 0h, in-progress +2, delivered +4, tested +1, merged +1
  #2 FAIL return          its status events sit on page 2 of the events listing
  #3 after-pass return    an earlier FAIL in the window loses to the nearer PASS
  #4 unclassified return  its only FAIL verdict is 13h before the return
  #5 started before the window; only its in-window stages count
  #6 mallory              excluded author, carries a FAIL return that must not count
  #7 label events only before the window: not considered
  #8 return lands after END: not counted

Known answer for ReturnMatching, window 2026-02-01 .. 2026-02-02, author alice:
  #21 delivered, tested, scoped after a PASS; a routing comment carries the reason: after_pass
  #22 delivered, tested, merged, scoped with no verdict on the thread: after_pass
  #23 FAIL verdict posted 2 seconds after the scoped label: matched
  #24 two returns, each verdict posted seconds after its label: each takes its own
  #25 a return before the window took its verdict; the return inside has none: unclassified
  #26 FAIL verdict 11 minutes after the return: outside the default 10-minute grace
  #27 PASS, merged, then a post-merge FAIL 3 seconds after the scoped label: verification_failure
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "flow.py"
REPO = "example/widgets"

STUB = r'''#!{python}
import json, os, re, sys
from urllib.parse import urlsplit, parse_qs
args = sys.argv[1:]
if os.environ.get("FAKE_GH_LOG"):
    with open(os.environ["FAKE_GH_LOG"], "a") as fh:
        fh.write(" ".join(args) + "\n")
if len(args) != 4 or args[:3] != ["api", "-X", "GET"]:
    print("fake gh: unexpected call: " + " ".join(args), file=sys.stderr)
    sys.exit(99)
if os.environ.get("FAKE_GH_FAIL") and os.environ["FAKE_GH_FAIL"] in args[3]:
    print("gh: HTTP 502: Bad Gateway", file=sys.stderr)
    sys.exit(1)
if os.environ.get("FAKE_GH_GARBAGE") and os.environ["FAKE_GH_GARBAGE"] in args[3]:
    print("<html>upstream timeout</html>")
    sys.exit(0)
data = json.load(open(os.environ["FAKE_GH_DATA"]))
url = urlsplit(args[3])
query = parse_qs(url.query)
m = re.fullmatch(r"repos/([^/]+/[^/]+)/issues(?:/(\d+)/(events|comments))?", url.path)
if not m or m.group(1) != data["repo"]:
    print("gh: HTTP 404: Not Found (" + url.path + ")", file=sys.stderr)
    sys.exit(1)
if m.group(2) is None:
    rows = data["issues"]
    if "creator" in query:
        rows = [r for r in rows if r["user"]["login"] == query["creator"][0]]
else:
    rows = data[m.group(3)].get(m.group(2), [])
per_page = int(query.get("per_page", ["30"])[0])
page = int(query.get("page", ["1"])[0])
print(json.dumps(rows[(page - 1) * per_page: page * per_page]))
'''


def lab(name, at, event="labeled"):
    return {"event": event, "label": {"name": name}, "created_at": at}


def com(body, at):
    return {"body": body, "created_at": at}


def fixture():
    issues = [{"number": n, "user": {"login": who}} for n, who in
              [(1, "alice"), (2, "bob"), (3, "alice"), (4, "bob"), (5, "alice"),
               (6, "mallory"), (7, "alice"), (8, "bob")]]
    filler = [{"event": "subscribed", "created_at": "2026-01-11T00:00:00Z"}] * 150
    events = {
        "1": [lab("status:scoped", "2026-01-10T00:00:00Z"),
              lab("type:feature", "2026-01-10T00:30:00Z"),
              lab("status:scoped", "2026-01-10T02:00:00Z", event="unlabeled"),
              lab("status:in-progress", "2026-01-10T02:00:00Z"),
              lab("status:delivered", "2026-01-10T06:00:00Z"),
              lab("status:tested", "2026-01-10T07:00:00Z"),
              lab("status:merged", "2026-01-10T08:00:00Z")],
        "2": filler + [
              lab("status:scoped", "2026-01-11T00:00:00Z"),
              lab("status:in-progress", "2026-01-11T04:00:00Z"),
              lab("status:delivered", "2026-01-11T10:00:00Z"),
              lab("status:scoped", "2026-01-11T13:00:00Z"),
              lab("status:in-progress", "2026-01-11T14:00:00Z"),
              lab("status:delivered", "2026-01-11T16:00:00Z"),
              lab("status:tested", "2026-01-11T19:00:00Z"),
              lab("status:merged", "2026-01-11T21:00:00Z")],
        "3": [lab("status:scoped", "2026-01-12T00:00:00Z"),
              lab("status:in-progress", "2026-01-12T01:00:00Z"),
              lab("status:delivered", "2026-01-12T03:00:00Z"),
              lab("status:scoped", "2026-01-12T06:00:00Z")],
        "4": [lab("status:scoped", "2026-01-13T00:00:00Z"),
              lab("status:in-progress", "2026-01-13T05:00:00Z"),
              lab("status:delivered", "2026-01-13T08:00:00Z"),
              lab("status:scoped", "2026-01-13T12:00:00Z")],
        "5": [lab("status:scoped", "2026-01-08T00:00:00Z"),
              lab("status:in-progress", "2026-01-09T00:00:00Z"),
              lab("status:delivered", "2026-01-10T12:00:00Z"),
              lab("status:tested", "2026-01-10T14:00:00Z"),
              lab("status:merged", "2026-01-10T17:00:00Z")],
        "6": [lab("status:scoped", "2026-01-14T00:00:00Z"),
              lab("status:delivered", "2026-01-14T02:00:00Z"),
              lab("status:scoped", "2026-01-14T03:00:00Z")],
        "7": [lab("status:scoped", "2026-01-05T00:00:00Z"),
              lab("status:merged", "2026-01-05T09:00:00Z")],
        "8": [lab("status:scoped", "2026-01-19T00:00:00Z"),
              lab("status:in-progress", "2026-01-19T10:00:00Z"),
              lab("status:delivered", "2026-01-19T20:00:00Z"),
              lab("status:scoped", "2026-01-20T02:00:00Z")],
    }
    comments = {
        "2": [com("Picked up.", "2026-01-11T03:00:00Z"),
              com("## QA verification: FAIL\n\n- AC2 not met", "2026-01-11T12:00:00Z"),
              com("QA verification: PASS", "2026-01-11T18:30:00Z")],
        "3": [com("QA verification: FAIL on AC1", "2026-01-12T02:00:00Z"),
              com("QA verification: PASS\nSlice 1 of 2 verified.", "2026-01-12T05:00:00Z")],
        "4": [com("QA verification: FAIL\nAC3 not met", "2026-01-12T23:00:00Z"),
              com("Rebased onto main, please re-check.", "2026-01-13T09:00:00Z")],
        "6": [com("QA verification: FAIL", "2026-01-14T02:30:00Z")],
        "8": [com("QA verification: FAIL", "2026-01-20T01:00:00Z")],
    }
    return {"repo": REPO, "issues": issues, "events": events, "comments": comments}


class StubbedGh(unittest.TestCase):
    """A fake gh on PATH serving self.data(); run_flow runs flow.py against it."""
    data = staticmethod(fixture)
    authors = ("alice", "bob")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        stub = self.bin / "gh"
        stub.write_text(STUB.replace("{python}", sys.executable))
        stub.chmod(0o755)
        (self.dir / "data.json").write_text(json.dumps(self.data()))
        self.out = self.dir / "flow.json"
        self.log = self.dir / "gh.log"

    def tearDown(self):
        self.tmp.cleanup()

    def run_flow(self, start="2026-01-10", end="2026-01-20", path=None, args=(), **extra_env):
        env = dict(os.environ, PATH=path if path is not None else f"{self.bin}{os.pathsep}{os.environ.get('PATH', '')}",
                   FAKE_GH_DATA=str(self.dir / "data.json"), FAKE_GH_LOG=str(self.log), **extra_env)
        authors = [flag for who in self.authors for flag in ("--author", who)]
        return subprocess.run(
            [sys.executable, str(SCRIPT), start, end, str(self.out), "--repo", REPO, *authors, *args],
            capture_output=True, text=True, env=env)


class FlowReport(StubbedGh):

    def test_known_answer(self):
        proc = self.run_flow()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        report = json.loads(self.out.read_text())
        self.assertEqual(report["items_considered"], 6)
        self.assertEqual(report["median_hours"], {
            "scoped->in-progress": 4.0, "in-progress->delivered": 5.0,
            "delivered->tested": 2.0, "tested->merged": 2.0, "scoped->merged": 21.0})
        self.assertEqual(report["samples"], {
            "scoped->in-progress": 5, "in-progress->delivered": 6,
            "delivered->tested": 3, "tested->merged": 3, "scoped->merged": 3})
        self.assertEqual(report["transitions"], {
            "delivered": 7, "in-progress": 6, "merged": 3, "scoped": 8, "tested": 3})
        self.assertEqual(report["throughput_per_day"], {
            "delivered": 0.7, "in-progress": 0.6, "merged": 0.3, "scoped": 0.8, "tested": 0.3})
        returns = report["returns"]
        self.assertEqual((returns["total"], returns["after_pass"], returns["verification_failure"],
                          returns["unclassified"]), (3, 1, 1, 1))
        self.assertEqual(returns["per_delivery_pct"], 42.9)
        self.assertEqual([(e["item"], e["class"]) for e in returns["events"]],
                         [(2, "verification_failure"), (3, "after_pass"), (4, "unclassified")])
        self.assertTrue(any("first time each label was added" in limit for limit in report["limits"]))
        self.assertIn("first time each label was added", proc.stdout)
        calls = self.log.read_text()
        self.assertIn(f"repos/{REPO}/issues/2/events?per_page=100&page=2", calls)
        self.assertNotIn("--paginate", calls)

    def test_failed_gh_call_exits_nonzero_and_names_it(self):
        proc = self.run_flow(FAKE_GH_FAIL="issues/3/events")
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertIn("issues/3/events", proc.stderr)
        self.assertIn("502", proc.stderr)
        self.assertFalse(self.out.exists(), "a report was written despite the failed call")

    def test_non_json_answer_exits_nonzero(self):
        proc = self.run_flow(FAKE_GH_GARBAGE="issues/2/comments")
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertIn("issues/2/comments", proc.stderr)
        self.assertIn("not JSON", proc.stderr)
        self.assertFalse(self.out.exists())

    def test_missing_gh_exits_nonzero(self):
        empty = self.dir / "empty-path"
        empty.mkdir()
        proc = self.run_flow(path=str(empty))
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertIn("could not run `gh api", proc.stderr)
        self.assertFalse(self.out.exists())

    def test_window_without_label_events_is_not_an_empty_report(self):
        proc = self.run_flow(start="2025-01-01", end="2025-02-01")
        self.assertEqual(proc.returncode, 3, proc.stdout)
        self.assertIn("nothing to report", proc.stderr)
        self.assertFalse(self.out.exists())


def matching_fixture():
    issues = [{"number": n, "user": {"login": "alice"}} for n in range(21, 28)]
    events = {
        "21": [lab("status:scoped", "2026-02-01T00:00:00Z"),
               lab("status:in-progress", "2026-02-01T01:00:00Z"),
               lab("status:delivered", "2026-02-01T03:00:00Z"),
               lab("status:tested", "2026-02-01T04:00:00Z"),
               lab("status:scoped", "2026-02-01T06:00:00Z")],
        "22": [lab("status:scoped", "2026-02-01T00:00:00Z"),
               lab("status:delivered", "2026-02-01T02:00:00Z"),
               lab("status:tested", "2026-02-01T03:00:00Z"),
               lab("status:merged", "2026-02-01T04:00:00Z"),
               lab("status:scoped", "2026-02-01T05:00:00Z")],
        "23": [lab("status:scoped", "2026-02-01T08:00:00Z"),
               lab("status:in-progress", "2026-02-01T09:00:00Z"),
               lab("status:delivered", "2026-02-01T10:00:00Z"),
               lab("status:scoped", "2026-02-01T11:00:00Z")],
        "24": [lab("status:scoped", "2026-02-01T12:00:00Z"),
               lab("status:in-progress", "2026-02-01T12:30:00Z"),
               lab("status:delivered", "2026-02-01T13:00:00Z"),
               lab("status:scoped", "2026-02-01T14:00:00Z"),
               lab("status:in-progress", "2026-02-01T15:00:00Z"),
               lab("status:delivered", "2026-02-01T16:00:00Z"),
               lab("status:scoped", "2026-02-01T17:00:00Z")],
        "25": [lab("status:scoped", "2026-01-31T20:00:00Z"),
               lab("status:delivered", "2026-01-31T22:00:00Z"),
               lab("status:scoped", "2026-01-31T23:00:00Z"),
               lab("status:in-progress", "2026-02-01T00:00:00Z"),
               lab("status:delivered", "2026-02-01T01:00:00Z"),
               lab("status:scoped", "2026-02-01T02:00:00Z")],
        "26": [lab("status:scoped", "2026-02-01T18:00:00Z"),
               lab("status:delivered", "2026-02-01T19:00:00Z"),
               lab("status:scoped", "2026-02-01T20:00:00Z")],
        "27": [lab("status:scoped", "2026-02-01T21:00:00Z"),
               lab("status:delivered", "2026-02-01T21:10:00Z"),
               lab("status:tested", "2026-02-01T21:20:00Z"),
               lab("status:merged", "2026-02-01T21:30:00Z"),
               lab("status:scoped", "2026-02-01T22:00:00Z")],
    }
    comments = {
        "21": [com("## QA verification: #21 / PR #90: **PASS**", "2026-02-01T04:00:05Z"),
               com("PR #90 is CONFLICTING, not merged. Back to Scoped.", "2026-02-01T05:59:50Z")],
        "23": [com("## QA verification: #23 / PR #91: **FAIL**\n\n- AC2 not met", "2026-02-01T11:00:02Z")],
        "24": [com("## QA verification: #24 / PR #92: **FAIL**", "2026-02-01T14:00:03Z"),
               com("## QA re-verification: #24 / PR #92: **FAIL on AC3**", "2026-02-01T17:00:04Z")],
        "25": [com("## QA verification: #25: **FAIL**", "2026-01-31T23:00:02Z")],
        "26": [com("## QA verification: #26: **FAIL**", "2026-02-01T20:11:00Z")],
        "27": [com("## QA verification: #27 / PR #93: **PASS**", "2026-02-01T21:20:02Z"),
               com("## QA verdict on AC4 (post-merge gate): #27 / PR #93, **FAIL.**", "2026-02-01T22:00:03Z")],
    }
    return {"repo": REPO, "issues": issues, "events": events, "comments": comments}


class ReturnMatching(StubbedGh):
    """Returns after a pass get their own class; verdicts posted just after the label are matched."""
    data = staticmethod(matching_fixture)
    authors = ("alice",)

    def report(self, *args):
        proc = self.run_flow("2026-02-01", "2026-02-02", args=args)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return json.loads(self.out.read_text())["returns"]

    def events(self, returns, item):
        return [(e["returned_at"], e["class"], e["verdict_at"]) for e in returns["events"] if e["item"] == item]

    def test_a_return_after_a_pass_is_after_pass_not_a_slice_return(self):
        returns = self.report()
        self.assertEqual(self.events(returns, 21), [("2026-02-01T06:00:00Z", "after_pass", "2026-02-01T04:00:05Z")])
        self.assertEqual(self.events(returns, 22), [("2026-02-01T05:00:00Z", "after_pass", None)])
        self.assertEqual([(e["verdict"], e["pass_label"]) for e in returns["events"] if e["item"] in (21, 22)],
                         [("PASS", "tested"), (None, "merged")])
        self.assertNotIn("slice_return", returns)

    def test_a_verdict_posted_just_after_the_label_is_matched(self):
        returns = self.report()
        self.assertEqual(self.events(returns, 23),
                         [("2026-02-01T11:00:00Z", "verification_failure", "2026-02-01T11:00:02Z")])

    def test_a_second_return_takes_the_verdict_posted_just_after_it(self):
        returns = self.report()
        self.assertEqual(self.events(returns, 24),
                         [("2026-02-01T14:00:00Z", "verification_failure", "2026-02-01T14:00:03Z"),
                          ("2026-02-01T17:00:00Z", "verification_failure", "2026-02-01T17:00:04Z")])

    def test_a_fail_after_a_merge_is_a_verification_failure(self):
        returns = self.report()
        self.assertEqual(self.events(returns, 27),
                         [("2026-02-01T22:00:00Z", "verification_failure", "2026-02-01T22:00:03Z")])
        self.assertEqual([(e["verdict"], e["pass_label"]) for e in returns["events"] if e["item"] == 27],
                         [("FAIL", "merged")])

    def test_the_verdict_of_a_return_before_the_window_is_not_reused(self):
        returns = self.report()
        self.assertEqual(self.events(returns, 25), [("2026-02-01T02:00:00Z", "unclassified", None)])

    def test_counts_and_grace(self):
        returns = self.report()
        self.assertEqual((returns["total"], returns["after_pass"], returns["verification_failure"],
                          returns["unclassified"]), (8, 2, 4, 2))
        self.assertEqual(self.events(returns, 26), [("2026-02-01T20:00:00Z", "unclassified", None)])
        method = json.loads(self.out.read_text())["method"]
        self.assertEqual(method["verdict_grace_minutes"], 10.0)
        wider = self.report("--verdict-grace-minutes", "15")
        self.assertEqual(self.events(wider, 26),
                         [("2026-02-01T20:00:00Z", "verification_failure", "2026-02-01T20:11:00Z")])


class VerdictHeadings(unittest.TestCase):
    """classify_returns() reads a comment's heading, in the wordings verdicts are written in."""

    @classmethod
    def setUpClass(cls):
        import importlib.util
        spec = importlib.util.spec_from_file_location("flow_under_test", SCRIPT)
        cls.flow = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.flow)

    def verdict(self, *bodies):
        import datetime as dt
        import re
        returned = dt.datetime(2026, 1, 12, 12, 0, tzinfo=dt.timezone.utc)
        comments = [{"created_at": f"2026-01-12T{8 + i:02d}:00:00Z", "body": body}
                    for i, body in enumerate(bodies)]
        [(kind, _, _)] = self.flow.classify_returns(
            [(returned, None)], comments, dt.timedelta(hours=12), dt.timedelta(minutes=10),
            re.compile(self.flow.DEFAULT_FAIL), re.compile(self.flow.DEFAULT_PASS), 12)
        return kind

    def test_verdict_heading_wordings(self):
        cases = [
            ("## QA verdict: #12 / PR #34 @ `abc1234`, **FAIL on AC3, narrowly.** AC1 and AC2 PASS.", "verification_failure"),
            ("## QA verdict: #12 / PR #35 @ `def5678`, **PASS on the slice.** AC2 stays open.", "after_pass"),
            ("## QA verdict on AC4 (post-merge gate): #12, **FAIL.**", "verification_failure"),
            ("## QA re-verification: #12, **PASS**. The earlier FAIL is resolved.", "after_pass"),
            ("## QA verification: #12 / PR #36: **FAIL**", "verification_failure"),
        ]
        for body, expected in cases:
            with self.subTest(body=body):
                self.assertEqual(self.verdict(body), expected)

    def test_a_verdict_below_the_heading_is_not_read(self):
        self.assertEqual(self.verdict("## Unit landed: AC4 rework\n\nLocal gates PASS"), "unclassified")
        self.assertEqual(self.verdict("## Notes\n\nQA verification: FAIL"), "unclassified")

    def test_the_latest_verdict_wins(self):
        self.assertEqual(self.verdict("## QA verdict: #12, **FAIL on AC1.**",
                                      "## QA verdict: #12, **PASS on AC1.**"), "after_pass")


if __name__ == "__main__":
    unittest.main(verbosity=2)
