#!/usr/bin/env bash
#
# bootstrap.sh — one-command setup for a new agentic-SDLC instance.
#
# ALL bespoke configuration lives in ONE committed file at the product root:
#
#   sdlc.config   — instance · repo · seats (role:Name) · git identity · AWS
#                   profile · behaviour flags   (see onboarding/sdlc.config.example)
#
# First run (no sdlc.config): an interactive wizard asks, SUGGESTS seat names
# (Pim · Finn · Cas · Noor · Vera · …), writes the file, then provisions.
# Re-runs read the file and are idempotent — safe after editing sdlc.config,
# on a new machine, or to repair a partial run. Secrets NEVER go in
# sdlc.config — GH_TOKEN etc. live in each worktree's .env.local (gitignored).
#
# What it stands up (each step reports; failures are LOUD, never masked):
#   • GitHub  — label taxonomy (status:* routing index), ONE Delivery project
#               (reused if it already exists), standing epics, seat:* lanes,
#               an optional guided first epic.              (create-instance.sh)
#   • Gates   — the PreToolUse git guard + root CLAUDE.md + a root .gitignore
#               covering the seat env/identity files.    (hooks/guard-git.sh)
#   • Local   — one worktree per seat named AFTER the seat ($BASE/<repo>-<name>)
#               on its own seat/<name> branch, with identity in .env.local.
#   • Panes   — the operator slash-commands (/check · /board · /workload ·
#               /backlog) installed for every launch path, a double-clickable
#               launcher per seat and, on macOS, a <Name>.app bundle.
#
# Usage:
#   bash agentic-sdlc/onboarding/bootstrap.sh          # wizard or config-driven
#   bash agentic-sdlc/onboarding/bootstrap.sh --yes    # non-interactive (needs sdlc.config)
#
# Requires: git · gh (authenticated, `project` scope) · node · jq.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"    # agentic-sdlc/onboarding
ROOT="$(cd "$HERE/../.." && pwd)"                       # the product repo root
LOG="$(mktemp -t sdlc-bootstrap.XXXXXX)"

c_head(){ printf '\n\033[1;36m%s\033[0m\n' "$*"; }
c_ok(){   printf '  \033[32m✓\033[0m %s\n' "$*"; }
c_info(){ printf '  %s\n' "$*"; }
c_warn(){ printf '  \033[33m⚠ %s\033[0m\n' "$*"; }
die(){    printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; printf '  log: %s\n' "$LOG" >&2; exit 1; }
fail_step(){ # fail_step "what" — show the captured output, then die
  printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2
  tail -n 8 "$LOG" | sed 's/^/    │ /' >&2
  die "fix the cause above, then re-run bootstrap (it is idempotent)."
}
ask(){ # ask "Prompt:" "default" -> echoes answer (or default if blank)
  local p="$1" d="${2:-}" a
  read -rp "$(printf '\033[1m%s\033[0m%s ' "$p" "${d:+ [$d]}")" a || true
  printf '%s' "${a:-$d}"
}
yes_p(){ case "${1:-}" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac; }

YES=0
while [ $# -gt 0 ]; do case "$1" in
  --yes|-y) YES=1; shift ;;
  *) die "unknown arg: $1 (usage: bootstrap.sh [--yes])" ;;
esac; done

# ── 0. preflight: tools + auth ────────────────────────────────────────────────
c_head "▶ Agentic SDLC — instance bootstrap"
for bin in git gh node jq; do
  command -v "$bin" >/dev/null 2>&1 || die "missing '$bin' — install it first."
done
gh auth status >>"$LOG" 2>&1 || die "gh is not authenticated — run 'gh auth login'."
git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1 \
  || die "not a git repo ($ROOT). Vendor the framework first: bash onboarding/vendor-framework.sh --into <your-product> --repo <you>/<your-product>"
[ -d "$ROOT/agentic-sdlc" ] \
  || die "no $ROOT/agentic-sdlc — run bootstrap from a product repo that vendors the framework."
git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1 \
  || die "this repo has no commits yet — commit the vendored framework first: git add -A && git commit -m 'chore(sdlc): vendor framework'"

# `project` scope — hard check with a real Projects call (a missing scope used
# to surface halfway through provisioning, leaving partial state).
gh api graphql -f query='{viewer{projectsV2(first:1){totalCount}}}' >>"$LOG" 2>&1 \
  || die "your gh token cannot reach Projects v2 (missing 'project' scope?) — run: gh auth refresh -s project"

