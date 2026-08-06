#!/usr/bin/env bash
#
# squad-launch.sh — open every seat of an instance at once: one agterm workspace,
# or plain Terminal windows when agterm is not installed.
#
# The runtime behind the generated squad.command (make-launcher.sh emits that shim
# next to the per-seat launchers; all logic lives here, so /update propagates fixes).
# Seats are DISCOVERED from the *.command launchers in --dir and their worktrees'
# .env.local — never hardcoded — and open ordered by the SDLC chain:
#
#     PM  →  Engineer(s)  →  Quality  →  Scrum-Master
#     frame    build          verify      merge
#
# so reading the sidebar top-to-bottom is reading the 4-eye chain in the direction
# work actually flows.
#
# agterm mode is re-run clean: agterm RESTORES workspaces (and their seats) on
# relaunch, and --create-workspace REUSES a live workspace by name — so a re-run
# would stack a second copy of every seat on top of the restored ones. Any workspace
# already named after this instance is therefore wiped first (deleted, or emptied
# when it is a window's last workspace — agterm keeps at least one per window).
#
# Each seat is launched through a login shell: agterm runs --command programs with
# the app's GUI PATH, which usually lacks the operator's package manager (Homebrew,
# nvm, …) and would kill seat-launch.sh at `exec claude` with "command not found".
#
# Usage:   squad-launch.sh [--dir <dir-with-seat-.commands>]     (default: cwd)
# Needs:   jq for the stale-workspace lookup (already a framework prerequisite);
#          without it the wipe is skipped with a warning, everything else works.
#
set -euo pipefail

DIR="$PWD"
while [ $# -gt 0 ]; do case "$1" in
  --dir) DIR="$2"; shift 2 ;;
  *) echo "squad-launch: unknown arg: $1 (usage: squad-launch.sh [--dir DIR])" >&2; exit 1 ;;
esac; done
DIR="$(cd "$DIR" && pwd)"
WS="$(basename "$DIR")"

# ── discover seats from the sibling per-seat launchers ───────────────────────
# rank = SDLC flow position; anything unknown sorts last but still opens.
rank_of() { case "$1" in
  pm) echo 10 ;; architect) echo 20 ;; engineer) echo 30 ;;
  data-*|cloud-architect) echo 40 ;; quality-engineer) echo 50 ;;
  scrum-master) echo 60 ;; auditor) echo 70 ;; *) echo 90 ;;
esac; }

ROWS=()
for f in "$DIR"/*.command; do
  [ -e "$f" ] || continue
  [ "$(basename "$f")" = "squad.command" ] && continue
  wt="$(grep -o -- '--worktree "[^"]*"' "$f" 2>/dev/null | head -1 | sed 's/--worktree "//;s/"$//')"
  [ -n "$wt" ] && [ -f "$wt/.env.local" ] || { echo "  ⚠ skip $(basename "$f" .command) — no worktree/.env.local"; continue; }
  role="$(grep -E '^SEAT_ROLE=' "$wt/.env.local" | head -1 | cut -d= -f2- | tr -d '"'"'"' ')"
  name="$(grep -E '^SEAT_NAME=' "$wt/.env.local" | head -1 | cut -d= -f2- | tr -d '"'"'"' ')"
  [ -n "$role" ] || continue
  # Display name. Acronym roles stay upper-case (PM, QA); the rest title-case.
  # When SEAT_NAME is absent or just restates the role, show the role alone.
  case "$role" in
    pm) pretty="PM" ;;
    quality-engineer) pretty="QA" ;;
    scrum-master) pretty="SM" ;;
    *) pretty="$(printf '%s' "$role" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')" ;;
  esac
  lname="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  lrole="$(printf '%s' "$role" | tr '[:upper:]' '[:lower:]')"
  if [ -z "$name" ] || [ "$lname" = "$lrole" ]; then disp="$pretty"; else disp="$pretty — $name"; fi
  ROWS+=("$(rank_of "$role")|$disp|$wt|$f")
done
[ ${#ROWS[@]} -gt 0 ] || { echo "✗ no seat launchers (*.command with --worktree) in $DIR" >&2; exit 1; }
sorted() { printf '%s\n' "${ROWS[@]}" | sort -t'|' -k1,1n; }

# ── find agterm; without it, fall back to one Terminal window per seat ───────
CTL="$(command -v agtermctl || true)"
[ -n "$CTL" ] || { [ -x "/Applications/agterm.app/Contents/MacOS/agtermctl" ] \
  && CTL="/Applications/agterm.app/Contents/MacOS/agtermctl" || true; }

if [ -z "$CTL" ]; then
  echo "▸ $WS — agterm not found; opening ${#ROWS[@]} seats as separate Terminal windows"
  while IFS='|' read -r _rank disp _wt launcher; do
    open "$launcher" && printf '   ✓ %s\n' "$disp"
  done < <(sorted)
  exit 0
fi

open -ga agterm 2>/dev/null || true
for _ in $(seq 1 25); do "$CTL" tree >/dev/null 2>&1 && break; sleep 0.2; done
"$CTL" tree >/dev/null 2>&1 || { echo "✗ agterm is not answering on its control socket." >&2; exit 1; }

# ── clean slate: wipe any stale workspace with this instance's name ──────────
if command -v jq >/dev/null 2>&1; then
  while IFS='|' read -r wsid sids; do
    [ -n "$wsid" ] || continue
    if "$CTL" workspace delete --target "$wsid" >/dev/null 2>&1; then
      echo "  ↺ removed stale \"$WS\" workspace"
    elif [ -n "$sids" ]; then
      close=( session close ); for sid in $sids; do close+=( --target "$sid" ); done
      "$CTL" "${close[@]}" >/dev/null 2>&1 || true
      echo "  ↺ emptied stale \"$WS\" workspace (last in its window — reusing it)"
    fi
  done < <("$CTL" tree --json 2>/dev/null \
    | jq -r --arg ws "$WS" '.result.tree.workspaces[]? | select(.name == $ws)
                            | .id + "|" + ([.sessions[]?.id] | join(" "))' 2>/dev/null || true)
else
  echo "  ⚠ jq not found — skipping stale-workspace cleanup (re-runs may duplicate seats)"
fi

# ── open the workspace, one session per seat, in flow order ──────────────────
echo "▸ $WS — opening ${#ROWS[@]} seats in SDLC flow order"
first=1
while IFS='|' read -r _rank disp wt launcher; do
  # login shell (the operator's own) so the seat sees the real PATH, then exec the launcher
  args=( session new --cwd "$wt" --name "$disp"
         --workspace-name "$WS" --create-workspace
         --command "${SHELL:-/bin/zsh} -lc 'exec \"$launcher\"'" --wait )
  [ $first -eq 1 ] || args+=( --no-select )
  if "$CTL" "${args[@]}" >/dev/null 2>&1; then
    printf '   ✓ %s\n' "$disp"
  else
    printf '   ✗ %s  (session new failed)\n' "$disp"
  fi
  first=0
done < <(sorted)

# ── make the squad legible ───────────────────────────────────────────────────
"$CTL" sidebar visibility show >/dev/null 2>&1 || true
"$CTL" sidebar mode tree       >/dev/null 2>&1 || true
"$CTL" sidebar expand          >/dev/null 2>&1 || true

cat <<EOF

  ${WS} squad is up. Useful from any terminal:

    agtermctl session go next-attention   jump to the seat that wants you
    agtermctl tree                        who exists, who is where
    agtermctl dashboard --mru             view-only grid of live seats

  Seat cadence is unchanged and still operator-driven:
    /board   glance      →   /check   drain that seat   →   it stops at empty
EOF
