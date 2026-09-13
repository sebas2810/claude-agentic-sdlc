#!/usr/bin/env python3
"""flow.py: stage times, throughput and returns from status label history.

Usage:
  flow.py START END OUT --repo OWNER/NAME [--author LOGIN ...]
          [--label-prefix status:] [--fail-pattern REGEX] [--pass-pattern REGEX]
          [--verdict-window-hours 12] [--verdict-grace-minutes 10]

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
  returns        status:delivered followed later by status:scoped. A verdict is
                 read from each comment's heading (its first non-empty line). Each
                 return is matched to the verdict comment nearest in time within
                 [returned_at - window, returned_at + grace], and a verdict serves
                 at most one return, so a verdict posted seconds after the label
                 change is found and a stale one is never reused. Classes:
                   verification_failure  the matched verdict is FAIL, even when
                                         the item had reached status:tested or
                                         status:merged
                   after_pass            the matched verdict is PASS, or no verdict
                                         was matched but the item reached
                                         status:tested or status:merged after its
                                         last status:delivered
                   unclassified          no matched verdict and no such label
                 The automatic pass cannot tell a slice return from a routing
                 after a pass (an unmergeable PR, say): a person decides each
                 after_pass return with rows 1 and 2 of returns.md, and each
                 unclassified return with its whole table.

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
    "on a linked PR, earlier than the verdict window, later than the grace after the "
    "return, or nearer in time to another return of the same item, is not matched: "
    "the return is unclassified unless a tested or merged label shows a pass.",
    "A return after a pass (after_pass) is not split automatically: the script cannot "
    "tell a slice return from a routing after a pass, such as an unmergeable PR. A "
    "person decides each after_pass return with rows 1 and 2 of returns.md, and each "
    "unclassified one with the whole table. A matched FAIL verdict makes a return a "
    "verification_failure even after a tested or merged label, so a failure found "
    "after a merge is not counted as a return after a pass.",
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
    """(time, state) for each status label added, in time order. Adds in the same
    second keep the order the events listing gave them."""
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
    adds.sort(key=lambda add: add[0])
    return adds


def read_verdicts(comments, fail_rx, pass_rx, number):
    """(time, "FAIL" or "PASS") for each comment whose heading carries a verdict."""
    verdicts = []
    for comment in comments:
        if not isinstance(comment, dict) or not comment.get("created_at"):
            die(f"item #{number}: a comment has no created_at")
        at = parse_when(comment["created_at"], f"item #{number} comment")
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
        verdicts.append((at, "FAIL" if is_fail else "PASS"))
    return verdicts


def classify_returns(returns, comments, window, grace, fail_rx, pass_rx, number):
    """Class each return of one item: a list of (returned_at, pass_label), where
    pass_label is "tested" or "merged" when that label was added after the last
    status:delivered and before the return, else None.

    Each return is matched to the verdict nearest in time within
    [returned_at - window, returned_at + grace]. Pairs are taken nearest first and
    a verdict serves at most one return, so the next return on the item cannot
    reuse it. Returns (class, verdict_at, verdict) per return, in input order."""
    verdicts = read_verdicts(comments, fail_rx, pass_rx, number)
    pairs = []
    for r, (returned_at, _) in enumerate(returns):
        for v, (at, _) in enumerate(verdicts):
            if returned_at - window <= at <= returned_at + grace:
                # Nearest first; on a tie, a verdict at or before the return first.
                pairs.append((abs((at - returned_at).total_seconds()), at > returned_at, r, v))
    matched = {}
    used = set()
    for _, _, r, v in sorted(pairs):
        if r not in matched and v not in used:
            matched[r] = v
            used.add(v)
    classes = []
    for r, (_, pass_label) in enumerate(returns):
        verdict_at, verdict = verdicts[matched[r]] if r in matched else (None, None)
        if verdict == "FAIL":
            kind = "verification_failure"
        elif verdict == "PASS" or pass_label:
            kind = "after_pass"
        else:
            kind = "unclassified"
        classes.append((kind, verdict_at, verdict))
    return classes


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
    parser.add_argument("--verdict-window-hours", type=float, default=12.0,
                        help="how long before a return a verdict can be posted and still be matched to it")
    parser.add_argument("--verdict-grace-minutes", type=float, default=10.0,
                        help="how long after a return a verdict can be posted and still be matched to it")
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
    if args.verdict_window_hours < 0 or args.verdict_grace_minutes < 0:
        die("--verdict-window-hours and --verdict-grace-minutes cannot be negative")
    window = dt.timedelta(hours=args.verdict_window_hours)
    grace = dt.timedelta(minutes=args.verdict_grace_minutes)

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
    returns_of = {}
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
        # Every return of the item is matched to verdicts, including those outside
        # the window, so a verdict that belongs to one of them is not taken by a
        # return inside it. Only returns inside the window are reported.
        after_delivered, pass_label, item_returns = False, None, []
        for at, state in adds:
            if state == "delivered":
                after_delivered, pass_label = True, None
            elif state in ("tested", "merged") and after_delivered:
                pass_label = state
            elif state == "scoped" and after_delivered:
                item_returns.append((at, pass_label))
                after_delivered, pass_label = False, None
        if any(start <= at < end for at, _ in item_returns):
            returns_of[number] = item_returns
            returns.extend((number, at) for at, _ in item_returns if start <= at < end)

    if considered == 0:
        who = f" opened by {', '.join(args.author)}" if args.author else ""
        die(f"no issue or PR in {args.repo}{who} had a {args.label_prefix} label added "
            f"between {iso(start)} and {iso(end)}; nothing to report", EXIT_NOTHING)

    counts = {"after_pass": 0, "verification_failure": 0, "unclassified": 0}
    events = []
    for number, item_returns in returns_of.items():
        comments = gh_pages(f"repos/{args.repo}/issues/{number}/comments")
        classes = classify_returns(item_returns, comments, window, grace, fail_rx, pass_rx, number)
        for (at, pass_label), (kind, verdict_at, verdict) in zip(item_returns, classes):
            if not start <= at < end:
                continue
            counts[kind] += 1
            events.append({"item": number, "returned_at": iso(at), "class": kind,
                           "verdict_at": iso(verdict_at) if verdict_at else None,
                           "verdict": verdict, "pass_label": pass_label})

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
            "verdict_grace_minutes": args.verdict_grace_minutes,
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
    print(f"  returns {len(returns)}: after a pass {counts['after_pass']} (slice or routing, "
          f"for a person to decide), verification {counts['verification_failure']}, "
          f"unclassified {counts['unclassified']}")
    for limit in LIMITS:
        print(f"  limit: {limit}")


if __name__ == "__main__":
    main()
