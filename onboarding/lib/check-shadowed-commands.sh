#!/usr/bin/env bash
#
# check-shadowed-commands.sh — name every personal command or skill that hides this instance's copy.
#
# Usage: check-shadowed-commands.sh <framework-dir> [home-dir]     (home-dir defaults to $HOME)
#
# Claude Code resolves a /name clash as "enterprise over personal, and personal over project", and a
# skill over a command file. So ~/.claude/commands/<name>.md or ~/.claude/skills/<name>/SKILL.md runs
# instead of the seat worktree's .claude/commands/<name>.md, for every instance on the machine, even
# when it happens to be identical today (#77). Older launchers copied the framework commands there.
#
# Prints one line per shadowing file: "<path> shadows this instance's /<name> (<how it compares>)".
# Exit: 0 nothing shadows · 1 at least one shadow · 2 input unreadable (no commands, no home dir)
set -uo pipefail

FW="${1:-}"; H="${2:-${HOME:-}}"
die(){ printf 'check-shadowed-commands: %s\n' "$1" >&2; exit 2; }

[ -n "$FW" ] || die "usage: check-shadowed-commands.sh <framework-dir> [home-dir]"
[ -d "$FW/commands" ] || die "no commands directory at $FW/commands"
[ -n "$H" ] && [ -d "$H" ] || die "home directory '${H}' does not exist"
shopt -s nullglob
FILES=("$FW"/commands/*.md)
[ "${#FILES[@]}" -gt 0 ] || die "no command files (*.md) in $FW/commands"

FOUND=0
for src in "${FILES[@]}"; do
  name="$(basename "$src" .md)"
  for personal in "$H/.claude/commands/$name.md" "$H/.claude/skills/$name/SKILL.md"; do
    [ -e "$personal" ] || continue
    if [ -f "$personal" ] && cmp -s "$src" "$personal"; then
      how="identical to this instance's copy today, and it still wins for every instance on this machine"
    else
      how="differs from this instance's copy"
    fi
    printf "%s shadows this instance's /%s (%s)\n" "$personal" "$name" "$how"
    FOUND=1
  done
done
exit "$FOUND"