# ── 1. configuration: sdlc.config (wizard writes it on first run) ─────────────
CONFIG="$ROOT/sdlc.config"

# curated name pool (the instance style: short first names) + per-role defaults
NAME_POOL="Pim Finn Cas Noor Vera Otto Dex Max Sam Tess Quin Bo Isa Jip Roos"
ROLES="pm engineer scrum-master quality-engineer cloud-architect data-architect data-scientist"
default_name(){ case "$1" in
  pm) echo Pim ;; engineer) echo Finn ;; scrum-master) echo Cas ;;
  quality-engineer) echo Noor ;; cloud-architect) echo Otto ;;
  data-architect) echo Dex ;; data-scientist) echo Vera ;; *) echo "" ;;
esac; }
# model tier by role — capability where errors are expensive / hard to catch
# (judgment + the independent gate), economy on gated, high-volume work.
# Override per seat with a role:Name:model triple in SEATS.
default_model(){ case "$1" in
  pm|orchestrator|quality-engineer) echo opus ;; *) echo sonnet ;;
esac; }
# SEATS entries are role:Name or role:Name:model — parse one entry into
# SEAT_R / SEAT_N / SEAT_M (model empty = role default applies later)
parse_seat(){
  SEAT_R="${1%%:*}"
  local rest="${1#*:}"
  SEAT_N="${rest%%:*}"
  SEAT_M="${rest#*:}"
  # a pair has no third field — ${rest#*:} then equals the name itself
  if [ "$SEAT_M" = "$SEAT_N" ]; then SEAT_M=""; fi
}
pick_unused(){ # pick_unused "<used names>" -> first pool name not yet used
  local used="$1" n
  for n in $NAME_POOL; do
    printf '%s' "$used" | grep -qiw "$n" || { printf '%s' "$n"; return 0; }
  done
  printf 'Seat%s' "$RANDOM"
}

if [ -f "$CONFIG" ]; then
  c_ok "sdlc.config found — using it (edit the file + re-run to change anything)"
  # shellcheck disable=SC1090
  . "$CONFIG"
else
  [ "$YES" -eq 1 ] && die "--yes needs an sdlc.config (copy agentic-sdlc/onboarding/sdlc.config.example → sdlc.config and fill it in)."
  c_info "no sdlc.config yet — a few questions, then it is written for you (and committed with the repo)."

  DEF_OWNER="$(gh api user --jq .login 2>/dev/null || true)"
  DEF_REPO="$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null \
              | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' || true)"
  DEF_INSTANCE="$(basename "${DEF_REPO:-$ROOT}")"

  OWNER="$(ask 'GitHub owner (login or org):' "$DEF_OWNER")"
  REPO="$(ask  'Product repo (owner/repo):'   "$DEF_REPO")"
  INSTANCE="$(ask 'Instance name (short slug):' "$DEF_INSTANCE")"
  BASE="$(ask  'Checkout base dir:'           "$HOME/Code")"

  c_info "Roles: $ROLES"
  ROLE_LIST="$(ask 'Seats to stand up (roles, space-separated; a role may repeat):' 'pm engineer scrum-master quality-engineer')"

  # every seat gets a NAME — suggested from the pool; the checkout, launcher,
  # .app and (for producers) the seat:<name> routing lane are all named after it
  SEATS="" ; USED=""
  for role in $ROLE_LIST; do
    printf '%s' "$ROLES" | grep -qw "$role" || die "unknown role '$role' (roles: $ROLES)"
    SUGGEST="$(default_name "$role")"
    { [ -z "$SUGGEST" ] || printf '%s' "$USED" | grep -qiw "$SUGGEST"; } && SUGGEST="$(pick_unused "$USED")"
    NAME="$(ask "Name for the $role seat:" "$SUGGEST")"
    printf '%s' "$USED" | grep -qiw "$NAME" && die "seat name '$NAME' used twice — names must be unique."
    USED="$USED $NAME"
    SEATS="$SEATS${SEATS:+ }$role:$NAME"
  done

  GIT_USER_NAME="$(ask  'Git commit name for these seats:'  "$(git config --global user.name  2>/dev/null || echo '')")"
  GIT_USER_EMAIL="$(ask 'Git commit email:'                 "$(git config --global user.email 2>/dev/null || echo '')")"
  AWS_PROFILE="$(ask 'AWS profile (blank = no AWS):' '')"
  AWS_ACCOUNT_ID=""
  [ -n "$AWS_PROFILE" ] && AWS_ACCOUNT_ID="$(ask 'AWS account id (optional, verified when set):' '')"
  SEED_EPIC="$(ask 'Seed the guided first epic (one full pass through the loop)? (y/n):' 'y')"
  BUILD_APPS='n'
  [ "$(uname)" = "Darwin" ] && BUILD_APPS="$(ask 'Build a double-clickable macOS .app per seat? (y/n):' 'y')"

  # write the config — BASE stored $HOME-relative so the file is machine-portable
  BASE_OUT="$BASE"
  case "$BASE" in "$HOME"*) BASE_OUT="\$HOME${BASE#"$HOME"}" ;; esac
  cat > "$CONFIG" <<CFG
