#!/usr/bin/env python3
"""Fixture test for flow.py: a fake `gh` on PATH serves canned REST pages.

Run: python3 operations/metrics/tests/test_flow.py

Known answer, window 2026-01-10 .. 2026-01-20 (10 days), authors alice and bob:
  #1 clean pass           scoped 0h, in-progress +2, delivered +4, tested +1, merged +1
  #2 FAIL return          its status events sit on page 2 of the events listing
  #3 PASS return          an earlier FAIL in the window is overridden by the later PASS
  #4 unclassified return  its only FAIL verdict is 13h before the return
  #5 started before the window; only its in-window stages count
  #6 mallory              excluded author, carries a FAIL return that must not count
  #7 label events only before the window: not considered
  #8 return lands after END: not counted
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


class FlowReport(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        stub = self.bin / "gh"
        stub.write_text(STUB.replace("{python}", sys.executable))
        stub.chmod(0o755)
        (self.dir / "data.json").write_text(json.dumps(fixture()))
        self.out = self.dir / "flow.json"
        self.log = self.dir / "gh.log"

    def tearDown(self):
        self.tmp.cleanup()

    def run_flow(self, start="2026-01-10", end="2026-01-20", path=None, **extra_env):
        env = dict(os.environ, PATH=path if path is not None else f"{self.bin}{os.pathsep}{os.environ.get('PATH', '')}",
                   FAKE_GH_DATA=str(self.dir / "data.json"), FAKE_GH_LOG=str(self.log), **extra_env)
        return subprocess.run(
            [sys.executable, str(SCRIPT), start, end, str(self.out), "--repo", REPO,
             "--author", "alice", "--author", "bob"],
            capture_output=True, text=True, env=env)

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
        self.assertEqual((returns["total"], returns["slice_return"], returns["verification_failure"],
                          returns["unclassified"]), (3, 1, 1, 1))
        self.assertEqual(returns["per_delivery_pct"], 42.9)
        self.assertEqual([(e["item"], e["class"]) for e in returns["events"]],
                         [(2, "verification_failure"), (3, "slice_return"), (4, "unclassified")])
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


class VerdictHeadings(unittest.TestCase):
    """classify() reads a comment's heading, in the wordings verdicts are written in."""

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
        kind, _ = self.flow.classify(comments, returned, dt.timedelta(hours=12),
                                     re.compile(self.flow.DEFAULT_FAIL),
                                     re.compile(self.flow.DEFAULT_PASS), 12)
        return kind

    def test_verdict_heading_wordings(self):
        cases = [
            ("## QA verdict: #12 / PR #34 @ `abc1234`, **FAIL on AC3, narrowly.** AC1 and AC2 PASS.", "verification_failure"),
            ("## QA verdict: #12 / PR #35 @ `def5678`, **PASS on the slice.** AC2 stays open.", "slice_return"),
            ("## QA verdict on AC4 (post-merge gate): #12, **FAIL.**", "verification_failure"),
            ("## QA re-verification: #12, **PASS**. The earlier FAIL is resolved.", "slice_return"),
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
                                      "## QA verdict: #12, **PASS on AC1.**"), "slice_return")


if __name__ == "__main__":
    unittest.main(verbosity=2)
