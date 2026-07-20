#!/usr/bin/env bash
#
# vendor-framework.sh — take the framework into a product repo (the missing
# first step of "Fork it"). Run FROM a clone of the framework repo:
#
#   bash onboarding/vendor-framework.sh --into ~/Code/my-product
#   bash onboarding/vendor-framework.sh --into ~/Code/my-product --repo <you>/my-product
#
# What it does:
#   • creates <product> if needed (and `git init -b main`s it if it isn't a repo)
#   • copies the framework's tracked files → <product>/agentic-sdlc/  (no .git,
#     no local cruft — exactly what the repo ships)
#   • stamps a root CLAUDE.md (auto-loaded by Claude Code) if the product has none
#   • with --repo <owner/name>: commits the vendor and PUBLISHES the repo to
#     GitHub (private by default; --public to flip) — bootstrap needs the repo
#     to exist on GitHub, because the labels, issues, and board live there.
#     Requires `gh auth login` done and a git identity
#     (git config --global user.name / user.email) set.
#
# Then, inside the product repo, one command stands up the whole instance:
#
#   cd ~/Code/my-product
#   bash agentic-sdlc/onboarding/bootstrap.sh
#
# Re-running refreshes agentic-sdlc/ in place (adopt a newer framework version).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"      # <framework>/onboarding
FW="$(cd "$HERE/.." && pwd)"                              # the framework root

INTO="" ; REPO="" ; VISIBILITY="--private"
while [ $# -gt 0 ]; do case "$1" in
  --into)   INTO="$2"; shift 2 ;;
  --repo)   REPO="$2"; shift 2 ;;
  --public) VISIBILITY="--public"; shift ;;
  *) echo "unknown arg: $1 (usage: vendor-framework.sh --into <product-repo-dir> [--repo <owner/name>] [--public])" >&2; exit 1 ;;
esac; done
[ -n "$INTO" ] || { echo "usage: vendor-framework.sh --into <product-repo-dir> [--repo <owner/name>] [--public]" >&2; exit 1; }

if [ -n "$REPO" ]; then
  command -v gh >/dev/null 2>&1 || { echo "✗ --repo needs the gh CLI — install it and run 'gh auth login' first" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "✗ gh is not authenticated — run 'gh auth login' first" >&2; exit 1; }
  git config --get user.name >/dev/null 2>&1 && git config --get user.email >/dev/null 2>&1 \
    || { echo "✗ no git identity — set it first:  git config --global user.name \"Your Name\" && git config --global user.email you@example.com" >&2; exit 1; }
fi

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

# root .gitignore — the seat env/identity files land at the PRODUCT root; the
# vendored framework .gitignore only covers agentic-sdlc/. Without these lines
# a seat's `git add -A` would commit .env.local (which may hold a GH_TOKEN).
for pat in '.env.local' '.*-seat.md' '.claude/settings.local.json' '.DS_Store'; do
  grep -qxF "$pat" "$INTO/.gitignore" 2>/dev/null || printf '%s\n' "$pat" >> "$INTO/.gitignore"
done
echo "✓ root .gitignore covers seat env + identity files (never commit .env.local)"

# optional: publish to GitHub (bootstrap needs the repo to exist there —
# the labels, issues, and board live on it)
if [ -n "$REPO" ]; then
  git -C "$INTO" add -A
  git -C "$INTO" diff --cached --quiet \
    || git -C "$INTO" commit -m "chore(sdlc): vendor agentic-sdlc framework" >/dev/null
  if gh repo view "$REPO" >/dev/null 2>&1; then
    echo "· GitHub repo $REPO already exists"
    git -C "$INTO" remote get-url origin >/dev/null 2>&1 \
      || { git -C "$INTO" remote add origin "https://github.com/$REPO.git"; git -C "$INTO" push -u origin main; }
  else
    ( cd "$INTO" && gh repo create "$REPO" $VISIBILITY --source . --push >/dev/null )
    echo "✓ GitHub repo created + first commit pushed → https://github.com/$REPO ($([ "$VISIBILITY" = "--public" ] && echo public || echo private))"
  fi
  cat <<NEXT

  Next:
    cd $INTO
    bash agentic-sdlc/onboarding/bootstrap.sh     # stands up the whole instance
NEXT
else
  cat <<NEXT

  Next:
    cd $INTO
    git add -A && git commit -m "chore(sdlc): vendor agentic-sdlc framework"
    gh repo create <you>/$(basename "$INTO") --private --source . --push   # bootstrap needs the repo on GitHub
    bash agentic-sdlc/onboarding/bootstrap.sh     # stands up the whole instance
NEXT
fi
