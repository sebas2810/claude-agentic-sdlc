#!/usr/bin/env bash
#
# seat-loop-hook.sh — the autonomous standing-seat board-loop (a Claude Code Stop hook).
#
# Inverts control: after every turn Claude Code runs this hook. If the Execution board still
# has work for THIS seat, it returns {"decision":"block","reason":...} to block the stop and
# hand the seat its next item — so the seat self-loops the board, deterministically, in the
# *interactive* (watchable) pane (not "the model remembering to loop"). Board drained for this
# seat → exit 0 (clean, idle stop). Wired by seat-launch.sh; generic across instances.
#
# Config — exported by seat-launch.sh (sourced from the worktree .env.local):
#   SEAT_ROLE    quality-engineer → watch Status=Delivered; any producer → watch Status=Scoped + SEAT_LABEL
#   SEAT_LABEL   routing label for producer seats (e.g. seat:dex)
#   BOARD_ID     the Execution project number
#   BOARD_OWNER  the project owner login
#   GH_TOKEN     (optional) board-ops token — e.g. a GitHub App installation token (its own quota)
#
# Safety: honours stop_hook_active (Claude Code also force-overrides after 8 consecutive blocks);
# any tooling error → exit 0 (allow stop) rather than block forever; the seat is told to set the
# item Blocked + post a consult-exception on a 3rd repeat (the dead-letter).
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

# 1) infinite-loop guard — if we already forced a continuation, let it stop.
if [ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ]; then
  exit 0
fi

# 2) require the routing config; missing → don't block (clean stop).
[ -n "${BOARD_ID:-}" ] && [ -n "${BOARD_OWNER:-}" ] && [ -n "${SEAT_ROLE:-}" ] || exit 0

# 3) read the board — control-char-safe. Raw control chars in titles/bodies break jq; strip them
#    byte-wise (LC_ALL=C) so multi-byte UTF-8 (em-dashes, arrows) survives intact.
ITEMS="$(gh project item-list "$BOARD_ID" --owner "$BOARD_OWNER" --format json --limit 300 2>/dev/null \
          | LC_ALL=C tr -d '\000-\010\013\014\016-\037')" || exit 0
[ -z "$ITEMS" ] && exit 0

# 4) pick this seat's next item by role.
if [ "$SEAT_ROLE" = "quality-engineer" ]; then
  NEXT="$(printf '%s' "$ITEMS" | jq -r 'first(.items[] | select(.status=="Delivered")) | .content.number // empty' 2>/dev/null)"
  ACT="VERIFY it against its pre-committed AC on the deployed env (perturb the happy path — gate reliability, not one lucky output); post a falsifiable per-criterion PASS/FAIL; on PASS set Status->Tested, on FAIL set Status->In Progress (so it leaves your queue). You never merge. No false-green — a deployed eval must assert the feature's CONTENT, not just disposition."
else
  [ -n "${SEAT_LABEL:-}" ] || exit 0
  NEXT="$(printf '%s' "$ITEMS" | jq -r --arg L "$SEAT_LABEL" 'first(.items[] | select(.status=="Scoped") | select((.labels // []) | index($L))) | .content.number // empty' 2>/dev/null)"
  ACT="First CLAIM it: flip Status Scoped->In Progress and assign yourself BEFORE building (the atomic claim, so nothing double-grabs it). Then read the issue + its steer (the AC) and build it per your seat KICKOFF: branch off origin/main, gates + a real deployed round-trip, ONE PR with '## Closes #n', post the ready-signal, flip Status->Delivered. NEVER self-merge — the PM adjudicates."
fi

# 5) block + hand over, or stop clean when drained.
if [ -n "$NEXT" ]; then
  jq -cn --arg n "$NEXT" --arg a "$ACT" \
    '{decision:"block", reason:("Board-loop: still work for you — item #" + $n + ". " + $a + " When done, this hook hands you the next item automatically. Stop ONLY when your queue is empty, or on a 3rd repeated failure of the same item (post \"## Consult-exception\" and set it Blocked — the dead-letter).")}'
else
  exit 0
fi
