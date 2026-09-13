#!/usr/bin/env python3
"""flow.py: stage times, throughput and returns from status label history.

Usage:
  flow.py START END OUT --repo OWNER/NAME [--author LOGIN ...]
          [--label-prefix status:] [--fail-pattern REGEX] [--pass-pattern REGEX]
          [--verdict-window-hours 12]

START and END are ISO-8601 dates or datetimes, read as UTC. END is exclusive.
OUT is where the JSON report is written; a short summary goes to stdout.

Everything is read through `gh api` over REST, paginated explicitly with
per_page=100&page=N (never --paginate, whose output breaks under --jq):
  repos/OWNER/NAME/issues               issues and PRs updated since START,
                                        once per --author (all authors if none)
  repos/OWNER/NAME/issues/N/events      label history of each item
  repos/OWNER/NAME/issues/N/comments    verdicts, read only for items with a return

What it reports:
  median_hours   per stage: scoped->in-progress, in-progress->delivered,
                 delivered->tested, tested->merged, scoped->merged. A stage is
                 counted when its later label was first added inside the window.
  transitions    label additions inside the window, per state
  throughput     those additions per day of window
  returns        status:delivered followed later by status:scoped, split by the
                 latest verdict in the hours before the return, read from each
                 comment's heading (its first non-empty line):
                 FAIL -> verification_failure, PASS -> slice_return,
                 neither -> unclassified. See returns.md for the full table.

Exit codes:
  0  report written
  2  an input could not be read: a gh call failed or returned something other
     than the expected JSON, or an argument is invalid
  3  the input was read, but no item had a label added in the window
No report file is written on a non-zero exit.
"""
import argparse
import collections
import datetime as dt
import json
import re
import statistics
import subprocess
import sys
from urllib.parse import urlencode

STAGES = [
    ("scoped", "in-progress"),
    ("in-progress", "delivered"),
    ("delivered", "tested"),
    ("tested", "merged"),
    ("scoped", "merged"),
]
# Matched against a comment's heading, its first non-empty line. Headings seen in
# practice: "QA verification: ... PASS", "QA verdict: ... **FAIL on AC3**",
# "QA verdict on AC4 (post-merge gate): ... FAIL", "QA re-verification: ... PASS".
DEFAULT_FAIL = r"QA (?:re-)?(?:verification|verdict)\b.*\bFAIL\b"
DEFAULT_PASS = r"QA (?:re-)?(?:verification|verdict)\b.*\bPASS\b"
PER_PAGE = 100
MAX_PAGES = 1000
EXIT_UNREADABLE = 2
EXIT_NOTHING = 3

LIMITS = [
    "Stage times use the first time each label was added to an item. An item "
    "that loops (delivered, scoped, delivered again) is timed on its first pass.",
    "Verdicts are read from the item's own issue comments. A verdict posted only "
    "on a linked PR, or earlier than the verdict window, leaves the return unclassified.",
    "A verdict is read from a comment's heading (its first non-empty line); a verdict "
    "stated only further down a comment is not seen.",
    "Items are those returned by the issues listing for the chosen authors; an "
    "item transferred out of the repository is not seen.",
]


def die(message, code=EXIT_UNREADABLE):
    print(f"flow.py: error: {message}", file=sys.stderr)
    sys.exit(code)


def parse_when(text, what):
    value = text.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        moment = dt.datetime.fromisoformat(value)
    except ValueError:
        die(f"{what}: {text!r} is not an ISO-8601 date or datetime")
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=dt.timezone.utc)
    return moment.astimezone(dt.timezone.utc)


