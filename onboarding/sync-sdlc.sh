#!/usr/bin/env bash
# sync-sdlc.sh — drift report (+ owner-gated apply) between THIS repo's
# agentic-sdlc/ copy and the canonical claude-agentic-sdlc framework (#2675).
#
# Usage:
#   agentic-sdlc/onboarding/sync-sdlc.sh                  # report-only (default — no writes, ever, without --apply)
#   agentic-sdlc/onboarding/sync-sdlc.sh --ref <sha|branch>  # compare against a specific canonical ref (default: main)
#   agentic-sdlc/onboarding/sync-sdlc.sh --apply          # write ADDED + CHANGED files — asks for typed confirmation
#
# Compares the PORTABLE framework ONLY — mirroring vendor-framework.sh's
# exclusion list, so /update can never pull in what vendoring deliberately
# leaves out:
#   instance/        the per-product overlay — never diffed or touched
#   .github/         workflows are inert in a subdirectory (repo-root only)
#   .claude-plugin/  the plugin installs from the marketplace, not the vendor
#   SECURITY.md      framework-repo-specific (points at ITS advisories)
#   assurance/       STRUCTURAL INDEPENDENCE — the Assure loop runs from its
#                    own checkout AGAINST product repos, never inside them
#
# --apply is intentionally NOT a routine flag: the files it can rewrite
# (agentic-operating-model.md, seats/*, feedback/*, the skill model) are what
# every active seat's behaviour derives from. Applying mid-wave, without the
# owner having reviewed the report first, is exactly the "silent process
# rewrite" risk #2675's PM adjudication called out — so apply mode always
# prints the full file list it's about to touch and requires the operator to
# type the word "apply" back, every single run. There is no --yes / --force
# escape hatch by design.
#
# Requires: git only (canonical is a public repo — plain https clone, no gh
# auth needed). Never mutates the canonical checkout; that's a throwaway tmpdir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"        # agentic-sdlc/
CANONICAL_REPO="sebas2810/claude-agentic-sdlc"
REF="main"
APPLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --ref) REF="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "→ fetching canonical ${CANONICAL_REPO}@${REF} ..."
# Full clone, then checkout the ref — works uniformly for a branch name OR an
# exact SHA (a shallow --branch clone only accepts branch/tag names).
git clone --quiet "https://github.com/${CANONICAL_REPO}.git" "$TMPDIR/canonical"
(cd "$TMPDIR/canonical" && git checkout --quiet "$REF")
CANONICAL_SHA="$(cd "$TMPDIR/canonical" && git rev-parse HEAD)"
echo "  canonical @ ${CANONICAL_SHA}"

# ── Build sorted, repo-relative file lists (instance/ + canonical's own .git/
#    excluded from both sides) ────────────────────────────────────────────────
CANON_FILES="$TMPDIR/canon_files.txt"
LOCAL_FILES="$TMPDIR/local_files.txt"
EXCLUDES=( -not -path './.git/*' -not -path './instance/*' -not -path './.github/*'
           -not -path './.claude-plugin/*' -not -name 'SECURITY.md' -not -path './assurance/*' )
(cd "$TMPDIR/canonical" && find . -type f "${EXCLUDES[@]}" | sed 's#^\./##' | sort) > "$CANON_FILES"
(cd "$ROOT" && find . -type f "${EXCLUDES[@]}" | sed 's#^\./##' | sort) > "$LOCAL_FILES"

comm -23 "$CANON_FILES" "$LOCAL_FILES" > "$TMPDIR/added.txt"       # in canonical, not local
comm -13 "$CANON_FILES" "$LOCAL_FILES" > "$TMPDIR/local_only.txt"  # in local, not canonical
comm -12 "$CANON_FILES" "$LOCAL_FILES" > "$TMPDIR/common.txt"      # in both — diff content below

CHANGED_FILE="$TMPDIR/changed.txt"
: > "$CHANGED_FILE"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  diff -q "$TMPDIR/canonical/$f" "$ROOT/$f" >/dev/null 2>&1 || echo "$f" >> "$CHANGED_FILE"
done < "$TMPDIR/common.txt"

ADDED_COUNT=$(wc -l < "$TMPDIR/added.txt" | tr -d ' ')
CHANGED_COUNT=$(wc -l < "$CHANGED_FILE" | tr -d ' ')
LOCAL_ONLY_COUNT=$(wc -l < "$TMPDIR/local_only.txt" | tr -d ' ')

echo ""
echo "==== SDLC drift report — canonical@${CANONICAL_SHA} vs this repo's agentic-sdlc/ ===="
echo ""
echo "ADDED upstream, missing locally (${ADDED_COUNT}):"
sed 's/^/  + /' "$TMPDIR/added.txt"
echo ""
echo "CHANGED upstream vs local (${CHANGED_COUNT}):"
sed 's/^/  ~ /' "$CHANGED_FILE"
echo ""
echo "LOCAL-ONLY, not in canonical (${LOCAL_ONLY_COUNT}) — instance-specific or diverged, NEVER auto-touched:"
sed 's/^/  ? /' "$TMPDIR/local_only.txt"
echo ""

if [ "$APPLY" -eq 0 ]; then
  echo "Report-only (default) — nothing written."
  echo "Re-run with --apply to write the ADDED + CHANGED files above (local-only"
  echo "files are never touched); apply mode asks for a typed confirmation first."
  exit 0
fi

TOTAL_WRITES=$((ADDED_COUNT + CHANGED_COUNT))
if [ "$TOTAL_WRITES" -eq 0 ]; then
  echo "Nothing to apply — local copy already matches canonical@${CANONICAL_SHA}."
  exit 0
fi

echo ""
echo "!! --apply will OVERWRITE ${TOTAL_WRITES} file(s) under agentic-sdlc/ with"
echo "   canonical@${CANONICAL_SHA}'s version — including operating-model / seat /"
echo "   feedback files every active seat currently follows. This is NOT reversible"
echo "   by this script (your own git history is the undo)."
read -r -p "   Type 'apply' to confirm, anything else aborts: " CONFIRM
if [ "$CONFIRM" != "apply" ]; then
  echo "Aborted — no files written."
  exit 1
fi

while IFS= read -r f; do
  [ -z "$f" ] && continue
  mkdir -p "$ROOT/$(dirname "$f")"
  cp -p "$TMPDIR/canonical/$f" "$ROOT/$f"
  echo "  wrote $f"
done < "$TMPDIR/added.txt"

while IFS= read -r f; do
  [ -z "$f" ] && continue
  cp -p "$TMPDIR/canonical/$f" "$ROOT/$f"
  echo "  wrote $f"
done < "$CHANGED_FILE"

echo "$CANONICAL_SHA" > "$ROOT/.sdlc-version"
echo ""
echo "done. agentic-sdlc/.sdlc-version now records canonical@${CANONICAL_SHA}."
echo "Review the diff (git status / git diff) and commit like any other change."
