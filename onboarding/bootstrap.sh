#!/usr/bin/env bash
#
# bootstrap.sh — one-command interactive setup for a new agentic-SDLC instance.
#
# Run once from the root of your product repo (a fork of this framework, so it
# already contains agentic-sdlc/). Answer the prompts and it stands up the whole
# thing end-to-end:
#
#   • GitHub  — the portable label taxonomy (incl. the status:* routing index),
#               ONE Delivery project (Board + EPICS views), the standing epics,
#               the per-seat seat:* lane labels, an optional guided first epic,
#               and the instance overlay skeleton.          (create-instance.sh)
#   • Gates   — the PreToolUse git guard (no-push-to-main · no-AI-attribution ·
#               rebase-before-push) wired into the product root .claude/, and a
#               root CLAUDE.md stamped if absent.        (hooks/guard-git.sh)
#   • Local   — one isolated git worktree per seat, each with its own identity
#               written to .env.local + the seat file scaffolded.
#                                          (git worktree + setup-seat.sh)
#   • Apps    — a double-clickable launcher (and, on macOS, a .app bundle) per
#               seat, so a teammate just double-clicks to open their pane.
#                                     (make-launcher.sh + build-apps.sh)
#
# Nothing here is irreversible without confirmation; it prints a summary and
# asks you to type "yes" before it touches GitHub or your disk.
#
# Requires: git · gh (authenticated, with `project` scope) · node · jq.
#           macOS only for the optional .app step.
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"    # agentic-sdlc/onboarding
ROOT="$(cd "$HERE/../.." && pwd)"                       # the product repo root

