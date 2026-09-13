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

# 5. native start — wire the seat's local Claude Code settings idempotently
#    (gitignored .claude/settings.local.json): the SessionStart hook that
#    injects the seat identity, the auto-compact-window / claude.ai-connector
#    defaults, a statusline showing context usage + cost, and the
#    ScheduleWakeup/CronCreate permission denial (this framework is
#    operator-driven — see MODES.md — so no seat gets tools that self-
#    schedule). Every write below is idempotent: running this script twice
#    produces a byte-identical file, and a key this script doesn't own
#    (permissions.allow, any other hook) is read back untouched (#76 AC4).
if command -v jq >/dev/null 2>&1; then
  SETTINGS="$ROOT/.claude/settings.local.json"
  mkdir -p "$ROOT/.claude"
  [ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"

  # 5a. SessionStart seat-brief hook — REPLACED, never appended. Matches on
  # the `-seat.md` cat pattern regardless of which instance name (or a
  # historical, unexpanded literal `${INSTANCE}` left by a past bug in this
  # very script) produced it, so a settings file already carrying N stale
  # duplicates self-heals to exactly one entry on the very next run, instead
  # of growing a 12th-to-19th copy (the incident #76 AC4 exists to fix).
  # ${INSTANCE} must expand NOW — a bare `claude` launched later has no such
  # env var — only $CLAUDE_PROJECT_DIR stays literal for Claude Code to
  # expand at runtime.
  _hook_cmd="cat \"\$CLAUDE_PROJECT_DIR/.${INSTANCE}-seat.md\" 2>/dev/null || true"
  _tmp="$(mktemp)"
  jq --arg cmd "$_hook_cmd" '
    .hooks.SessionStart = (
      ((.hooks.SessionStart // [])
        | map(select((.hooks // []) | any(.command? // "" | test("-seat\\.md")) | not))
      ) + [{"hooks":[{"type":"command","command":$cmd}]}]
    )
  ' "$SETTINGS" > "$_tmp" && mv "$_tmp" "$SETTINGS"
  echo "    hook:   SessionStart → injects .${INSTANCE}-seat.md (wired, deduped)"

  # 5b. autoCompactWindow — Claude Code 2.1.x accepts only an integer in
  # [100000, 1000000] and SILENTLY IGNORES anything else (no error, no log),
  # so a bad override must never reach the file: that would degrade to "the
  # setting quietly did nothing," a worse failure than refusing it here,
  # loudly, before it's written. A valid in-range override is honoured.
  AUTO_COMPACT_WINDOW="${AUTO_COMPACT_WINDOW:-250000}"
  case "$AUTO_COMPACT_WINDOW" in
    ''|*[!0-9]*)
      echo "    settings: ⚠ AUTO_COMPACT_WINDOW='$AUTO_COMPACT_WINDOW' is not an integer — refusing it, using default 250000"
      AUTO_COMPACT_WINDOW=250000
      ;;
  esac
  if [ "$AUTO_COMPACT_WINDOW" -lt 100000 ] || [ "$AUTO_COMPACT_WINDOW" -gt 1000000 ]; then
    echo "    settings: ⚠ AUTO_COMPACT_WINDOW=$AUTO_COMPACT_WINDOW is outside Claude Code's accepted [100000, 1000000] range — refusing it, using default 250000"
    AUTO_COMPACT_WINDOW=250000
  fi

  # 5c. disableClaudeAiConnectors — default true (a seat worktree has no
  # business auto-fetching claude.ai cloud MCP connectors); overridable per
  # seat via .env.local.
  DISABLE_CLAUDE_AI_CONNECTORS="${DISABLE_CLAUDE_AI_CONNECTORS:-true}"
  case "$DISABLE_CLAUDE_AI_CONNECTORS" in
    true|false) ;;
    *)
      echo "    settings: ⚠ DISABLE_CLAUDE_AI_CONNECTORS='$DISABLE_CLAUDE_AI_CONNECTORS' is not true/false — using default true"
      DISABLE_CLAUDE_AI_CONNECTORS=true
      ;;
  esac

  _tmp="$(mktemp)"
  jq --argjson window "$AUTO_COMPACT_WINDOW" --argjson noConnectors "$DISABLE_CLAUDE_AI_CONNECTORS" '
    .autoCompactWindow = $window
    | .disableClaudeAiConnectors = $noConnectors
  ' "$SETTINGS" > "$_tmp" && mv "$_tmp" "$SETTINGS"
  echo "    settings: autoCompactWindow=${AUTO_COMPACT_WINDOW} disableClaudeAiConnectors=${DISABLE_CLAUDE_AI_CONNECTORS}"

  # 5d. statusline — context-window usage + session cost, so a seat always
  # sees how close it is to compacting without running /context by hand.
  # Path resolved relative to $CLAUDE_PROJECT_DIR when the framework lives
  # under this worktree (the common case), else the absolute $FW path — same
  # "resolve now, $CLAUDE_PROJECT_DIR stays literal" split as 5a.
  case "$FW" in
    "$ROOT"/*) _fw_for_hook="\$CLAUDE_PROJECT_DIR/${FW#"$ROOT"/}" ;;
    *) _fw_for_hook="$FW" ;;
  esac
  _statusline_cmd="bash \"${_fw_for_hook}/onboarding/lib/seat-statusline.sh\""
  _tmp="$(mktemp)"
  jq --arg cmd "$_statusline_cmd" '.statusLine = {"type":"command","command":$cmd}' \
    "$SETTINGS" > "$_tmp" && mv "$_tmp" "$SETTINGS"
  echo "    statusline: context tokens + cost (wired)"

  # 5e. deny ScheduleWakeup/CronCreate — this framework is operator-driven
  # (MODES.md): no seat self-schedules or self-loops, so these tools are
  # removed from every seat's context entirely rather than merely gated. A
  # BARE tool name (not "ScheduleWakeup(*)") is what removes a tool outright
  # per Claude Code's own permission-rule syntax; a scoped rule would leave
  # the tool visible and only block matching calls. `unique` sorts the
  # merged array — deterministic (idempotent) rather than insertion-order-
  # preserving — and any other existing deny/allow/ask entry is carried
  # through untouched.
  _tmp="$(mktemp)"
  jq '.permissions.deny = (((.permissions.deny // []) + ["ScheduleWakeup", "CronCreate"]) | unique)' \
    "$SETTINGS" > "$_tmp" && mv "$_tmp" "$SETTINGS"
  echo "    permissions: ScheduleWakeup + CronCreate denied"
else
  echo "    hook:   ⚠ jq not found — wire the SessionStart hook manually (see new-pair-setup.md)"
fi
