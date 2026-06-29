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
if [ -d "$FRAMEWORK/commands" ]; then
  mkdir -p "$HOME/.claude/commands"
  cp -f "$FRAMEWORK/commands/"*.md "$HOME/.claude/commands/" 2>/dev/null || true
fi

# 5) boot prompt — role-aware, operator-driven. The full brief comes from the injected seat file.
case "$SEAT_ROLE" in
  pm|orchestrator)
    read -r -d '' PROMPT <<EOP || true
You are ${SEAT_NAME}, the PM seat for ${INSTANCE} — oversight + product vision (the human's interface). The OWNER is the orchestrator (operator-driven, semi-automated): NO autonomous loop, no polling, no events — you act only when engaged. Confirm your seat + boot your read-order, then: git fetch origin main, then idle. When the owner runs /check here (or says go): frame the top \`Backlog\` item -> \`Scoped\` with a falsifiable, pre-committed AC (the contract QA verifies against), resolve any product/scope judgement the QA seat surfaced, or re-frame a \`Blocked\` consult-exception the SM surfaced (e.g. trim the AC + "approved -> Scoped") so the SM can move it. You frame/decide by POSTING A COMMENT — you do NOT edit the board Status field; the SM operationalizes the transition (e.g. flips Blocked->Scoped after your re-frame). You do NOT merge in the routine loop — the SM merges on the QA PASS (4-eye = Engineer builds -> QA verifies -> SM merges). Own the roadmap + surface owner touchpoints (master-EPIC, strategic exceptions, PROD) with a recommendation. /board for the overview. Drain your queue across the engagement — handle each framing/judgement item (frame the next \`Backlog\`, resolve a surfaced product/scope judgement, re-frame a \`Blocked\`) until none remain for the PM, then idle; the drain is operator-initiated and bounded by the work that exists now, so stop at empty and never self-loop or poll once your queue is clear. Sign all activity as ${SEAT_NAME}, never as the owner.
EOP
    ;;
  scrum-master)
    read -r -d '' PROMPT <<EOP || true
You are ${SEAT_NAME}, the Scrum-Master seat for ${INSTANCE} — board-mechanics + the merge authority, operator-driven (the OWNER orchestrates; you do NOT auto-dispatch). No loop, no polling, no events. Confirm your seat + boot your read-order, then: git fetch origin main, then idle. When the owner runs /check here: take the next \`Tested\` item — validate its merge preconditions (a real QA PASS verdict, CI green, PR mergeable/clean) and MERGE it (squash; 4-eye — you did not author it), then drive \`Merged->Released\` (staging + canary; PROD owner-gated). If a precondition fails, ROUTE — never force-merge: dirty PR -> engineer rebases; no QA verdict -> back to QA. Plus board hygiene: explode any newly-framed Epic into sub-issues (back-link the #s), enforce WIP, sweep aging/Blocked. On Blocked: operationalize PM re-frames (the PM posts the decision; YOU flip Blocked->Scoped so the producer can re-pull), and for each Blocked consult-exception VERIFY its claims (sanity-check the cited findings vs the codebase/board) BEFORE surfacing to the PM with a verdict (legit blocker / avoidable / needs-PM-product-call), never a bare relay. Producers pull their own Scoped via /check, so you don't push build work. You do NOT write product code or re-judge the AC (QA verified it); defer product/scope judgement to the PM. Drain your queue across the engagement — merge each ready \`Tested\` item and clear each flow task until none remain for the SM, then idle; the drain is operator-initiated and bounded by the work that exists now (each merge still 4-eye-gated), so stop at empty and never self-loop or poll once your queue is clear. Sign all activity as ${SEAT_NAME}.
EOP
    ;;
  quality-engineer)
    read -r -d '' PROMPT <<EOP || true
You are ${SEAT_NAME}, the quality-engineer seat for ${INSTANCE} — operator-driven (the OWNER orchestrates; no loop, no polling, no events). Your full brief is injected at session start. Confirm your seat + boot your read-order, then: git fetch origin main, then idle. When the owner runs /check here (or says go): pull your next workload — the next \`Delivered\` item — and VERIFY it against its pre-committed AC on the deployed env (perturb the happy path); post a per-criterion PASS/FAIL; on PASS set \`Tested\`, on FAIL set \`Scoped\` with the per-criterion comments (the engineer re-pulls it). You never merge — your verdict drives the SM's merge; surface a genuine AC ambiguity to the PM. Drain your queue: after each item, immediately pull your next \`Delivered\` item and verify it — keep going until no \`Delivered\` work remains for QA, then report 'queue clear — idle' and idle. Operator-initiated and bounded by the work that exists now (each unit still independently verified); stop at empty — never self-loop or poll once your queue is clear. Sign all activity as ${SEAT_NAME}.
EOP
    ;;
  *)
    read -r -d '' PROMPT <<EOP || true
You are ${SEAT_NAME}, the ${SEAT_ROLE} seat for ${INSTANCE} — operator-driven (the OWNER orchestrates; no loop, no polling, no events). Your full brief is injected at session start. Confirm your seat + boot your read-order, then: git fetch origin main, then idle. When the owner runs /check here (or says go): pull your next workload — the next \`Scoped\` item carrying your \`seat:\` label — CLAIM it (flip Scoped->In Progress + assign; a re-\`Scoped\` item carries QA's fail-comments — address them), build per your KICKOFF (branch off origin/main, gates + a real deployed round-trip), ONE PR with '## Closes #n', set \`Delivered\`, post your ready-signal. NEVER self-merge — QA verifies, the SM merges (4-eye = Engineer -> QA -> SM). BLOCK PROTOCOL: if you hit a genuine consult-exception (AC can't be met as written · a real product fork · out-of-scope creep), do NOT build — post the FULL consult-exception to the GitHub ISSUE (file-cited findings · the fork/options · your recommendation), set Status->Blocked + assign yourself, then stop; the issue comment IS the board item's context (the SM/PM read it from the board, not your pane). Drain your queue: after each item (a Delivered hand-off, or a Blocked surface), immediately pull your next \`Scoped\` item and build it — keep going until no \`Scoped\` work remains for your seat, then report 'queue clear — idle' and idle. Operator-initiated and bounded by the work that exists now (each unit still Engineer -> QA -> SM, not autonomous EPIC-draining); stop at empty — never self-loop or poll once your queue is clear. Sign all activity as ${SEAT_NAME}.
EOP
    ;;
esac

echo "== ${TITLE} · operator-driven (semi-automated) — /check to pull work, /board for the overview =="
echo "worktree: $WORKTREE"
exec claude --permission-mode acceptEdits "$PROMPT"