c_head(){ printf '\n\033[1;36m%s\033[0m\n' "$*"; }
c_ok(){   printf '  \033[32m✓\033[0m %s\n' "$*"; }
c_info(){ printf '  %s\n' "$*"; }
die(){    printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
ask(){ # ask "Prompt:" "default" -> echoes answer (or default if blank)
  local p="$1" d="${2:-}" a
  read -rp "$(printf '\033[1m%s\033[0m%s ' "$p" "${d:+ [$d]}")" a || true
  printf '%s' "${a:-$d}"
}

# ── 0. preflight ──────────────────────────────────────────────────────────────
c_head "▶ Agentic SDLC — instance bootstrap"
for bin in git gh node jq; do
  command -v "$bin" >/dev/null 2>&1 || die "missing '$bin' — install it first."
done
gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run 'gh auth login' (it needs the 'project' scope)."
# scope check (best-effort — classic tokens report X-OAuth-Scopes; fine-grained/App tokens don't)
GH_SCOPES="$(gh api -i user 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}')"
if [ -n "$GH_SCOPES" ] && ! printf '%s' "$GH_SCOPES" | grep -qw 'project'; then
  c_info "⚠ your gh token lists no 'project' scope — board provisioning will fail. Fix: gh auth refresh -s project"
fi
# layout check — this script must run from INSIDE a product repo that vendors the framework
[ -d "$ROOT/agentic-sdlc" ] && git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1 \
  || die "not a product repo (no $ROOT/agentic-sdlc). Vendor the framework first: bash onboarding/vendor-framework.sh --into <your-product-repo>"

# ── 1. prompts (sensible defaults, all overridable) ───────────────────────────
DEF_OWNER="$(gh api user --jq .login 2>/dev/null || true)"
DEF_REPO="$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null \
            | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' || true)"
DEF_INSTANCE="$(basename "${DEF_REPO:-my-instance}")"

OWNER="$(ask 'GitHub owner (login or org):' "$DEF_OWNER")"
REPO="$(ask  'Product repo (owner/repo):'   "$DEF_REPO")"
INSTANCE="$(ask 'Instance name (short slug):' "$DEF_INSTANCE")"
BASE="$(ask  'Checkout base dir:'           "$HOME/Code")"

c_info "Seats to stand up (space-separated). Available roles:"
c_info "  pm · engineer · scrum-master · quality-engineer · cloud-architect · data-architect · data-scientist"
SEATS="$(ask 'Seats:' 'pm engineer scrum-master quality-engineer')"

GIT_NAME="$(ask  'Git commit name for these seats:'  "$(git config --global user.name  2>/dev/null || echo '')")"
GIT_EMAIL="$(ask 'Git commit email:'                 "$(git config --global user.email 2>/dev/null || echo '')")"
AWS_PROFILE="$(ask 'AWS profile (optional, blank to skip):' '')"

SEED_EPIC="$(ask 'Seed the guided first epic (one full pass through the loop)? (y/n):' 'y')"

BUILD_APPS='n'
[ "$(uname)" = "Darwin" ] && BUILD_APPS="$(ask 'Build a double-clickable macOS .app per seat? (y/n):' 'y')"

REPONAME="$(basename "$REPO")"
APPS_DIR="$BASE/agents/$INSTANCE"

# ── 2. confirm (the only gate before anything is written) ─────────────────────
cat <<SUMMARY

  ────────────────────────────────────────────────
  owner       $OWNER
  repo        $REPO
  instance    $INSTANCE
  seats       $SEATS
  worktrees   $BASE/${REPONAME}-<seat>
  apps        $APPS_DIR   (build .app: $BUILD_APPS)
  first epic  $SEED_EPIC
  commit as   ${GIT_NAME:-<unset>} <${GIT_EMAIL:-unset}>
  ────────────────────────────────────────────────
SUMMARY
[ "$(ask 'Proceed? type "yes":' 'no')" = "yes" ] || die "aborted — nothing was changed."

# ── 3. GitHub: labels · Delivery board · standing epics · overlay ─────────────
c_head "▶ Provisioning GitHub (labels · Delivery board · standing epics · overlay)"
bash "$HERE/create-instance.sh" --instance "$INSTANCE" --owner "$OWNER" --repo "$REPO"

# seat:* lane labels — the routing lane each producer's /check pulls on
for role in $SEATS; do
  gh label create "seat:$role" --repo "$REPO" --color "0E8A16" \
    --description "Routing lane: work for the $role seat" --force >/dev/null 2>&1 \
    && c_ok "label seat:$role" || c_info "label seat:$role (exists)"
done

# optional guided first epic — one full pass through the loop on day one
# (URL kept: it goes ON the board once the board number is discovered below)
FIRST_EPIC_URL=""
if [ "$SEED_EPIC" = "y" ]; then
  FIRST_EPIC_URL="$(gh issue create --repo "$REPO" \
    --title "EPIC: Hello, Agentic SDLC — first pass through the loop" \
    --label "level:epic,type:chore,status:backlog" \
    --body-file "$HERE/first-epic.md" 2>/dev/null)" \
    && c_ok "guided first epic seeded (PM: /check frames it; SM: /check explodes it)" \
    || { FIRST_EPIC_URL=""; c_info "first-epic seeding skipped (exists, or labels missing)"; }
fi

# ── 3.5 gates: git guard + root CLAUDE.md ─────────────────────────────────────
c_head "▶ Wiring the gates (.claude/hooks/guard-git.sh + CLAUDE.md)"
mkdir -p "$ROOT/.claude/hooks"
cp "$HERE/hooks/guard-git.sh" "$ROOT/.claude/hooks/guard-git.sh"
chmod +x "$ROOT/.claude/hooks/guard-git.sh"
SETTINGS="$ROOT/.claude/settings.json"
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
if grep -q 'guard-git\.sh' "$SETTINGS" 2>/dev/null; then
  c_ok "PreToolUse git guard already wired"
else
  _tmp="$(mktemp)"
  jq '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/guard-git.sh"}]}])' \
    "$SETTINGS" > "$_tmp" && mv "$_tmp" "$SETTINGS"
  c_ok "PreToolUse git guard wired (no-push-to-main · no-attribution · rebase-before-push)"
fi
if [ ! -f "$ROOT/CLAUDE.md" ]; then
  cp "$HERE/CLAUDE.template.md" "$ROOT/CLAUDE.md"
  c_ok "CLAUDE.md stamped at the product root (fill in the product-context section)"
else
  c_info "CLAUDE.md already present (kept)"
fi

# Best-effort: discover the Delivery project number just created (for .env.local).
BOARD_ID="$(gh project list --owner "$OWNER" --format json --limit 100 2>/dev/null \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const p=(j.projects||[]).filter(p=>/Delivery/i.test(p.title||"")).sort((a,b)=>b.number-a.number)[0];process.stdout.write(p?String(p.number):"")}catch(e){}})' 2>/dev/null || true)"
[ -n "$BOARD_ID" ] && c_ok "Delivery board is project #$BOARD_ID" || c_info "(couldn't auto-detect the board number — set BOARD_ID in each .env.local afterwards)"

# the first epic lives ON the board (create-instance.sh adds the standing epics itself)
if [ -n "$FIRST_EPIC_URL" ] && [ -n "$BOARD_ID" ]; then
  gh project item-add "$BOARD_ID" --owner "$OWNER" --url "$FIRST_EPIC_URL" >/dev/null 2>&1 \
    && c_ok "first epic added to board #$BOARD_ID" \
    || c_info "couldn't add the first epic to the board — add it by hand: gh project item-add $BOARD_ID --owner $OWNER --url $FIRST_EPIC_URL"
fi

# ── 4. one isolated worktree + identity per seat ──────────────────────────────
for role in $SEATS; do
  WT="$BASE/${REPONAME}-${role}"
  c_head "▶ Seat '$role' → $WT"
  if [ -d "$WT" ]; then
    c_info "worktree already exists — reusing"
  else
    git -C "$ROOT" worktree add "$WT" main >/dev/null 2>&1 \
      || git -C "$ROOT" worktree add "$WT" HEAD >/dev/null 2>&1 \
      || { c_info "could not add worktree (skipping seat)"; continue; }
    c_ok "worktree checked out"
  fi
  cat > "$WT/.env.local" <<ENV
INSTANCE=$INSTANCE
SEAT_ROLE=$role
SEAT_NAME=$role
GIT_USER_NAME="$GIT_NAME"
GIT_USER_EMAIL="$GIT_EMAIL"
AWS_PROFILE=$AWS_PROFILE
SEAT_LABEL=seat:$role
BOARD_ID=$BOARD_ID
BOARD_OWNER=$OWNER
ENV
  c_ok ".env.local written"
  ( cd "$WT" && source ./agentic-sdlc/onboarding/setup-seat.sh ) >/dev/null 2>&1 \
    && c_ok "seat identity + SessionStart hook scaffolded" \
    || c_info "run 'source ./agentic-sdlc/onboarding/setup-seat.sh' in the worktree to finish seat config"
  bash "$HERE/make-launcher.sh" --worktree "$WT" --out "$APPS_DIR" >/dev/null 2>&1 \
    && c_ok "launcher → $APPS_DIR/${role}.command" \
    || c_info "launcher step skipped"
done

# ── 5. wrap launchers into macOS .app bundles (optional) ──────────────────────
if [ "$BUILD_APPS" = "y" ] && [ "$(uname)" = "Darwin" ]; then
  c_head "▶ Building double-clickable .app bundles"
  bash "$HERE/build-apps.sh" --dir "$APPS_DIR" >/dev/null 2>&1 \
    && c_ok "apps → $APPS_DIR/*.app" \
    || c_info "app-build step skipped"
fi

# ── 6. you're live ────────────────────────────────────────────────────────────
cat <<DONE

  ✓ Instance '$INSTANCE' is live.

    Board    https://github.com/users/$OWNER/projects/${BOARD_ID:-?}
             (one-time: apply the EPICS + Board views — workflow/project-boards.md)
    Seats    $SEATS
    Gates    .claude/hooks/guard-git.sh (PreToolUse) + root CLAUDE.md
             (commit both: git add .claude CLAUDE.md)
    Apps     $APPS_DIR/
    Start    open a seat (double-click its .app, or 'cd' its worktree and run 'claude'),
             then type  /check  to pull the next work item from the board.

  Next: $( [ "$SEED_EPIC" = "y" ] \
    && echo "run the guided first epic — /check in the PM seat frames it (onboarding/first-epic.md)." \
    || echo "frame your first epic — workflow/state-machine.md." )
DONE