# sdlc.config — this instance's bespoke configuration (committed — NO secrets;
# tokens live in each worktree's gitignored .env.local). Written by bootstrap.sh
# on $(date +%Y-%m-%d); edit + re-run bootstrap any time (it is idempotent).
INSTANCE="$INSTANCE"
REPO="$REPO"
OWNER="$OWNER"
BASE="$BASE_OUT"
SEATS="$SEATS"
GIT_USER_NAME="$GIT_USER_NAME"
GIT_USER_EMAIL="$GIT_USER_EMAIL"
AWS_PROFILE="$AWS_PROFILE"
AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
SEED_EPIC="$SEED_EPIC"
BUILD_APPS="$BUILD_APPS"
GOLDEN_BOARD=""
CFG
  c_ok "sdlc.config written — commit it with the repo (git add sdlc.config)"
fi

# ── 1b. validate the configuration (config-file or wizard alike) ──────────────
for var in INSTANCE REPO OWNER BASE SEATS GIT_USER_NAME GIT_USER_EMAIL; do
  eval "val=\${$var:-}"
  [ -n "$val" ] || die "sdlc.config: $var must be set (empty git identity would make seats commit as nobody)."
done
USED=""
for pair in $SEATS; do
  [ "${pair%%:*}" != "$pair" ] || die "sdlc.config: SEATS entries are role:Name (or role:Name:model) — '$pair' has no name."
  parse_seat "$pair"
  printf '%s' "$ROLES" | grep -qw "$SEAT_R" || die "sdlc.config: unknown role '$SEAT_R' (roles: $ROLES)"
  [ -f "$HERE/seat.${SEAT_R}.template.md" ] || die "no seat template for role '$SEAT_R' ($HERE/seat.${SEAT_R}.template.md)"
  printf '%s' "$USED" | grep -qiw "$SEAT_N" && die "sdlc.config: seat name '$SEAT_N' used twice — names must be unique."
  USED="$USED $SEAT_N"
done
gh repo view "$REPO" >>"$LOG" 2>&1 \
  || die "repo '$REPO' not reachable on GitHub — publish it first (gh repo create $REPO --private --source . --push) or fix REPO in sdlc.config."
if [ -n "${AWS_PROFILE:-}" ] && [ -n "${AWS_ACCOUNT_ID:-}" ] && command -v aws >/dev/null 2>&1; then
  GOT_ACCT="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text 2>>"$LOG" || true)"
  if [ "$GOT_ACCT" != "$AWS_ACCOUNT_ID" ]; then
    c_warn "AWS profile '$AWS_PROFILE' resolves to account '${GOT_ACCT:-unresolved}', expected '$AWS_ACCOUNT_ID' — check ~/.aws before the seats do real work."
  fi
fi

REPONAME="$(basename "$REPO")"
APPS_DIR="$BASE/agents/$INSTANCE"

# ── 2. confirm (the only gate before anything is written) ─────────────────────
cat <<SUMMARY

  ────────────────────────────────────────────────
  owner       $OWNER
  repo        $REPO
  instance    $INSTANCE
  seats       $SEATS
  worktrees   $BASE/${REPONAME}-<name>   (branch seat/<name>)
  apps        $APPS_DIR   (build .app: $BUILD_APPS)
  first epic  $SEED_EPIC
  commit as   $GIT_USER_NAME <$GIT_USER_EMAIL>
  config      $CONFIG
  ────────────────────────────────────────────────
SUMMARY
if [ "$YES" -eq 0 ]; then
  yes_p "$(ask 'Proceed? (yes/no):' 'no')" || die "aborted — nothing was changed."
fi

