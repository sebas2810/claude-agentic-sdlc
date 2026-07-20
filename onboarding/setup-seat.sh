#!/usr/bin/env bash
# Configure THIS worktree as an isolated seat. Run from the worktree root:
#   source ./agentic-sdlc/onboarding/setup-seat.sh
# It sets a per-worktree git identity and exports AWS/GitHub creds for the session.
set -uo pipefail
ENV_FILE="$(git rev-parse --show-toplevel)/.env.local"
[ -f "$ENV_FILE" ] || { echo "✗ no .env.local — copy agentic-sdlc/onboarding/.env.local.example → .env.local and fill it in"; return 1 2>/dev/null || exit 1; }
set -a; . "$ENV_FILE"; set +a
INSTANCE="${INSTANCE:-seat}"   # seat-file + overlay name (set in .env.local, e.g. sammy)

# 1. per-worktree git identity (extensions.worktreeConfig avoids leaking to other seats)
git config extensions.worktreeConfig true
git config --worktree user.name  "$GIT_USER_NAME"
git config --worktree user.email "$GIT_USER_EMAIL"

# 2. AWS + GitHub for this session (AWS only when the seat actually has a profile)
[ -n "${AWS_PROFILE:-}" ] && export AWS_PROFILE
[ -n "${GH_TOKEN:-}" ] && export GH_TOKEN

# 3. verify + report
if [ -n "${AWS_PROFILE:-}" ]; then
  AWS_ID="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo 'AWS creds NOT resolving — check AWS_PROFILE')"
else
  AWS_ID="(no AWS_PROFILE — skipped)"
fi
echo "✓ seat ready — ${SEAT_ROLE}/${SEAT_NAME}"
echo "    git:    $(git config --worktree user.name) <$(git config --worktree user.email)>"
echo "    aws:    ${AWS_PROFILE:-—} → ${AWS_ID}"
echo "    github: ${GH_TOKEN:+custom token}${GH_TOKEN:-default gh login}"

# 4. native start — scaffold this seat's identity file from its role template
#    (per-worktree, gitignored). Update its steer line when you pick up an EPIC.
ROOT="$(git rev-parse --show-toplevel)"
SEAT_FILE="$ROOT/.${INSTANCE}-seat.md"
# Locate the framework wherever it is vendored: SDLC_FRAMEWORK_DIR wins (set by seat-launch.sh),
# else the conventional in-repo overlay. Lets the role template resolve under docs/agentic-sdlc/ too.
FW="${SDLC_FRAMEWORK_DIR:-$ROOT/agentic-sdlc}"
TEMPLATE="$FW/onboarding/seat.${SEAT_ROLE}.template.md"
if [ -f "$SEAT_FILE" ]; then
  echo "    seat:   .${INSTANCE}-seat.md present (kept)"
elif [ -f "$TEMPLATE" ]; then
  sed -e "s/<NAME>/${SEAT_NAME}/g" -e "s/<ROLE>/${SEAT_ROLE}/g" "$TEMPLATE" > "$SEAT_FILE"
  echo "    seat:   .${INSTANCE}-seat.md scaffolded (${SEAT_ROLE}) — set its steer line to your EPIC"
else
  echo "    seat:   ⚠ no template for role '${SEAT_ROLE}' ($TEMPLATE)"
fi

# 5. native start — wire a SessionStart hook so the seat identity is injected
#    into every Claude session in this worktree (gitignored settings.local.json).
if command -v jq >/dev/null 2>&1; then
  SETTINGS="$ROOT/.claude/settings.local.json"
  mkdir -p "$ROOT/.claude"
  [ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
  if grep -q "${INSTANCE}-seat\.md" "$SETTINGS" 2>/dev/null; then
    echo "    hook:   SessionStart already wired"
  else
    # ${INSTANCE} must expand NOW (a bare `claude` launched later has no such
    # env var — the stored hook must hardcode the real filename); only
    # $CLAUDE_PROJECT_DIR stays literal for Claude Code to expand at runtime.
    _hook_cmd="cat \"\$CLAUDE_PROJECT_DIR/.${INSTANCE}-seat.md\" 2>/dev/null || true"
    _tmp="$(mktemp)"
    jq --arg cmd "$_hook_cmd" \
      '.hooks.SessionStart = ((.hooks.SessionStart // []) + [{"hooks":[{"type":"command","command":$cmd}]}])' \
      "$SETTINGS" > "$_tmp" && mv "$_tmp" "$SETTINGS"
    echo "    hook:   SessionStart → injects .${INSTANCE}-seat.md (wired)"
  fi
else
  echo "    hook:   ⚠ jq not found — wire the SessionStart hook manually (see new-pair-setup.md)"
fi
