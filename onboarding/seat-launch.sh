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
# operator engages it; then on /check (role-aware) it DRAINS its queue — reads the board once, then
# handles every eligible item in that one snapshot (item -> report -> next) until none remain for its
# role, then idles. The drain is operator-initiated and bounded by the work that exists now (one board
# read per /check, cheap per-item ops after); it STOPS at empty (no idle-poll, no self-loop). The
# operator conducts the cadence (watch /board → run /check in the seat that should advance). Generic
# across instances; SEAT_ROLE is the enforced type.
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
#     LEGACY PATH — superseded by the agentic-sdlc plugin (which ships the same commands, versioned,
#     on every Claude Code surface); kept for un-pluginned machines, to be retired after the plugin
#     pilot (#24).
if [ -d "$FRAMEWORK/commands" ]; then
  mkdir -p "$HOME/.claude/commands"
  cp -f "$FRAMEWORK/commands/"*.md "$HOME/.claude/commands/" 2>/dev/null || true
fi

# 5) boot prompt — ONE generic instruction for every role (single-source: the
#    role's authority lives in its KICKOFF + injected seat brief; the role's
#    drain contract lives in /check. The per-role heredocs that used to sit
#    here restated /check in different words and drifted — see #24).
read -r -d '' PROMPT <<EOP || true
You are ${SEAT_NAME}, the ${SEAT_ROLE} seat for ${INSTANCE} — operator-driven: the OWNER orchestrates; no autonomous loop, no polling, no events — you act only when engaged. Boot now: confirm your seat, follow your read-order (root CLAUDE.md -> agentic-sdlc/README.md -> the spine -> seats/${SEAT_ROLE}/KICKOFF.md; your injected seat brief names you), then run 'git fetch origin main' and idle. When the owner runs /check here (or says go), drain your queue per YOUR role's contract in /check — take an eligible item, do it, report, take the next — until none remain for your role, then report 'queue clear — idle' and stop: never self-loop or poll once your queue is clear. Your KICKOFF defines your authority and its limits (who merges, who adjudicates, what is owner-gated); /check defines your discovery, transitions, and block protocol. Sign all activity as ${SEAT_NAME}, never as the owner.
EOP

# 6) model tier — configured per seat in sdlc.config (role:Name:model triples; bootstrap writes the
#    resolved tier to this worktree's .env.local as SEAT_MODEL). The case below is only the FALLBACK
#    for hand-made seats whose .env.local predates SEAT_MODEL: PM + quality-engineer (judgment + the
#    independent gate) → opus; scrum-master + producers (mechanical / volume, with a downstream
#    gate) → sonnet. Set SEAT_MODEL="" explicitly to inherit the account default (pass no --model).
#    `${SEAT_MODEL-…}` keeps an explicit "" distinct from unset.
case "$SEAT_ROLE" in
  pm|orchestrator|quality-engineer) DEFAULT_MODEL="opus" ;;
  *)                                DEFAULT_MODEL="sonnet" ;;
esac
SEAT_MODEL="${SEAT_MODEL-$DEFAULT_MODEL}"
MODEL_FLAG=(); [ -n "$SEAT_MODEL" ] && MODEL_FLAG=(--model "$SEAT_MODEL")

echo "== ${TITLE} · operator-driven (semi-automated) · model: ${SEAT_MODEL:-account-default} — /check to pull work, /board for the overview =="
echo "worktree: $WORKTREE"
exec claude "${MODEL_FLAG[@]}" --permission-mode acceptEdits "$PROMPT"