# ── 3. GitHub: labels · Delivery board (reused if present) · epics · overlay ──
c_head "▶ Provisioning GitHub (labels · Delivery board · standing epics · overlay)"
CI_LOG="$(mktemp -t sdlc-create.XXXXXX)"
# (macOS bash 3.2: expanding an EMPTY array under set -u is an unbound-variable
# error — hence the ${arr[@]+...} guard idiom rather than a bare "${arr[@]}")
GOLDEN_ARGS=()
[ -n "${GOLDEN_BOARD:-}" ] && GOLDEN_ARGS=(--golden "$GOLDEN_BOARD")
if ! bash "$HERE/create-instance.sh" --instance "$INSTANCE" --owner "$OWNER" --repo "$REPO" ${GOLDEN_ARGS[@]+"${GOLDEN_ARGS[@]}"} | tee "$CI_LOG"; then
  cat "$CI_LOG" >>"$LOG"; fail_step "create-instance.sh failed"
fi
# the board number — emitted by create-instance.sh on a machine-readable line
BOARD_ID="$(awk -F= '/^BOARD_NUM=/{print $2}' "$CI_LOG" | tail -1)"
rm -f "$CI_LOG"
[ -n "$BOARD_ID" ] && c_ok "Delivery board is project #$BOARD_ID" \
  || c_warn "couldn't determine the board number — set BOARD_ID in each .env.local afterwards"

# seat:* lane labels — producers get a PER-NAME lane (two engineers = two lanes);
# pm / scrum-master / quality-engineer key off their role, no lane needed.
for pair in $SEATS; do
  parse_seat "$pair"
  case "$SEAT_R" in pm|scrum-master|quality-engineer) continue ;; esac
  key="$(printf '%s' "$SEAT_N" | tr '[:upper:] ' '[:lower:]-')"
  gh label create "seat:$key" --repo "$REPO" --color "0E8A16" \
    --description "Routing lane: work for $SEAT_N (the $SEAT_R seat)" --force >>"$LOG" 2>&1 \
    && c_ok "label seat:$key ($SEAT_N)" || c_warn "label seat:$key failed (see log)"
done

# optional guided first epic — once; re-runs detect it by title
FIRST_EPIC_URL=""
if yes_p "$SEED_EPIC"; then
  EXISTING="$(gh issue list --repo "$REPO" --state all --search 'in:title "EPIC: Hello, Agentic SDLC"' --json number --jq '.[0].number' 2>>"$LOG" || true)"
  if [ -n "$EXISTING" ]; then
    c_info "guided first epic already seeded (#$EXISTING)"
  elif FIRST_EPIC_URL="$(gh issue create --repo "$REPO" \
      --title "EPIC: Hello, Agentic SDLC — first pass through the loop" \
      --label "level:epic,type:chore,status:backlog" \
      --body-file "$HERE/first-epic.md" 2>>"$LOG")"; then
    c_ok "guided first epic seeded (PM: /check frames it; SM: /check explodes it)"
    [ -n "$BOARD_ID" ] && gh project item-add "$BOARD_ID" --owner "$OWNER" --url "$FIRST_EPIC_URL" >>"$LOG" 2>&1 \
      && c_ok "first epic added to board #$BOARD_ID" \
      || c_warn "couldn't add the first epic to board #$BOARD_ID — gh project item-add $BOARD_ID --owner $OWNER --url $FIRST_EPIC_URL"
  else
    fail_step "seeding the first epic failed (labels missing?)"
  fi
fi

# ── 3.5 gates: git guard + root CLAUDE.md + root .gitignore ───────────────────
c_head "▶ Wiring the gates (.claude/hooks/guard-git.sh · CLAUDE.md · .gitignore)"
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
# root .gitignore — the seat env/identity files live at the PRODUCT root; the
# framework's own .gitignore only covers agentic-sdlc/. Without these lines a
# seat's `git add -A` would commit .env.local (which may hold a GH_TOKEN).
for pat in '.env.local' '.*-seat.md' '.claude/settings.local.json' '.DS_Store'; do
  grep -qxF "$pat" "$ROOT/.gitignore" 2>/dev/null || printf '%s\n' "$pat" >> "$ROOT/.gitignore"
done
c_ok ".gitignore covers .env.local · .*-seat.md · .claude/settings.local.json"

