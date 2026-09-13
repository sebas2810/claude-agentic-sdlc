#!/usr/bin/env bash
#
# seat-statusline.sh — Claude Code `statusLine` command: context TOKENS
# (not just a percentage) + session cost, wired by setup-seat.sh (#76 AC4)
# so a seat always sees how close it is to the autoCompactWindow token
# threshold this same story sets, without running /context by hand.
#
# QA (Tess) FAILed the first version of this script on #5241/claude-
# agentic-sdlc#80: it printed `.context_window.used_percentage` — a
# percentage of the MODEL's context window, not a token count against the
# compaction threshold this story actually configures (autoCompactWindow,
# a raw token number). Verified against the installed Claude Code 2.1.270
# binary (`strings` on the CLI, function `WPt`): the statusline payload's
# `context_window` object carries `total_input_tokens`, `total_output_
# tokens`, `context_window_size` and `current_usage` alongside `used_
# percentage` / `remaining_percentage` — the token counts were available
# the whole time, this script just never read them. Fixed to show the
# input-token count against the window size (what's actually comparable to
# autoCompactWindow), with the percentage kept alongside for the same
# number in a more familiar shape.
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
TOKENS="$(printf '%s' "$INPUT" | jq -r '.context_window.total_input_tokens // empty' 2>/dev/null)"
WINDOW="$(printf '%s' "$INPUT" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)"
PCT="$(printf '%s' "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)"
COST="$(printf '%s' "$INPUT" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)"

# Two-decimal cost via printf rather than trusting jq's own float
# formatting — falls back to the raw string if it isn't numeric.
if [ -n "$COST" ]; then
  COST="$(printf '%.2f' "$COST" 2>/dev/null || printf '%s' "$COST")"
fi

if [ -n "$TOKENS" ] && [ -n "$WINDOW" ]; then
  CTX="${TOKENS}/${WINDOW} tok"
  [ -n "$PCT" ] && CTX="${CTX} (${PCT}%)"
elif [ -n "$TOKENS" ]; then
  CTX="${TOKENS} tok"
else
  CTX="?"
fi

printf '%s · ctx %s · $%s\n' "${MODEL:-?}" "$CTX" "${COST:-?}"
