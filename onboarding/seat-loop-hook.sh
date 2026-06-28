#!/usr/bin/env bash
#
# seat-loop-hook.sh — the standing-seat re-engagement hook (a Claude Code Stop hook).
#
# EVENT-DRIVEN model (feedback/architecture/event-driven-orchestration.md — owner mandate 2026-06-28):
# the board PUSHES; seats do NOT poll. After every turn Claude Code runs this hook:
#
#   • SCRUM-MASTER  — the SINGLE board reader (one GraphQL consumer). Its hook re-engages it while
#                     work is mid-pipeline; it DISPATCHES by writing producer/Quality inboxes.
#   • engineer / any producer, quality-engineer — read their LOCAL INBOX ($0 filesystem, never the
#                     board). Inbox item present → block + hand it over (and consume it); inbox empty
#                     → exit 0 (clean idle). A drained seat is re-woken by the SM/dispatch writing its
#                     inbox, or by /recheck — NOT by polling.
#   • pm / orchestrator — do NOT run this hook (AUTONOMOUS=0; they self-drive their own runner).
#
# This kills the N-way board poll that exhausted the shared GitHub rate budget: N seats × gh project
# item-list (heavy GraphQL) → one SM reader + N free inbox reads.
#
# Safety: honours .paused (the kill-switch) and stop_hook_active (Claude also force-stops after 8
# consecutive blocks); ANY tooling error → exit 0 (allow stop) rather than wedge the pane forever.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT="$(cat 2>/dev/null || true)"

# 1) infinite-loop guard — if we already forced a continuation, let it stop.
if [ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ]; then
  exit 0
fi

# 2) require the seat role; missing → don't block (clean stop).
[ -n "${SEAT_ROLE:-}" ] || exit 0

# 3) the global kill-switch — `/pause` (inbox.sh pause) → every seat idles cleanly.
INBOX_ROOT="${SAMMY_INBOX_ROOT:-$HOME/.agentic-sdlc/${INSTANCE:-seat}/inbox}"
[ -f "$INBOX_ROOT/.paused" ] && exit 0

block() { jq -cn --arg r "$1" '{decision:"block", reason:$r}'; }

# ── SCRUM-MASTER: the one board reader ───────────────────────────────────────────────────────────
if [ "$SEAT_ROLE" = "scrum-master" ]; then
  [ -n "${BOARD_ID:-}" ] && [ -n "${BOARD_OWNER:-}" ] || exit 0
  # control-char-safe read (LC_ALL=C strips raw control bytes; multi-byte UTF-8 survives).
  ITEMS="$(gh project item-list "$BOARD_ID" --owner "$BOARD_OWNER" --format json --limit 300 2>/dev/null \
            | LC_ALL=C tr -d '\000-\010\013\014\016-\037')" || exit 0
  [ -z "$ITEMS" ] && exit 0
  NEXT="$(printf '%s' "$ITEMS" | jq -r 'first(.items[] | select(.status=="Scoped" or .status=="In Progress" or .status=="Delivered" or .status=="Tested" or .status=="Merged")) | .content.number // empty' 2>/dev/null)"
  if [ -n "$NEXT" ]; then
    block "Orchestrate per your orchestrator-runner — you are the ONLY board reader. Enforce WIP first, then PUSH work to seats (never make them poll): dispatch each PM-approved Scoped item by writing the owning producer's inbox — \`bash $HERE/inbox.sh push --key <seat> --item <n> --action claim+build --ac '#<n> ## Steer' --epic <e> --by sm\` (seat key = its seat:<x> label suffix) and set Status->In Progress. Ensure each Delivered item reaches Quality — \`bash $HERE/inbox.sh push --key quality-engineer --item <n> --action verify --ac '#<n>'\`. Drive Merged->deploy/canary->Released; route the back-edges (deploy-fail->fix-story, QA-fail->producer); sweep aging/Blocked; surface idle seats for relaunch (a stopped pane can't self-wake). Surface Tested-ready + the 3 consult-exceptions to the PM. You do NOT merge, adjudicate, or write product code. Stop when only Released/Blocked/PM-pending Backlog remain."
  fi
  exit 0
fi

# ── NON-SM seats: read the LOCAL INBOX, never the board ──────────────────────────────────────────
# seat key: a producer's seat:<x> label suffix, else the role (pm, quality-engineer).
KEY="${SEAT_KEY:-}"
if [ -z "$KEY" ]; then
  case "${SEAT_LABEL:-}" in seat:*) KEY="${SEAT_LABEL#seat:}" ;; *) KEY="$SEAT_ROLE" ;; esac
fi

ITEM_JSON="$(bash "$HERE/inbox.sh" peek --key "$KEY" 2>/dev/null)" || exit 0
[ -z "$ITEM_JSON" ] && exit 0   # inbox empty → clean idle (the event-driven rest state)

N="$(printf '%s' "$ITEM_JSON" | jq -r '.item // empty' 2>/dev/null)"
AC="$(printf '%s' "$ITEM_JSON" | jq -r '.ac_ref // empty' 2>/dev/null)"
[ -n "$N" ] || exit 0

# consume on hand-over; recovery for a crashed build is the SM board-reconcile (In Progress + no PR), not the inbox.
bash "$HERE/inbox.sh" pop --key "$KEY" --item "$N" >/dev/null 2>&1 || true

if [ "$SEAT_ROLE" = "quality-engineer" ]; then
  ACT="VERIFY item #$N against its pre-committed AC (${AC:-see the issue}) on the DEPLOYED env — perturb the happy path (gate reliability, not one lucky output). Post a falsifiable per-criterion PASS/FAIL; on PASS set Status->Tested, on FAIL set Status->In Progress (so it leaves your queue). You NEVER merge. No false-green — assert the feature's CONTENT, not just disposition."
else
  ACT="CLAIM #$N first: flip Status Scoped->In Progress + assign yourself BEFORE building (the atomic claim — even if the item was queued twice, only the first claim wins). Then build per your KICKOFF + the steer/AC (${AC:-see the issue}): branch off origin/main, gates + a real deployed round-trip, ONE PR with '## Closes #$N', post the ready-signal, flip Status->Delivered. NEVER self-merge — the PM adjudicates."
fi

block "Inbox: work for you — item #$N. $ACT  This item is now consumed from your inbox; when you finish, the hook checks your inbox again — empty → you idle until the SM/dispatch (or /recheck) wakes you. On a 3rd repeat of the same item, set it Blocked + post '## Consult-exception' (the dead-letter)."
exit 0
