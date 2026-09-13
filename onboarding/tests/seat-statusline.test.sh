#!/usr/bin/env bash
#
# Both-directions test for seat-statusline.sh (#76 AC4 re-delivery).
#
# The defect it guards: the script printed `context_window.used_percentage`
# — a percentage of the model's context window — instead of a token count.
# The story's own AC asks for "context tokens", and the autoCompactWindow
# threshold this same story configures is a raw token number (default
# 250000): a percentage of the window doesn't tell a seat how close it is
# to that point. QA (Tess) caught this on #5241/claude-agentic-sdlc#80
# because setup-seat-settings.test.sh only checked that `statusLine` POINTS
# at this script (never runs it) — this suite closes that gap by actually
# executing the script against a real Claude Code 2.1.270 statusline
# payload, committed as a fixture (field names verified against the
# installed 2.1.270 binary itself, not assumed from docs).
#
# Usage: seat-statusline.test.sh <path-to-seat-statusline.sh> [path-to-fixture]
set -uo pipefail

SCRIPT="${1:-}"
[ -n "$SCRIPT" ] || { echo "usage: $0 <path-to-seat-statusline.sh> [path-to-fixture]" >&2; exit 1; }
case "$SCRIPT" in /*) ;; *) SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")" ;; esac
[ -f "$SCRIPT" ] || { echo "no such script: $SCRIPT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required to run this test" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="${2:-"$HERE/fixtures/statusline-payload-2.1.270.json"}"
[ -f "$FIXTURE" ] || { echo "no such fixture: $FIXTURE" >&2; exit 1; }

fails=0
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }

INPUT_TOKENS="$(jq -r '.context_window.total_input_tokens' "$FIXTURE")"
COST="$(jq -r '.cost.total_cost_usd' "$FIXTURE")"

# 1. The real Claude Code 2.1.270 payload -> the output names the actual
# context TOKEN count (not just a derived percentage) and the cost.
OUT="$(jq -c . "$FIXTURE" | bash "$SCRIPT" 2>/dev/null)"
case "$OUT" in
  *"$INPUT_TOKENS"*) ok "output contains the context token count ($INPUT_TOKENS)" ;;
  *) bad "output '$OUT' is missing the context token count ($INPUT_TOKENS) — a percentage alone does not satisfy this" ;;
esac
case "$OUT" in
  *"${COST}"*) ok "output contains the raw cost value" ;;
  *"1.23"*) ok "output contains the cost, rounded to cents" ;;
  *) bad "output '$OUT' is missing the session cost ($COST)" ;;
esac

# 2. A payload missing context_window/cost entirely degrades to "?"
# placeholders and exits 0 — never a crash on a field a future Claude Code
# build renamed or hasn't shipped yet.
OUT2="$(printf '{}' | bash "$SCRIPT" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -n "$OUT2" ]; then
  ok "an empty payload still exits 0 with non-empty output (no crash)"
else
  bad "an empty payload should exit 0 with SOME output, got rc=$rc out='$OUT2'"
fi

# 3. Malformed (non-JSON) stdin: same — never a crash, never a non-zero exit
# that would blank the whole statusline for an unrelated reason.
OUT3="$(printf 'not json' | bash "$SCRIPT" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -n "$OUT3" ]; then
  ok "malformed stdin still exits 0 with non-empty output (no crash)"
else
  bad "malformed stdin should exit 0 with SOME output, got rc=$rc out='$OUT3'"
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "seat-statusline: all checks passed"
else
  echo "seat-statusline: $fails check(s) FAILED" >&2
fi
exit "$fails"
