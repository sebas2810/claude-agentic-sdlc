#!/usr/bin/env python3
"""seat-tokens.py: per-seat token spend from local Claude Code transcripts.

Usage:
  seat-tokens.py START END OUT --match PATTERN [--projects-dir DIR]
                 [--seat-map FROM=TO ...] [--label-prefix status:]

START and END are ISO-8601 dates or datetimes, read as UTC. END is exclusive.
OUT is where the JSON report is written; a table goes to stdout.

Transcripts: every **/*.jsonl under each folder of --projects-dir (default
~/.claude/projects) whose name matches --match. A match without * ? or [ is a
substring test; with them it is a glob on the whole folder name. The seat is
the part of the folder name after the match, dashes trimmed ("main" when
nothing follows). --seat-map FROM=TO renames a seat and may merge several.
Files under a subagents/ directory count toward their seat and are reported
as its subagent share.

Counting:
  A call is one assistant message id. Claude Code writes a message once per
  content block and streams its output count, so the same id repeats with
  growing numbers: each usage field takes its largest value across the lines
  (and files) that carry that id. The call is dated by its first line.
  Input-equivalent tokens weight each call's usage:
    input 1, cache write 5-minute 1.25, cache write 1-hour 2,
    cache read 0.1, output 5.
  Context of a call = input + cache writes + cache read.
  A cold re-cache is a call writing at least 100k tokens to cache.
  A status-label write is a Bash tool call whose command adds or removes a
  label starting with --label-prefix (gh issue/pr edit --add-label or
  --remove-label, or gh api writing to a labels endpoint), counted once per
  tool call id.

Exit codes:
  0  report written
  2  an input could not be read: the projects dir, a folder or a transcript is
     unreadable, no folder matches, or an argument is invalid
  3  transcripts were read but hold no assistant usage in the window
No report file is written on a non-zero exit.
"""
import argparse
import collections
import datetime as dt
import fnmatch
import json
import os
import re
import sys
from urllib.parse import quote

WEIGHTS = {"input": 1.0, "cache_write_5m": 1.25, "cache_write_1h": 2.0, "cache_read": 0.1, "output": 5.0}
LARGE_CONTEXT = 200_000
COLD_RECACHE = 100_000
GLOB_CHARS = set("*?[")
EXIT_UNREADABLE = 2
EXIT_NOTHING = 3
SEGMENT = re.compile(r"\n|&&|\|\||;|\|")

LIMITS = [
    "Input-equivalent tokens are relative units for comparing seats, not a price.",
    "Transcript files last modified before START are not opened.",
    "Label writes are seen only when made through a Bash tool call running gh; "
    "a write made any other way is not counted.",
]


def die(message, code=EXIT_UNREADABLE):
    print(f"seat-tokens.py: error: {message}", file=sys.stderr)
    sys.exit(code)


def parse_when(text):
    value = text.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        moment = dt.datetime.fromisoformat(value)
    except ValueError:
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=dt.timezone.utc)
    return moment.astimezone(dt.timezone.utc)


def match_regex(match):
    """The --match pattern without its outer stars, as a regex to find where it ends."""
    core, parts, i = match.strip("*"), [], 0
    while i < len(core):
        char = core[i]
        if char == "*":
            parts.append(".*?")
        elif char == "?":
            parts.append(".")
        elif char == "[" and "]" in core[i + 1:]:
            close = core.index("]", i + 1)
            body = core[i + 1:close]
            parts.append("[" + ("^" + body[1:] if body.startswith("!") else body) + "]")
            i = close
        else:
            parts.append(re.escape(char))
        i += 1
    return re.compile("".join(parts))


def is_label_write(command, prefix):
    encoded = quote(prefix, safe="")
    add_remove = re.compile(r"--(?:add|remove)-label(?:=|\s)+['\"]?[^\s'\"]*" + re.escape(prefix))
    for segment in SEGMENT.split(command):
        if prefix not in segment and encoded not in segment:
            continue
        if add_remove.search(segment):
            return True
        if re.search(r"\bgh\s+api\b", segment) and "/labels" in segment:
            method = re.search(r"(?:-X|--method)[=\s]*['\"]?([A-Za-z]+)", segment)
            if method:
                if method.group(1).upper() != "GET":
                    return True
            elif re.search(r"\s(?:-f|-F|--field|--raw-field|--input)\b", segment):
                return True
    return False


def count(value):
    return value if isinstance(value, (int, float)) and value > 0 else 0


def token_fields(usage):
    written = count(usage.get("cache_creation_input_tokens"))
    breakdown = usage.get("cache_creation") if isinstance(usage.get("cache_creation"), dict) else {}
    one_hour = count(breakdown.get("ephemeral_1h_input_tokens"))
    five_min = breakdown.get("ephemeral_5m_input_tokens")
    five_min = count(five_min) if five_min is not None else max(written - one_hour, 0)
    return (count(usage.get("input_tokens")), five_min, one_hour,
            count(usage.get("cache_read_input_tokens")), count(usage.get("output_tokens")))


