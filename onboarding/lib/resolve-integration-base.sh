#!/usr/bin/env bash
#
# resolve-integration-base.sh — the ONE place this framework decides what a
# branch's base is: a registered long-lived integration branch it descends
# from, else origin/main. Sub-PRs targeting an epic branch are legitimately
# "behind" main and must not be measured against it.
#
# Extracted from guard-git.sh (#4543's REGISTRY SHAPE) so delivery-check.sh
# (sebas2810/claude-agentic-sdlc#73 AC3, "the base is the registered
# integration branch") can resolve the SAME base guard-git.sh already
# enforces, rather than trusting a caller-supplied literal or re-deriving
# its own copy. See feedback/architecture/one-control-one-implementation.md
# — a second, forked implementation of this exact logic is the failure mode
# that rule exists to name.
#
# Registry: one file per branch under agentic-sdlc/integration-branches/,
# the file's path equal to the branch name (e.g.
# agentic-sdlc/integration-branches/feat/4489-journey-rail). Override its
# location with AGENTIC_SDLC_INTEGRATION_BRANCHES; otherwise it is found by
# walking up from the target repo's toplevel.
#
# Usage: resolve-integration-base.sh <repo-dir> <src-ref>
# Prints the resolved base ref (origin/<branch>, or origin/main) to stdout.
# Exit 0 always for a usable repo-dir; exit 2 on a usage error.
set -uo pipefail

DIR="${1:-}"; SRC="${2:-}"
[ -n "$DIR" ] && [ -n "$SRC" ] || {
  echo "usage: $0 <repo-dir> <src-ref>" >&2; exit 2; }

g() { git -C "$DIR" "$@"; }

BASE="origin/main"
REG_DIR="${AGENTIC_SDLC_INTEGRATION_BRANCHES:-}"
if [ -z "$REG_DIR" ]; then
  RR="$(g rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$RR" ] && [ -d "$RR/agentic-sdlc/integration-branches" ] \
    && REG_DIR="$RR/agentic-sdlc/integration-branches"
fi
if [ -n "$REG_DIR" ] && [ -d "$REG_DIR" ]; then
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    if g rev-parse --verify -q "origin/$b" >/dev/null 2>&1 \
       && g merge-base --is-ancestor "origin/$b" "$SRC" 2>/dev/null; then
      BASE="origin/$b"; break
    fi
  done <<EOF
$(find "$REG_DIR" -type f ! -name 'README.md' 2>/dev/null | sed "s|^$REG_DIR/||")
EOF
fi

printf '%s\n' "$BASE"
