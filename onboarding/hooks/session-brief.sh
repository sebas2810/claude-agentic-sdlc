#!/usr/bin/env bash
#
# session-brief.sh — plugin SessionStart hook: inject this worktree's seat brief
# (.<instance>-seat.md, scaffolded by setup-seat.sh) into every session.
#
# Replaces the per-worktree settings.local.json surgery: the hook travels with
# the plugin and works on every Claude Code surface (terminal, desktop app,
# web, IDE); the brief itself stays per-worktree and gitignored. Outside a seat
# worktree (no .env.local) it stays silent — the plugin is inert there.
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
ENV_FILE="$ROOT/.env.local"
[ -f "$ENV_FILE" ] || exit 0
INSTANCE="$(sed -n 's/^INSTANCE=//p' "$ENV_FILE" | head -1 | tr -d '"')"
[ -n "$INSTANCE" ] || exit 0
cat "$ROOT/.${INSTANCE}-seat.md" 2>/dev/null || true
# model tier — configured per seat in sdlc.config, applied by seat-launch.sh in
# the terminal (--model); surfaced here so a desktop-app/web/IDE session knows
# what tier this seat is meant to run (pick it in the UI there).
MODEL="$(sed -n 's/^SEAT_MODEL=//p' "$ENV_FILE" | head -1 | tr -d '"')"
[ -n "$MODEL" ] && printf '\nSeat model tier: %s (terminal launches pass --model %s; in the desktop app / web / IDE, select this tier in the UI).\n' "$MODEL" "$MODEL"
exit 0
