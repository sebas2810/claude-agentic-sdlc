#!/usr/bin/env python3
"""Fixture test for seat-tokens.py: a small transcript tree with a known answer.

Run: python3 operations/metrics/tests/test_seat_tokens.py

Window 2026-02-01 .. 2026-02-03, --match acme-app, --seat-map qa=quality.
Input-equivalent = input + 1.25*write5m + 2*write1h + 0.1*read + 5*output.

pm seat (4 calls):
  A  100 + 2*1000 + 0.1*10000 + 5*200            =   4100  context  11100
     three lines: two in the session (output streamed 20 then 200) and a copy
     in the subagent file; counted once, at output 200
  B  50 + 1.25*20000 + 2*100000 + 0.1*90000 + 5*1000 = 239050  context 210050  cold
  C  10 + 1.25*400 + 0.1*250000 + 5*100          =  26010  context 250410
     (no 5m/1h breakdown: the whole cache write is 5-minute)
  F  subagent: 1000 + 5*1000                     =   6000  context   1000
  total 275160, 2 active days, 1 label write, 96.3% of spend above 200k,
  subagent share 2.2%, average context 118140, 1 unparseable line
qa seat, renamed quality (1 call):
  G  1.25*100000 = 125000, cold (exactly 100k), 2 label writes, one read-only
main seat (1 call):
  H  10 + 5*2 = 20, at exactly START, no label writes
Excluded: D after END, E before START, the other-thing folder.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "seat-tokens.py"


def usage(i=0, w5=None, w1=None, cw=0, cr=0, o=0):
    u = {"input_tokens": i, "cache_read_input_tokens": cr, "output_tokens": o}
    if w5 is None and w1 is None:
        u["cache_creation_input_tokens"] = cw
    else:
        u["cache_creation_input_tokens"] = (w5 or 0) + (w1 or 0)
        u["cache_creation"] = {"ephemeral_5m_input_tokens": w5 or 0, "ephemeral_1h_input_tokens": w1 or 0}
    return u


def assistant(mid, at, u, *content):
    return {"type": "assistant", "timestamp": at,
            "message": {"id": mid, "role": "assistant", "usage": u, "content": list(content)}}


def bash(tool_id, command):
    return {"type": "tool_use", "id": tool_id, "name": "Bash", "input": {"command": command}}


def text(value):
    return {"type": "text", "text": value}


A_STREAMED = usage(i=100, w5=0, w1=1000, cr=10000, o=20)
A_FINAL = usage(i=100, w5=0, w1=1000, cr=10000, o=200)
G = usage(w5=100000, w1=0)

TREE = {
    "-home-dev-code-acme-app/s3.jsonl": [
        assistant("msg_H", "2026-02-01T00:00:00.000Z", usage(i=10, o=2), text("hello")),
    ],
    "-home-dev-code-acme-app-pm/s1.jsonl": [
        {"type": "user", "timestamp": "2026-02-01T08:59:00.000Z", "message": {"role": "user", "content": "go"}},
        assistant("msg_A", "2026-02-01T09:00:00.000Z", A_STREAMED, text("claiming")),
        assistant("msg_A", "2026-02-01T09:00:01.000Z", A_FINAL,
                  bash("toolu_1", "gh issue edit 12 --add-label status:in-progress --remove-label status:scoped")),
        "{not json",
        assistant("msg_B", "2026-02-01T10:00:00.000Z", usage(i=50, w5=20000, w1=100000, cr=90000, o=1000),
                  text("reading")),
        assistant("msg_C", "2026-02-02T08:00:00.000Z", usage(i=10, cw=400, cr=250000, o=100),
                  bash("toolu_2", "gh issue list --label status:delivered --json number"),
                  bash("toolu_3", "gh pr edit 9 --add-label type:bug")),
        assistant("msg_D", "2026-02-03T01:00:00.000Z", usage(i=999999),
                  bash("toolu_4", "gh issue edit 3 --add-label status:merged")),
        assistant("msg_E", "2026-01-31T23:59:59.000Z", usage(i=888888), text("too early")),
    ],
    "-home-dev-code-acme-app-pm/s1/subagents/agent-a1.jsonl": [
        assistant("msg_F", "2026-02-02T09:00:00.000Z", usage(i=1000, o=1000), text("subagent work")),
        assistant("msg_A", "2026-02-01T09:00:01.000Z", A_FINAL, text("copied from the parent")),
    ],
    "-home-dev-code-acme-app-qa/s2.jsonl": [
        assistant("msg_G", "2026-02-02T12:00:00.000Z", G,
                  bash("toolu_5", "gh issue edit 7 --remove-label status:delivered --add-label status:tested")),
        assistant("msg_G", "2026-02-02T12:00:01.000Z", G,
                  bash("toolu_6", "gh api -X POST repos/o/r/issues/7/labels -f 'labels[]=status:merged'")),
        assistant("msg_G", "2026-02-02T12:00:02.000Z", G,
                  bash("toolu_7", "gh api repos/o/r/issues/7/labels --jq '.[].name' | grep status:")),
        assistant("msg_G", "2026-02-02T12:00:01.000Z", G,
                  bash("toolu_5", "gh issue edit 7 --remove-label status:delivered --add-label status:tested")),
    ],
    "-home-dev-code-other-thing/s4.jsonl": [
        assistant("msg_I", "2026-02-01T12:00:00.000Z", usage(i=5000000),
                  bash("toolu_8", "gh issue edit 1 --add-label status:scoped")),
    ],
}


class SeatTokens(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = Path(self.tmp.name) / "projects"
        for rel, lines in TREE.items():
            path = self.projects / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("".join((l if isinstance(l, str) else json.dumps(l)) + "\n" for l in lines))
        self.out = Path(self.tmp.name) / "tokens.json"

    def tearDown(self):
        for path in self.projects.rglob("*.jsonl"):
            path.chmod(0o644)
        self.tmp.cleanup()

    def run_report(self, *extra, start="2026-02-01", end="2026-02-03", projects=None, match="acme-app"):
        return subprocess.run(
            [sys.executable, str(SCRIPT), start, end, str(self.out),
             "--projects-dir", str(projects or self.projects), "--match", match, *extra],
            capture_output=True, text=True)

    def test_known_answer(self):
        proc = self.run_report("--seat-map", "qa=quality")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        report = json.loads(self.out.read_text())
        self.assertEqual(report["seats"]["pm"], {
            "calls": 4, "active_days": 2, "input_equivalent_tokens": 275160.0, "per_active_day": 137580.0,
            "label_writes": 1, "per_label_write": 275160.0, "avg_context_tokens": 118140,
            "calls_over_200k_context": 2, "share_of_spend_over_200k_context_pct": 96.3,
            "cold_recaches": 1, "subagent_share_pct": 2.2, "bad_lines": 1})
        self.assertEqual(report["seats"]["quality"], {
            "calls": 1, "active_days": 1, "input_equivalent_tokens": 125000.0, "per_active_day": 125000.0,
            "label_writes": 2, "per_label_write": 62500.0, "avg_context_tokens": 100000,
            "calls_over_200k_context": 0, "share_of_spend_over_200k_context_pct": 0.0,
            "cold_recaches": 1, "subagent_share_pct": 0.0, "bad_lines": 0})
        self.assertEqual(report["seats"]["main"], {
            "calls": 1, "active_days": 1, "input_equivalent_tokens": 20.0, "per_active_day": 20.0,
            "label_writes": 0, "per_label_write": None, "avg_context_tokens": 10,
            "calls_over_200k_context": 0, "share_of_spend_over_200k_context_pct": 0.0,
            "cold_recaches": 0, "subagent_share_pct": 0.0, "bad_lines": 0})
        self.assertEqual(set(report["seats"]), {"pm", "quality", "main"})
        self.assertEqual(report["totals"], {"input_equivalent_tokens": 400180.0, "calls": 6, "label_writes": 3})
        self.assertEqual(report["scan"]["folders"], 3)
        self.assertIn("total 0.4M input-equivalent tokens", proc.stdout)

    def test_glob_match_selects_the_same_folders(self):
        proc = self.run_report("--seat-map", "qa=quality", match="*code-acme-app*")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        report = json.loads(self.out.read_text())
        self.assertEqual(set(report["seats"]), {"pm", "quality", "main"})
        self.assertEqual(report["totals"]["input_equivalent_tokens"], 400180.0)

    def test_missing_projects_dir_exits_nonzero(self):
        proc = self.run_report(projects=Path(self.tmp.name) / "nowhere")
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertIn("nowhere", proc.stderr)
        self.assertFalse(self.out.exists())

    def test_no_matching_folder_exits_nonzero(self):
        proc = self.run_report(match="no-such-app")
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertIn("matches --match", proc.stderr)
        self.assertFalse(self.out.exists())

    @unittest.skipIf(hasattr(os, "geteuid") and os.geteuid() == 0, "root reads a mode-000 file")
    def test_unreadable_transcript_exits_nonzero(self):
        victim = self.projects / "-home-dev-code-acme-app-pm/s1.jsonl"
        victim.chmod(0)
        proc = self.run_report()
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertIn("s1.jsonl", proc.stderr)
        self.assertFalse(self.out.exists())

    def test_window_without_usage_is_not_an_empty_report(self):
        proc = self.run_report(start="2025-01-01", end="2025-01-02")
        self.assertEqual(proc.returncode, 3, proc.stdout)
        self.assertIn("nothing to report", proc.stderr)
        self.assertFalse(self.out.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
