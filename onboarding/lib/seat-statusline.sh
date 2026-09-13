#!/usr/bin/env bash
#
# seat-statusline.sh — Claude Code `statusLine` command: context-window
# usage + session cost, wired by setup-seat.sh (#76 AC4) so a seat always
# sees how close it is to compacting without running /context by hand.
#
# Claude Code invokes this command with the current session's status as a
# JSON object on stdin and prints stdout verbatim below the prompt. Every
# field below is read with a `// ` fallback: a field a given Claude Code
# build hasn't shipped (or has renamed) must degrade to a "?" placeholder,
# never a crash that blanks the whole statusline for an unrelated reason.
#
# Usage (wired automatically): "statusLine": {"type": "command",
#   "command": "bash <path-to-this-file>"}
set -uo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq not found\n'
  exit 0
fi

MODEL="$(printf '%s' "$INPUT" | jq -r '.model.display_name // .model.id // empty' 2>/dev/null)"
PCT="$(printf '%s' "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)"
COST="$(printf '%s' "$INPUT" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)"

# Two-decimal cost via printf rather than trusting jq's own float
# formatting — falls back to the raw string if it isn't numeric.
if [ -n "$COST" ]; then
  COST="$(printf '%.2f' "$COST" 2>/dev/null || printf '%s' "$COST")"
fi

printf '%s · ctx %s%% · $%s\n' "${MODEL:-?}" "${PCT:-?}" "${COST:-?}"
