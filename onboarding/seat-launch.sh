#!/usr/bin/env bash
#
# seat-launch.sh — run an operator-driven SDLC seat in THIS terminal.
#
# The runtime behind every generated <seat>.command (and thus every .app). Given a worktree with a
# .env.local (SEAT_ROLE/SEAT_NAME/... — see .env.local.example), it:
#   1. titles the terminal window           ("Engineer - Dex")
#   2. runs setup-seat.sh                    (per-worktree git identity + creds + the seat brief +
#                                             the SessionStart hook that injects it)
#   3. (optional) mints a board-ops token    (own GraphQL quota)
#   4. exports the seat + board env          (so /check and /board resolve)
#   5. launches an interactive `claude`      with a role-aware, operator-driven boot prompt
#
# OPERATOR-DRIVEN (semi-automated) — the HUMAN is the orchestrator. No autonomous self-loop, no
# polling, no events, no inbox. Each seat is an interactive, watchable pane that stays INERT until the
# operator engages it; then it PULLS its next workload from the board with /check (role-aware), does
# that one item, reports, and idles. The operator conducts the cadence (watch /board → run /check in
# the seat that should advance). Generic across instances; SEAT_ROLE is the enforced type.
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK="$(cd "$HERE/.." && pwd)"

WORKTREE="" ; TOKEN_CMD=""
while [ $# -gt 0 ]; do case "$1" in
  --worktree)  WORKTREE="$2"; shift 2 ;;
  --token-cmd) TOKEN_CMD="$2"; shift 2 ;;   # e.g. "bash ~/sammy/gh-app-token.sh" → board-ops own quota
  *) echo "seat-launch: unknown arg: $1" >&2; exit 1 ;;
esac; done
[ -n "$WORKTREE" ] && [ -f "$WORKTREE/.env.local" ] || {
  echo "seat-launch: need --worktree <path-with-.env.local>" >&2; exit 1; }

# seat config (also re-sourced by setup-seat.sh; we read what we need here too)
set -a; . "$WORKTREE/.env.local"; set +a
: "${SEAT_ROLE:?.env.local needs SEAT_ROLE}" "${SEAT_NAME:?.env.local needs SEAT_NAME}"
INSTANCE="${INSTANCE:-seat}"
TITLE="${SEAT_TITLE:-$(printf '%s' "$SEAT_ROLE" | awk '{print toupper(substr($0,1,1)) substr($0,2)}') - ${SEAT_NAME}}"

# 1) window title (and stop claude overriding it)
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
printf '\033]0;%s\007' "$TITLE"
cd "$WORKTREE"

# 2) identity + creds + seat brief + SessionStart hook (idempotent). Point setup-seat.sh at THIS
#    framework checkout so it resolves the role template wherever the framework is vendored.
export SDLC_FRAMEWORK_DIR="$FRAMEWORK"
# shellcheck disable=SC1091
source "$FRAMEWORK/onboarding/setup-seat.sh" || true

# 3) board-ops token (own quota) — optional; --token-cmd or BOARD_TOKEN_CMD in .env.local
TOKEN_CMD="${TOKEN_CMD:-${BOARD_TOKEN_CMD:-}}"
if [ -n "$TOKEN_CMD" ]; then
  if T="$($TOKEN_CMD 2>/dev/null)" && [ -n "$T" ]; then export GH_TOKEN="$T"; fi
fi

# 4) seat + board env (every pane) so the /check and /board slash-commands resolve.
#    seat key = a producer's seat:<x> label suffix, else the role.
case "${SEAT_LABEL:-}" in seat:*) SEAT_KEY="${SEAT_LABEL#seat:}" ;; *) SEAT_KEY="$SEAT_ROLE" ;; esac
export SEAT_ROLE SEAT_NAME INSTANCE SEAT_KEY SEAT_LABEL="${SEAT_LABEL:-}" \
       BOARD_ID="${BOARD_ID:-}" BOARD_OWNER="${BOARD_OWNER:-}"

# 4b) Strip any legacy autonomous Stop-hook — the self-loop is removed (operator-driven now). A seat
#     relaunched from an old autonomous session would otherwise keep its wired board-loop.
if [ -f .claude/settings.local.json ] && command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp)"
  if jq 'del(.hooks.Stop)' .claude/settings.local.json > "$tmp" 2>/dev/null; then mv "$tmp" .claude/settings.local.json; else rm -f "$tmp"; fi
