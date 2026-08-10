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

# 2. Cloud provider + GitHub for this session
[ -n "${GH_TOKEN:-}" ] && export GH_TOKEN

# 3. verify + report (provider-aware)
CLOUD_PROVIDER="${CLOUD_PROVIDER:-local}"
case "$CLOUD_PROVIDER" in
  aws)
    [ -n "${AWS_PROFILE:-}" ] && export AWS_PROFILE
    if [ -n "${AWS_PROFILE:-}" ]; then
      CLOUD_ID="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null \
                  || echo 'AWS creds NOT resolving — check AWS_PROFILE')"
    else
      CLOUD_ID="(no AWS_PROFILE set)"
    fi
    CLOUD_LABEL="aws    ${AWS_PROFILE:-—} → ${CLOUD_ID}"
    ;;
  gcp)
    export CLOUDSDK_CORE_PROJECT="${GCP_PROJECT:-}"
    CLOUD_ID="$(gcloud config get-value project 2>/dev/null || echo 'gcloud not configured — run: gcloud auth application-default login')"
    CLOUD_LABEL="gcp    ${GCP_PROJECT:-—} → ${CLOUD_ID} (${GCP_REGION:-region unset})"
    ;;
  azure)
    CLOUD_ID="$(az account show --query id -o tsv 2>/dev/null || echo 'az not configured — run: az login')"
    CLOUD_LABEL="azure  ${AZURE_SUBSCRIPTION:-—} → ${CLOUD_ID} (${AZURE_REGION:-region unset})"
    ;;
  local|*)
    COMPOSE="${DOCKER_COMPOSE_FILE:-docker-compose.yml}"
    if ! docker info >/dev/null 2>&1; then
      CLOUD_ID="Docker NOT running — start Docker Desktop first"
    elif [ -n "${DOCKER_REGISTRY_USER:-}" ] && [ -n "${DOCKER_REGISTRY_TOKEN:-}" ]; then
      echo "$DOCKER_REGISTRY_TOKEN" | docker login "${DOCKER_REGISTRY:-}" \
        --username "$DOCKER_REGISTRY_USER" --password-stdin >/dev/null 2>&1 \
        && CLOUD_ID="logged in to ${DOCKER_REGISTRY:-Docker Hub}" \
        || CLOUD_ID="docker login FAILED — check DOCKER_REGISTRY_USER / DOCKER_REGISTRY_TOKEN"
    else
      CLOUD_ID="${DOCKER_REGISTRY:-Docker Hub} (no registry credentials)"
    fi
    CLOUD_LABEL="local  ${COMPOSE} → ${CLOUD_ID}"
    ;;
esac

echo "✓ seat ready — ${SEAT_ROLE}/${SEAT_NAME}"
echo "    git:    $(git config --worktree user.name) <$(git config --worktree user.email)>"
echo "    cloud:  ${CLOUD_LABEL}"
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
  # If this instance belongs to a team fleet, append the fleet board so every
  # seat knows it exists (injected at scaffold time from TEAM_BOARD_URL in .env.local).
  if [ -n "${TEAM_BOARD_URL:-}" ]; then
    printf '\n## Fleet\n\nThis instance is part of a team fleet. The master board (epics across all instances, read-only context for this seat):\n%s\n' \
      "$TEAM_BOARD_URL" >> "$SEAT_FILE"
  fi
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
