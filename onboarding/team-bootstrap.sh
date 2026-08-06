#!/usr/bin/env bash
#
# team-bootstrap.sh — fleet-level setup: one master board across all developer instances.
#
# Run ONCE by the team lead, after each developer has self-provisioned their own
# instance (vendor-framework.sh + bootstrap.sh). It:
#   1. Creates an org-level Fleet project (epics-only master board).
#   2. Links every product repo to it (so repo epics appear on the fleet board).
#   3. Injects TEAM_BOARD_URL into each local repo's sdlc.config.
#   4. Prints re-run instructions so bootstrap propagates TEAM_BOARD_URL to
#      every seat's .env.local (and hence into every session's context).
#
# Usage:
#   bash agentic-sdlc/onboarding/team-bootstrap.sh [--config <path>]
#
# Reads team.config in the current directory by default (see team.config.example).
# Requires: gh (authenticated, `project` scope) · node · jq.
#
# Idempotent: re-running after adding a new developer repo just links the new
# repo and updates TEAM_BOARD_URL in that repo's sdlc.config.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="team.config"
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    *) echo "unknown arg: $1 (usage: team-bootstrap.sh [--config <path>])" >&2; exit 1 ;;
  esac
done

[ -f "$CONFIG" ] || {
  echo "✗ no team.config found (looked for: $CONFIG)" >&2
  echo "  copy onboarding/team.config.example → team.config and fill it in." >&2
  exit 1
}

# shellcheck source=/dev/null
. "$CONFIG"

ORG="${ORG:-}"
FLEET_TITLE="${FLEET_TITLE:-Fleet — Epics}"
FLEET_GOLDEN_BOARD="${FLEET_GOLDEN_BOARD:-}"
REPOS="${REPOS:-}"
LOCAL_REPOS="${LOCAL_REPOS:-}"

[ -n "$ORG" ]   || { echo "✗ team.config: ORG must be set" >&2; exit 1; }
[ -n "$REPOS" ] || { echo "✗ team.config: REPOS must be set (space-separated owner/repo list)" >&2; exit 1; }

LOG="$(mktemp -t sdlc-team.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

c_head(){ printf '\n\033[1;36m%s\033[0m\n' "$*"; }
c_ok(){   printf '  \033[32m✓\033[0m %s\n' "$*"; }
c_info(){ printf '  %s\n' "$*"; }
c_warn(){ printf '  \033[33m⚠ %s\033[0m\n' "$*"; }
die(){    printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; echo "  log: $LOG" >&2; exit 1; }

c_head "▶ Agentic SDLC — fleet bootstrap"
c_info "org:   $ORG"
c_info "board: $FLEET_TITLE"
c_info "repos: $REPOS"

# ── 0. preflight ──────────────────────────────────────────────────────────────
c_head "▶ Preflight"
for bin in gh node jq; do
  command -v "$bin" >/dev/null 2>&1 || die "$bin not found — install it first."
done
gh auth status >>"$LOG" 2>&1 || die "gh is not authenticated — run 'gh auth login'."
gh api graphql -f query='{viewer{projectsV2(first:1){totalCount}}}' >>"$LOG" 2>&1 \
  || die "gh token cannot reach Projects v2 (missing 'project' scope?) — run: gh auth refresh -s project"
for repo in $REPOS; do
  gh repo view "$repo" >>"$LOG" 2>&1 || die "repo '$repo' not accessible — check the name and your gh auth."
done
c_ok "preflight passed"

# ── 1. fleet board — create or reuse ─────────────────────────────────────────
c_head "▶ Fleet board"
OWNER_TYPE="$(gh api "users/$ORG" --jq .type 2>/dev/null || echo User)"
BOARD_PATH="users/$ORG"; [ "$OWNER_TYPE" = "Organization" ] && BOARD_PATH="orgs/$ORG"

# Reuse if a project with the same title already exists under this owner.
FLEET_NUM="$(gh project list --owner "$ORG" --format json --limit 50 2>/dev/null \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      const ps=(JSON.parse(s).projects||[]);
      const t=process.env.FLEET_TITLE;
      const m=ps.find(p=>p.title===t);
      console.log(m?m.number:"");})' 2>/dev/null || true)" FLEET_TITLE="$FLEET_TITLE"

if [ -n "$FLEET_NUM" ]; then
  c_ok "fleet board already exists — reusing project #$FLEET_NUM"