def iso(moment):
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def gh_json(path):
    """One REST GET through gh. Any failure stops the run and names the call."""
    try:
        proc = subprocess.run(["gh", "api", "-X", "GET", path], capture_output=True, text=True)
    except OSError as exc:
        die(f"could not run `gh api {path}`: {exc}")
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip()[:500] or "no output"
        die(f"`gh api {path}` exited {proc.returncode}: {detail}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        die(f"`gh api {path}` returned output that is not JSON ({exc})")


def gh_pages(path, **params):
    rows = []
    for page in range(1, MAX_PAGES + 1):
        call = f"{path}?{urlencode({**params, 'per_page': PER_PAGE, 'page': page})}"
        batch = gh_json(call)
        if not isinstance(batch, list):
            die(f"`gh api {call}` returned a JSON {type(batch).__name__}, expected a list")
        rows.extend(batch)
        if len(batch) < PER_PAGE:
            return rows
    die(f"`gh api {path}` was still returning full pages after {MAX_PAGES}; refusing a partial read")


def label_adds(events, prefix, number):
    adds = []
    for event in events:
        if not isinstance(event, dict) or event.get("event") != "labeled":
            continue
        name = (event.get("label") or {}).get("name") or ""
        if not name.startswith(prefix):
            continue
        if not event.get("created_at"):
            die(f"item #{number}: a labeled event for {name} has no created_at")
        adds.append((parse_when(event["created_at"], f"item #{number} event"), name[len(prefix):]))
    adds.sort()
    return adds


def classify(comments, returned_at, window, fail_rx, pass_rx, number):
    verdict, verdict_at = None, None
    for comment in comments:
        if not isinstance(comment, dict) or not comment.get("created_at"):
            die(f"item #{number}: a comment has no created_at")
        at = parse_when(comment["created_at"], f"item #{number} comment")
        if not returned_at - window <= at <= returned_at:
            continue
        heading = next((line for line in (comment.get("body") or "").splitlines() if line.strip()), "")
        is_fail = bool(fail_rx.search(heading))
        is_pass = bool(pass_rx.search(heading))
        if not (is_fail or is_pass):
            continue
        if is_fail and is_pass:
            # Both words on one heading ("FAIL on AC3; AC1 and AC2 PASS"): the word
            # written first is the verdict. Custom patterns without either word
            # keep the documented rule that a heading matching both counts as FAIL.
            fail_word = re.search(r"\bFAIL\b", heading)
            pass_word = re.search(r"\bPASS\b", heading)
            if fail_word and pass_word:
                is_fail = fail_word.start() < pass_word.start()
        if verdict_at is None or at >= verdict_at:
            verdict_at = at
            verdict = "verification_failure" if is_fail else "slice_return"
    return (verdict or "unclassified"), verdict_at


def main():
    parser = argparse.ArgumentParser(
        description="Stage times, throughput and returns from status label history.")
    parser.add_argument("start", help="window start, ISO-8601, UTC")
    parser.add_argument("end", help="window end (exclusive), ISO-8601, UTC")
    parser.add_argument("out", help="path of the JSON report to write")
    parser.add_argument("--repo", required=True, help="OWNER/NAME")
    parser.add_argument("--author", action="append", default=[],
                        help="only items opened by this login (repeatable; default all)")
    parser.add_argument("--label-prefix", default="status:")
    parser.add_argument("--fail-pattern", default=DEFAULT_FAIL,
                        help="regex matched against each comment's heading (first non-empty line); a match is a FAIL verdict")
    parser.add_argument("--pass-pattern", default=DEFAULT_PASS,
                        help="regex matched against each comment's heading (first non-empty line); a match is a PASS verdict")
    parser.add_argument("--verdict-window-hours", type=float, default=12.0)
    args = parser.parse_args()

    start = parse_when(args.start, "START")
    end = parse_when(args.end, "END")
    if end <= start:
        die("END must be later than START")
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repo):
        die(f"--repo {args.repo!r} is not OWNER/NAME")
    try:
        fail_rx = re.compile(args.fail_pattern)
        pass_rx = re.compile(args.pass_pattern)
    except re.error as exc:
        die(f"a verdict pattern is not a valid regex: {exc}")
    window = dt.timedelta(hours=args.verdict_window_hours)

    listed = {}
    for author in args.author or [None]:
        params = {"state": "all", "since": iso(start), "sort": "created", "direction": "asc"}
        if author:
            params["creator"] = author
        for item in gh_pages(f"repos/{args.repo}/issues", **params):
            if not isinstance(item, dict) or not isinstance(item.get("number"), int):
                die(f"`gh api repos/{args.repo}/issues` returned an entry without a number")
            login = (item.get("user") or {}).get("login")
            if args.author and login not in args.author:
                continue
            listed[item["number"]] = item

    stage_hours = {f"{a}->{b}": [] for a, b in STAGES}
    transitions = collections.Counter()
    returns = []
    considered = 0
    for number in sorted(listed):
        adds = label_adds(gh_pages(f"repos/{args.repo}/issues/{number}/events"), args.label_prefix, number)
        inside = [state for at, state in adds if start <= at < end]
        if not inside:
            continue
        considered += 1
        transitions.update(inside)
        first = {}
        for at, state in adds:
            first.setdefault(state, at)
        for a, b in STAGES:
            if a in first and b in first and first[b] >= first[a] and start <= first[b] < end:
                stage_hours[f"{a}->{b}"].append((first[b] - first[a]).total_seconds() / 3600)
        after_delivered = False
        for at, state in adds:
            if state == "delivered":
                after_delivered = True
            elif state == "scoped" and after_delivered:
                after_delivered = False
                if start <= at < end:
                    returns.append((number, at))

    if considered == 0:
        who = f" opened by {', '.join(args.author)}" if args.author else ""
        die(f"no issue or PR in {args.repo}{who} had a {args.label_prefix} label added "
            f"between {iso(start)} and {iso(end)}; nothing to report", EXIT_NOTHING)

    counts = {"slice_return": 0, "verification_failure": 0, "unclassified": 0}
    events = []
    comments_of = {}
    for number, at in returns:
        if number not in comments_of:
            comments_of[number] = gh_pages(f"repos/{args.repo}/issues/{number}/comments")
        kind, verdict_at = classify(comments_of[number], at, window, fail_rx, pass_rx, number)
        counts[kind] += 1
        events.append({"item": number, "returned_at": iso(at), "class": kind,
                       "verdict_at": iso(verdict_at) if verdict_at else None})

    days = (end - start).total_seconds() / 86400
    delivered = transitions["delivered"]
    report = {
        "window": {"start": iso(start), "end": iso(end), "days": round(days, 2)},
        "repo": args.repo,
        "authors": args.author or None,
        "label_prefix": args.label_prefix,
        "items_considered": considered,
        "median_hours": {k: (round(statistics.median(v), 2) if v else None) for k, v in stage_hours.items()},
        "samples": {k: len(v) for k, v in stage_hours.items()},
        "transitions": dict(sorted(transitions.items())),
        "throughput_per_day": {k: round(v / days, 2) for k, v in sorted(transitions.items())},
        "returns": {
            "total": len(returns),
            **counts,
            "per_delivery_pct": round(100 * len(returns) / delivered, 1) if delivered else None,
            "events": events,
        },
        "method": {
            "fail_pattern": args.fail_pattern,
            "pass_pattern": args.pass_pattern,
            "verdict_window_hours": args.verdict_window_hours,
        },
        "limits": LIMITS,
    }
    try:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=1)
            handle.write("\n")
    except OSError as exc:
        die(f"could not write {args.out}: {exc}")

    print(f"{args.repo}  {iso(start)} .. {iso(end)}  items={considered}")
    for stage, value in report["median_hours"].items():
        shown = "n/a" if value is None else f"{value}h"
        print(f"  median {stage:<24} {shown:>9}  (n={report['samples'][stage]})")
    print(f"  merged/day {report['throughput_per_day'].get('merged', 0)}"
          f"  delivered/day {report['throughput_per_day'].get('delivered', 0)}")
    print(f"  returns {len(returns)}: slice {counts['slice_return']}, verification "
          f"{counts['verification_failure']}, unclassified {counts['unclassified']}")
    for limit in LIMITS:
        print(f"  limit: {limit}")


if __name__ == "__main__":
    main()
