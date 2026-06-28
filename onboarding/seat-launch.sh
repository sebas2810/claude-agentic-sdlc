#!/usr/bin/env bash
#
# seat-launch.sh — run an autonomous standing seat in THIS terminal.
#
# The runtime behind every generated <seat>.command (and thus every .app). Given a worktree
# with a .env.local (SEAT_ROLE/SEAT_NAME/... — see .env.local.example), it:
#   1. titles the terminal window           ("Engineer - Dex")
#   2. runs setup-seat.sh                    (per-worktree git identity + creds + the seat brief +
#                                             the SessionStart hook that injects it)
#   3. (optional) mints a board-ops token    (own GraphQL quota — e.g. a GitHub App)
#   4. wires the Stop-hook board-loop         (autonomous producer/verifier seats)
#   5. launches `claude` in accept-edits      ("auto" mode) with a generic boot prompt
# The seat then self-loops the board via seat-loop-hook.sh. Generic across instances; names are
# free, SEAT_ROLE is the enforced type. The PM/orchestrator runs its own runner (no Stop-loop).
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
AUTONOMOUS="${SEAT_AUTONOMOUS:-1}"
case "$SEAT_ROLE" in pm|orchestrator) AUTONOMOUS=0 ;; esac   # PM self-drives via its own runner
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

# 4) wire the Stop-hook board-loop (autonomous producer/verifier only). The hook is a child of
#    claude, so it inherits these exports.
if [ "$AUTONOMOUS" = "1" ]; then
  export SEAT_ROLE SEAT_LABEL="${SEAT_LABEL:-}" BOARD_ID="${BOARD_ID:-}" BOARD_OWNER="${BOARD_OWNER:-}"
  mkdir -p .claude
  [ -f .claude/settings.local.json ] || printf '{}\n' > .claude/settings.local.json
  tmp="$(mktemp)"
  if jq --arg cmd "bash $FRAMEWORK/onboarding/seat-loop-hook.sh" \
        '.hooks.Stop = [{"hooks":[{"type":"command","command":$cmd}]}]' \
        .claude/settings.local.json > "$tmp" 2>/dev/null; then mv "$tmp" .claude/settings.local.json; else rm -f "$tmp"; fi
fi

# 5) boot prompt — role-aware; the full brief comes from the injected seat file.
case "$SEAT_ROLE" in
  scrum-master)     LOOP_LINE="ORCHESTRATE per your orchestrator-runner: enforce WIP, dispatch Scoped items to producer seats, ensure Delivered->Quality, drive Merged->deploy/canary->Released, route failures (deploy-fail->fix-story, QA-fail->re-Scope), wake idle seats. Surface Tested-ready items + consult-exceptions to the PM. You do NOT merge, adjudicate, or write product code." ;;
  quality-engineer) LOOP_LINE="VERIFY each Delivered item against its pre-committed AC on the deployed env (perturb the happy path); post a per-criterion PASS/FAIL; PASS->Tested, FAIL->In Progress. You never merge." ;;
  *)                LOOP_LINE="take your next Scoped item carrying your label — CLAIM it (atomic flip In Progress + assign) -> build per your KICKOFF -> ONE PR -> Delivered. NEVER self-merge — the PM adjudicates." ;;
esac

if [ "$SEAT_ROLE" = "pm" ] || [ "$SEAT_ROLE" = "orchestrator" ]; then
  read -r -d '' PROMPT <<EOP || true
You are ${SEAT_NAME}, the PM seat for ${INSTANCE} — the human's interface + prep + adjudication (NOT the dispatch loop; the Scrum-Master orchestrates that). Confirm your seat + boot your read-order, then: git fetch origin main. Your work: (1) PREP — identify + prioritise new work and the roadmap; refine Backlog->Scoped with pre-committed, falsifiable AC (Definition of Ready). (2) ADJUDICATE — review Tested/green producer PRs against the AC you pre-committed, and merge (the merge authority; 4-eye = producer->you; never merge what you authored). (3) OWNER interface — surface the fixed touchpoints (roadmap/EPIC framing, strategic consult-exceptions, PROD) with a recommendation. Sign all activity as ${SEAT_NAME}, never as the owner.
EOP
else
  read -r -d '' PROMPT <<EOP || true
You are ${SEAT_NAME}, the ${SEAT_ROLE} seat for ${INSTANCE} (SDLC_MODE=autonomous). Your full brief is injected at session start. Confirm your seat + boot your read-order, then: git fetch origin main. Then run your board-loop over the Execution board (#${BOARD_ID:-?}, owner ${BOARD_OWNER:-?}): ${LOOP_LINE} The Stop hook hands you the next item automatically; stop only when your queue is empty (or a 3rd repeat of one item -> Blocked + a consult-exception). Sign all activity as ${SEAT_NAME}.
EOP
fi

echo "== ${TITLE} · autonomous=${AUTONOMOUS} =="
echo "worktree: $WORKTREE"
exec claude --permission-mode acceptEdits "$PROMPT"