else
  TEMPLATE="$HERE/../workflow/project-templates/fleet-board.json"
  if [ -n "$FLEET_GOLDEN_BOARD" ]; then
    bash "$HERE/setup-board.sh" \
      --owner "$ORG" --title "$FLEET_TITLE" --copy-from "$FLEET_GOLDEN_BOARD" \
      >>"$LOG" 2>&1 || die "failed to copy fleet board from #$FLEET_GOLDEN_BOARD (log: $LOG)"
  else
    bash "$HERE/setup-board.sh" \
      --owner "$ORG" --title "$FLEET_TITLE" --template "$TEMPLATE" \
      >>"$LOG" 2>&1 || die "failed to create fleet board (log: $LOG)"
  fi
  FLEET_NUM="$(gh project list --owner "$ORG" --format json --limit 50 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
        const ps=(JSON.parse(s).projects||[]);
        const t=process.env.FLEET_TITLE;
        const m=ps.find(p=>p.title===t);
        console.log(m?m.number:"");})' 2>/dev/null || true)" FLEET_TITLE="$FLEET_TITLE"
  [ -n "$FLEET_NUM" ] || die "fleet board created but number not found — check $BOARD_PATH/projects"
  c_ok "fleet board created — project #$FLEET_NUM"
fi

FLEET_URL="https://github.com/$BOARD_PATH/projects/$FLEET_NUM"

# ── 2. link repos to the fleet board ─────────────────────────────────────────
c_head "▶ Linking repos"
for repo in $REPOS; do
  gh project link "$FLEET_NUM" --owner "$ORG" --repo "$repo" >>"$LOG" 2>&1 \
    && c_ok "linked $repo" \
    || c_warn "could not link $repo (may already be linked, or check project scope)"
done

# ── 3. inject TEAM_BOARD_URL into each local sdlc.config ─────────────────────
c_head "▶ Injecting TEAM_BOARD_URL"
if [ -z "$LOCAL_REPOS" ]; then
  c_warn "LOCAL_REPOS not set — skipping sdlc.config injection; add TEAM_BOARD_URL=\"$FLEET_URL\" to each repo's sdlc.config manually, then re-run bootstrap.sh --yes."
else
  read -r -a local_arr <<< "$LOCAL_REPOS"
  for local_repo in "${local_arr[@]}"; do
    cfg="$local_repo/sdlc.config"
    if [ ! -f "$cfg" ]; then
      c_warn "$cfg not found — skipping (add TEAM_BOARD_URL=\"$FLEET_URL\" manually)"
      continue
    fi
    if grep -q "^TEAM_BOARD_URL=" "$cfg" 2>/dev/null; then
      # Update existing entry.
      sed -i.bak "s|^TEAM_BOARD_URL=.*|TEAM_BOARD_URL=\"$FLEET_URL\"|" "$cfg" \
        && rm -f "${cfg}.bak"
      c_ok "$cfg — TEAM_BOARD_URL updated"
    else
      printf '\n# Fleet master board (epics across all instances — set by team-bootstrap.sh)\nTEAM_BOARD_URL="%s"\n' \
        "$FLEET_URL" >> "$cfg"
      c_ok "$cfg — TEAM_BOARD_URL injected"
    fi
  done
fi

# ── 4. summary ────────────────────────────────────────────────────────────────
cat <<DONE

  ✓ Fleet is live.

    Board   $FLEET_URL
            $( [ -n "$FLEET_GOLDEN_BOARD" ] \
              && echo "(views + fields copied from #$FLEET_GOLDEN_BOARD — no UI step)" \
              || echo "(one-time, ~3 min: apply the EPICS view — label:level:epic filter +
              Repository + Sub-issues progress + Owner + Target fields; workflow/project-boards.md)" )

    Next    Re-run bootstrap.sh --yes in each product repo so TEAM_BOARD_URL
            propagates to every seat's .env.local (and into each session's context):

DONE

read -r -a local_arr <<< "$LOCAL_REPOS"
for local_repo in "${local_arr[@]-}"; do
  [ -n "$local_repo" ] && printf '              cd %s && bash agentic-sdlc/onboarding/bootstrap.sh --yes\n' "$local_repo"
done

printf '\n    Once done, every seat in every instance knows the fleet board exists.\n\n'