def transcripts(folder):
    def unreadable(err):
        die(f"cannot read directory {err.filename}: {err.strerror}")
    found = []
    for dirpath, dirnames, filenames in os.walk(folder, onerror=unreadable):
        dirnames.sort()
        found.extend(os.path.join(dirpath, name) for name in filenames if name.endswith(".jsonl"))
    return sorted(found)


def main():
    parser = argparse.ArgumentParser(description="Per-seat token spend from Claude Code transcripts.")
    parser.add_argument("start", help="window start, ISO-8601, UTC")
    parser.add_argument("end", help="window end (exclusive), ISO-8601, UTC")
    parser.add_argument("out", help="path of the JSON report to write")
    parser.add_argument("--projects-dir", default="~/.claude/projects")
    parser.add_argument("--match", required=True,
                        help="substring or glob selecting this instance's project folders")
    parser.add_argument("--seat-map", action="append", default=[], metavar="FROM=TO",
                        help="rename a derived seat (repeatable)")
    parser.add_argument("--label-prefix", default="status:")
    args = parser.parse_args()

    start, end = parse_when(args.start), parse_when(args.end)
    if start is None or end is None:
        die("START and END must be ISO-8601 dates or datetimes")
    if end <= start:
        die("END must be later than START")
    seat_map = {}
    for entry in args.seat_map:
        source, _, target = entry.partition("=")
        if not source or not target:
            die(f"--seat-map {entry!r} is not FROM=TO")
        seat_map[source] = target

    root = os.path.expanduser(args.projects_dir)
    if not os.path.isdir(root):
        die(f"--projects-dir {root} is not a directory")
    try:
        names = sorted(e.name for e in os.scandir(root) if e.is_dir())
    except OSError as exc:
        die(f"cannot list --projects-dir {root}: {exc.strerror}")
    rx = match_regex(args.match)
    glob_match = bool(GLOB_CHARS & set(args.match))
    folders = [n for n in names if (fnmatch.fnmatchcase(n, args.match) if glob_match else args.match in n)]
    if not folders:
        die(f"no folder under {root} matches --match {args.match!r}")

    messages = {}  # message id -> {"seat", "subagent", "at", "tokens"}
    writes = {}    # tool call id -> (seat, at)
    bad_lines = collections.Counter()
    scan = collections.Counter()
    start_ts = start.timestamp()
    for folder in folders:
        hit = rx.search(folder)
        derived = (folder[hit.end():] if hit else folder).strip("-") or "main"
        seat = seat_map.get(derived, derived)
        base = os.path.join(root, folder)
        for path in transcripts(base):
            try:
                modified = os.stat(path).st_mtime
            except OSError as exc:
                die(f"cannot stat transcript {path}: {exc.strerror}")
            scan["transcript_files"] += 1
            if modified < start_ts:
                scan["files_older_than_start"] += 1
                continue
            subagent = "subagents" in os.path.relpath(path, base).split(os.sep)[:-1]
            try:
                with open(path, encoding="utf-8", errors="replace") as handle:
                    for lineno, line in enumerate(handle, 1):
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            record = json.loads(line)
                        except json.JSONDecodeError:
                            bad_lines[seat] += 1
                            continue
                        if not isinstance(record, dict) or record.get("type") != "assistant":
                            continue
                        message = record.get("message")
                        if not isinstance(message, dict):
                            continue
                        at = parse_when(record["timestamp"]) if isinstance(record.get("timestamp"), str) else None
                        if at is None:
                            bad_lines[seat] += 1
                            continue
                        content = message.get("content")
                        for index, block in enumerate(content if isinstance(content, list) else []):
                            if not (isinstance(block, dict) and block.get("type") == "tool_use"
                                    and block.get("name") == "Bash"):
                                continue
                            command = (block.get("input") or {}).get("command")
                            if isinstance(command, str) and is_label_write(command, args.label_prefix):
                                writes.setdefault(block.get("id") or f"{path}:{lineno}:{index}", (seat, at))
                        usage, message_id = message.get("usage"), message.get("id")
                        if not isinstance(usage, dict) or not message_id:
                            continue
                        scan["usage_lines"] += 1
                        tokens = token_fields(usage)
                        seen = messages.get(message_id)
                        if seen is None:
                            messages[message_id] = {"seat": seat, "subagent": subagent, "at": at, "tokens": tokens}
                        else:
                            scan["repeated_usage_lines"] += 1
                            seen["tokens"] = tuple(max(a, b) for a, b in zip(seen["tokens"], tokens))
            except OSError as exc:
                die(f"cannot read transcript {path}: {exc.strerror}")
    if scan["transcript_files"] == 0:
        die(f"the {len(folders)} folder(s) matching --match {args.match!r} hold no .jsonl transcripts")

    seats = collections.defaultdict(lambda: {"calls": 0, "weq": 0.0, "context": 0, "large_weq": 0.0,
                                             "large_calls": 0, "cold": 0, "subagent_weq": 0.0,
                                             "days": set(), "writes": 0})
    for call in messages.values():
        if not start <= call["at"] < end:
            continue
        inp, five_min, one_hour, read, out = call["tokens"]
        weq = (WEIGHTS["input"] * inp + WEIGHTS["cache_write_5m"] * five_min
               + WEIGHTS["cache_write_1h"] * one_hour + WEIGHTS["cache_read"] * read + WEIGHTS["output"] * out)
        context = inp + five_min + one_hour + read
        s = seats[call["seat"]]
        s["calls"] += 1
        s["weq"] += weq
        s["context"] += context
        s["days"].add(call["at"].date())
        if call["subagent"]:
            s["subagent_weq"] += weq
        if context > LARGE_CONTEXT:
            s["large_weq"] += weq
            s["large_calls"] += 1
        if five_min + one_hour >= COLD_RECACHE:
            s["cold"] += 1
    for seat, at in writes.values():
        if start <= at < end and seat in seats:
            seats[seat]["writes"] += 1

    if not seats:
        die(f"{scan['transcript_files']} transcript file(s) in {len(folders)} folder(s) hold no assistant "
            f"usage between {args.start} and {args.end}; nothing to report", EXIT_NOTHING)

    def pct(part, whole):
        return round(100 * part / whole, 1) if whole else 0.0

    report_seats = {}
    for seat, s in sorted(seats.items(), key=lambda kv: -kv[1]["weq"]):
        days = len(s["days"])
        report_seats[seat] = {
            "calls": s["calls"],
            "active_days": days,
            "input_equivalent_tokens": round(s["weq"], 1),
            "per_active_day": round(s["weq"] / days, 1),
            "label_writes": s["writes"],
            "per_label_write": round(s["weq"] / s["writes"], 1) if s["writes"] else None,
            "avg_context_tokens": round(s["context"] / s["calls"]),
            "calls_over_200k_context": s["large_calls"],
            "share_of_spend_over_200k_context_pct": pct(s["large_weq"], s["weq"]),
            "cold_recaches": s["cold"],
            "subagent_share_pct": pct(s["subagent_weq"], s["weq"]),
            "bad_lines": bad_lines[seat],
        }
    report = {
        "window": {"start": start.isoformat(), "end": end.isoformat()},
        "match": args.match,
        "seat_map": seat_map,
        "weights": WEIGHTS,
        "thresholds": {"large_context_tokens": LARGE_CONTEXT, "cold_recache_tokens": COLD_RECACHE},
        "totals": {
            "input_equivalent_tokens": round(sum(s["weq"] for s in seats.values()), 1),
            "calls": sum(s["calls"] for s in seats.values()),
            "label_writes": sum(s["writes"] for s in seats.values()),
        },
        "scan": {"folders": len(folders), **{k: scan[k] for k in
                 ("transcript_files", "files_older_than_start", "usage_lines", "repeated_usage_lines")},
                 "bad_lines": sum(bad_lines.values())},
        "seats": report_seats,
        "limits": LIMITS,
    }
    try:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=1)
            handle.write("\n")
    except OSError as exc:
        die(f"could not write {args.out}: {exc.strerror}")

    print(f"{'seat':<14}{'calls':>7}{'days':>6}{'M tok':>9}{'M/day':>8}{'writes':>8}{'M/write':>9}"
          f"{'ctx k':>7}{'>200k%':>8}{'cold':>6}{'sub%':>6}")
    for seat, r in report_seats.items():
        per_write = "n/a" if r["per_label_write"] is None else f"{r['per_label_write'] / 1e6:.2f}"
        print(f"{seat:<14}{r['calls']:>7}{r['active_days']:>6}{r['input_equivalent_tokens'] / 1e6:>9.1f}"
              f"{r['per_active_day'] / 1e6:>8.1f}{r['label_writes']:>8}{per_write:>9}"
              f"{r['avg_context_tokens'] / 1000:>7.0f}{r['share_of_spend_over_200k_context_pct']:>8.1f}"
              f"{r['cold_recaches']:>6}{r['subagent_share_pct']:>6.1f}")
    print(f"total {report['totals']['input_equivalent_tokens'] / 1e6:.1f}M input-equivalent tokens, "
          f"{report['totals']['calls']} calls, {report['totals']['label_writes']} label writes")


if __name__ == "__main__":
    main()