# ── 4. one worktree per seat — NAMED after the seat, on its own branch ────────
for pair in $SEATS; do
  parse_seat "$pair"
  role="$SEAT_R" ; name="$SEAT_N"
  model="${SEAT_M:-$(default_model "$role")}"
  key="$(printf '%s' "$name" | tr '[:upper:] ' '[:lower:]-')"
  WT="$BASE/${REPONAME}-${key}"
  c_head "▶ Seat $name ($role · $model) → $WT"
  if [ -d "$WT" ]; then
    c_info "worktree already exists — reusing"
  elif git -C "$ROOT" worktree add -b "seat/$key" "$WT" main >>"$LOG" 2>&1; then
    c_ok "worktree on branch seat/$key"
  elif git -C "$ROOT" worktree add "$WT" "seat/$key" >>"$LOG" 2>&1; then
    c_ok "worktree on existing branch seat/$key"
  else
    fail_step "could not create the worktree for $name"
  fi
  lane=""
  case "$role" in pm|scrum-master|quality-engineer) ;; *) lane="seat:$key" ;; esac
  cat > "$WT/.env.local" <<ENV
# $name — per-seat env (gitignored; secrets like GH_TOKEN belong HERE, not in sdlc.config)
INSTANCE=$INSTANCE
SEAT_ROLE=$role
SEAT_NAME=$name
SEAT_MODEL=$model
GIT_USER_NAME="$GIT_USER_NAME"
GIT_USER_EMAIL="$GIT_USER_EMAIL"
AWS_PROFILE=$AWS_PROFILE
SEAT_LABEL=$lane
BOARD_ID=$BOARD_ID
BOARD_OWNER=$OWNER
ENV
  c_ok ".env.local written ($name / $role · model $model${lane:+ · lane $lane})"
  if ( cd "$WT" && . ./agentic-sdlc/onboarding/setup-seat.sh ) >>"$LOG" 2>&1; then
    c_ok "seat identity + SessionStart hook scaffolded"
  else
    c_warn "setup-seat.sh had trouble — run 'source ./agentic-sdlc/onboarding/setup-seat.sh' in the worktree (log: $LOG)"
  fi
  if bash "$HERE/make-launcher.sh" --worktree "$WT" --out "$APPS_DIR" >>"$LOG" 2>&1; then
    c_ok "launcher → $APPS_DIR/${key}.command"
  else
    c_warn "launcher step failed (log: $LOG)"
  fi
done

# ── 4b. operator slash-commands — EVERY launch path, not just the .app ────────
# (a bare `cd worktree && claude` must find /check too)
mkdir -p "$HOME/.claude/commands"
cp -f "$ROOT/agentic-sdlc/commands/"*.md "$HOME/.claude/commands/" 2>>"$LOG" \
  && c_ok "slash-commands installed (/check · /board · /workload · /backlog)" \
  || c_warn "couldn't install the slash-commands (log: $LOG)"

# ── 5. wrap launchers into macOS .app bundles (optional) ──────────────────────
if yes_p "$BUILD_APPS" && [ "$(uname)" = "Darwin" ]; then
  c_head "▶ Building double-clickable .app bundles"
  if bash "$HERE/build-apps.sh" --dir "$APPS_DIR" >>"$LOG" 2>&1; then
    c_ok "apps → $APPS_DIR/<Name>.app"
  else
    c_warn "app-build step failed (log: $LOG)"
  fi
fi

# ── 6. you're live ────────────────────────────────────────────────────────────
OWNER_TYPE="$(gh api "users/$OWNER" --jq .type 2>/dev/null || echo User)"
BOARD_PATH="users/$OWNER" ; [ "$OWNER_TYPE" = "Organization" ] && BOARD_PATH="orgs/$OWNER"
cat <<DONE

  ✓ Instance '$INSTANCE' is live.

    Config   $CONFIG   ← commit this (git add sdlc.config .claude CLAUDE.md .gitignore)
    Board    https://github.com/$BOARD_PATH/projects/${BOARD_ID:-<see-projects-tab>}
             $( [ -n "${GOLDEN_BOARD:-}" ] \
               && echo "(views + fields copied from golden board #$GOLDEN_BOARD — no UI step)" \
               || echo "(one-time, ~5 min, UI: apply the EPICS + Board views — the click-path is in workflow/project-boards.md; or set GOLDEN_BOARD in sdlc.config to copy a configured board next time)" )
    Seats    $SEATS
    Apps     $APPS_DIR/
    Start    open a seat (double-click its .app, or 'cd' its worktree and run
             'claude'), then type  /check  to pull the next work item.

  Next: $( yes_p "$SEED_EPIC" \
    && echo "run the guided first epic — /check in the PM seat frames it (onboarding/first-epic.md)." \
    || echo "frame your first epic — workflow/state-machine.md." )
DONE
