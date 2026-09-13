#!/usr/bin/env bash
#
# install-seat-commands.sh — give ONE seat worktree its own instance's slash-commands.
#
# Usage: install-seat-commands.sh <framework-dir> <seat-worktree>
#
# Copies <framework-dir>/commands/*.md into <seat-worktree>/.claude/commands/ (project scope), so
# each instance's seats run that instance's /check. It never writes ~/.claude/commands. Claude Code
# runs a personal command over a project command of the same name, so one machine-global copy let
# the last instance launched decide /check for every instance on the machine (#77).
#
# Installed files stay out of `git status` through the repository's info/exclude (local to the
# clone, shared by all its worktrees), never through a tracked .gitignore edit. A command file the
# repository TRACKS under the same name is the product's own: it is left untouched and named.
#
# Exit: 0 every command installed (or already current)
#       2 input unreadable: no commands to copy, no worktree, or a file could not be written
#       3 a tracked file of the same name holds other content (left untouched, named on stderr)
set -uo pipefail

FW="${1:-}"; WT="${2:-}"
die(){ printf 'install-seat-commands: %s\n' "$1" >&2; exit 2; }

[ -n "$FW" ] && [ -n "$WT" ] || die "usage: install-seat-commands.sh <framework-dir> <seat-worktree>"
SRC="$FW/commands"
[ -d "$SRC" ] || die "no commands directory at $SRC"
[ -d "$WT" ]  || die "seat worktree $WT does not exist"
shopt -s nullglob
FILES=("$SRC"/*.md)
[ "${#FILES[@]}" -gt 0 ] || die "no command files (*.md) in $SRC"

DEST="$WT/.claude/commands"
mkdir -p "$DEST" || die "cannot create $DEST"

EXCLUDE="" ; PREFIX=""
if git -C "$WT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  PREFIX="$(git -C "$WT" rev-parse --show-prefix)" || die "cannot resolve $WT inside its repository"
  EXCLUDE="$(git -C "$WT" rev-parse --git-path info/exclude)" || die "cannot resolve info/exclude for $WT"
  case "$EXCLUDE" in /*) ;; *) EXCLUDE="$WT/$EXCLUDE" ;; esac
  mkdir -p "$(dirname "$EXCLUDE")" || die "cannot create $(dirname "$EXCLUDE")"
fi

STATUS=0 ; N=0
for src in "${FILES[@]}"; do
  name="$(basename "$src")"
  dest="$DEST/$name"
  [ -r "$src" ] || die "cannot read $src"
  if [ -n "$EXCLUDE" ] && git -C "$WT" ls-files --error-unmatch ".claude/commands/$name" >/dev/null 2>&1; then
    if ! cmp -s "$src" "$dest"; then
      printf 'install-seat-commands: %s is tracked by this repository and differs from the framework copy; left untouched (rename it to get the framework /%s)\n' \
        "$dest" "${name%.md}" >&2
      STATUS=3
    else
      N=$((N + 1))
    fi
    continue
  fi
  if ! cmp -s "$src" "$dest"; then
    tmp="$(mktemp "$DEST/.${name}.XXXXXX")" || die "cannot write in $DEST"
    if ! { cp "$src" "$tmp" && mv -f "$tmp" "$dest"; }; then
      rm -f "$tmp"
      die "cannot install $dest"
    fi
  fi
  if [ -n "$EXCLUDE" ]; then
    pattern="/${PREFIX}.claude/commands/$name"
    grep -qxF "$pattern" "$EXCLUDE" 2>/dev/null || printf '%s\n' "$pattern" >> "$EXCLUDE" || die "cannot write $EXCLUDE"
  fi
  N=$((N + 1))
done

printf 'install-seat-commands: %d command(s) current in %s\n' "$N" "$DEST"
exit "$STATUS"
