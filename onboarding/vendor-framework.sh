#!/usr/bin/env bash
#
# vendor-framework.sh — take the framework into a product repo (the missing
# first step of "Fork it"). Run FROM a clone of the framework repo:
#
#   bash onboarding/vendor-framework.sh --into ~/Code/my-product
#
# What it does:
#   • creates <product> if needed (and `git init -b main`s it if it isn't a repo)
#   • copies the framework's tracked files → <product>/agentic-sdlc/  (no .git,
#     no local cruft — exactly what the repo ships)
#   • stamps a root CLAUDE.md (auto-loaded by Claude Code) if the product has none
#
# Then, inside the product repo, one command stands up the whole instance:
#
#   cd ~/Code/my-product
#   git add -A && git commit -m "chore(sdlc): vendor agentic-sdlc framework"
#   bash agentic-sdlc/onboarding/bootstrap.sh
#
# Re-running refreshes agentic-sdlc/ in place (adopt a newer framework version).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"      # <framework>/onboarding
FW="$(cd "$HERE/.." && pwd)"                              # the framework root

INTO=""
while [ $# -gt 0 ]; do case "$1" in
  --into) INTO="$2"; shift 2 ;;
  *) echo "unknown arg: $1 (usage: vendor-framework.sh --into <product-repo-dir>)" >&2; exit 1 ;;
esac; done
[ -n "$INTO" ] || { echo "usage: vendor-framework.sh --into <product-repo-dir>" >&2; exit 1; }

mkdir -p "$INTO"
INTO="$(cd "$INTO" && pwd)"
[ "$INTO" = "$FW" ] && { echo "✗ --into points at the framework repo itself — point it at your product repo" >&2; exit 1; }

# a git repo to land in (init if new)
if ! git -C "$INTO" rev-parse --show-toplevel >/dev/null 2>&1; then
  git -C "$INTO" init -b main >/dev/null
  echo "✓ git repo initialised at $INTO"
fi

# copy the framework's TRACKED files → <product>/agentic-sdlc/ (clean vendor;
# falls back to a filtered tar copy when run from a non-git download)
mkdir -p "$INTO/agentic-sdlc"
if git -C "$FW" rev-parse HEAD >/dev/null 2>&1; then
  git -C "$FW" archive HEAD | tar -x -C "$INTO/agentic-sdlc"
else
  tar -C "$FW" --exclude .git --exclude .env.local --exclude '.DS_Store' -cf - . \
    | tar -x -C "$INTO/agentic-sdlc"
fi
echo "✓ framework vendored → $INTO/agentic-sdlc/"

# root CLAUDE.md — the file every Claude Code session auto-loads
if [ ! -f "$INTO/CLAUDE.md" ]; then
  cp "$HERE/CLAUDE.template.md" "$INTO/CLAUDE.md"
  echo "✓ CLAUDE.md stamped at the product root (edit the product-context section)"
else
  echo "· CLAUDE.md already present (kept)"
fi

cat <<NEXT

  Next:
    cd $INTO
    git add -A && git commit -m "chore(sdlc): vendor agentic-sdlc framework"
    bash agentic-sdlc/onboarding/bootstrap.sh     # stands up the whole instance
NEXT