fi

# 4c) provision the operator slash-commands (machine-global) from the framework — so /check · /board
#     · /workload work in every pane of every project that vendors this framework. Idempotent copy;
#     instance-agnostic (board id/owner come from this seat's env, exported above).
if [ -d "$FRAMEWORK/commands" ]; then
  mkdir -p "$HOME/.claude/commands"
  cp -f "$FRAMEWORK/commands/"*.md "$HOME/.claude/commands/" 2>/dev/null || true
fi

# 5) boot prompt — role-aware, operator-driven. The full brief comes from the injected seat file.
case "$SEAT_ROLE" in
  pm|orchestrator)
    read -r -d '' PROMPT <<EOP || true
You are ${SEAT_NAME}, the PM seat for ${INSTANCE} — the human's interface + prep + adjudication. The OWNER is the orchestrator (operator-driven, semi-automated): NO autonomous loop, no polling, no events — you act only when engaged. Confirm your seat + boot your read-order, then: git fetch origin main, then idle. When the owner runs /check here (or says go): pull your next workload — adjudicate the next \`Tested\` PR against its pre-committed AC + evidence and merge it (4-eye = producer->you; never merge what you authored); if none is Tested, frame the top \`Backlog\` item -> \`Scoped\` with falsifiable AC. Surface the owner touchpoints (roadmap/EPIC, strategic exceptions, PROD) with a recommendation. /board for the overview. Never self-loop or poll. Sign all activity as ${SEAT_NAME}, never as the owner.
EOP
    ;;
  scrum-master)
    read -r -d '' PROMPT <<EOP || true
You are ${SEAT_NAME}, the Scrum-Master seat for ${INSTANCE} — board-mechanics helper, operator-driven (the OWNER orchestrates; you do NOT auto-dispatch). No loop, no polling, no events. Confirm your seat + boot your read-order, then: git fetch origin main, then idle. When the owner runs /check here: do ONE flow pass over board #${BOARD_ID:-?} — explode any newly-framed Epic into sub-issues (back-link the #s), enforce WIP, sweep aging/Blocked, and surface Tested-ready + the 3 consult-exceptions to the PM. Producers pull their own Scoped via /check, so you don't push work. You never merge, adjudicate, or write product code. Never self-loop or poll. Sign all activity as ${SEAT_NAME}.
EOP
    ;;
  quality-engineer)
    read -r -d '' PROMPT <<EOP || true
You are ${SEAT_NAME}, the quality-engineer seat for ${INSTANCE} — operator-driven (the OWNER orchestrates; no loop, no polling, no events). Your full brief is injected at session start. Confirm your seat + boot your read-order, then: git fetch origin main, then idle. When the owner runs /check here (or says go): pull your next workload — the next \`Delivered\` item — and VERIFY it against its pre-committed AC on the deployed env (perturb the happy path); post a per-criterion PASS/FAIL; PASS->\`Tested\`, FAIL->\`In Progress\`. You never merge. Report + stop — one item per /check. Never self-loop or poll. Sign all activity as ${SEAT_NAME}.
EOP
    ;;
  *)
    read -r -d '' PROMPT <<EOP || true
You are ${SEAT_NAME}, the ${SEAT_ROLE} seat for ${INSTANCE} — operator-driven (the OWNER orchestrates; no loop, no polling, no events). Your full brief is injected at session start. Confirm your seat + boot your read-order, then: git fetch origin main, then idle. When the owner runs /check here (or says go): pull your next workload — the next \`Scoped\` item carrying your \`seat:\` label — CLAIM it (flip Scoped->In Progress + assign), build per your KICKOFF (branch off origin/main, gates + a real deployed round-trip), ONE PR with '## Closes #n', set \`Delivered\`, post your ready-signal. NEVER self-merge — the PM adjudicates. Report + stop — one item per /check. Never self-loop or poll. Sign all activity as ${SEAT_NAME}.
EOP
    ;;
esac

echo "== ${TITLE} · operator-driven (semi-automated) — /check to pull work, /board for the overview =="
echo "worktree: $WORKTREE"
exec claude --permission-mode acceptEdits "$PROMPT"
