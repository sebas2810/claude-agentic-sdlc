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

# ── Atomic install ───────────────────────────────────────────────────────────
# `cp` rewrites the destination IN PLACE, reusing its inode. This script is one
# of the files it syncs, and bash reads a script lazily by byte offset — so
# overwriting sync-sdlc.sh mid-apply moved the ground under the running process.
#
# Observed 2026-08-13: the file grew 6041 -> 7666 bytes during its own apply.
# Everything past that point — the .sdlc-version write and the completion
# message — never executed. Exit status looked clean and the pin silently kept
# its previous value, so the NEXT sync would have diffed against a stale
# baseline. It fires precisely when the sync updates itself, which is when it
# matters most.
#
# `mv` replaces the directory entry instead, leaving the running process on the
# old inode. It is also atomic per-file: a reader sees the old file or the new
# one, never a half-written one.
install_file() { # $1 = source, $2 = destination
  local tmp="$2.sync-tmp.$$"
  cp -p "$1" "$tmp" && mv -f "$tmp" "$2"
}

# ── Append-only instance logs ────────────────────────────────────────────────
# Files that record what happened in THIS instance. They diverge by design and
# can never be "brought up to date" by replacement — a replace is a deletion of
# instance history. These are union-merged on apply, never overwritten (#3968).
APPEND_ONLY=( 'learning-loop/CHANGELOG.md' )
is_append_only() {
  local f="$1" a
  for a in "${APPEND_ONLY[@]}"; do [ "$f" = "$a" ] && return 0; done
  return 1
}

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
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if is_append_only "$f"; then
    echo "  ~ $f   [append-only: MERGED, never overwritten — instance entries kept]"
  else
    echo "  ~ $f"
  fi
done < "$CHANGED_FILE"
echo ""
echo "LOCAL-ONLY, not in canonical (${LOCAL_ONLY_COUNT}) — instance-specific or diverged, NEVER auto-touched:"
sed 's/^/  ? /' "$TMPDIR/local_only.txt"
echo ""

if [ "$APPLY" -eq 0 ]; then
  echo "Report-only (default) — nothing written."
  echo "Re-run with --apply to write the ADDED + CHANGED files above (local-only"
  echo "files are never touched, and files marked [append-only] are merged rather"
  echo "than replaced); apply mode asks for a typed confirmation first."
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
  install_file "$TMPDIR/canonical/$f" "$ROOT/$f"
  echo "  wrote $f"
done < "$TMPDIR/added.txt"

while IFS= read -r f; do
  [ -z "$f" ] && continue
  if is_append_only "$f"; then
    # Append-only instance log — union-merge, never replace. Overwriting these
    # silently deleted instance-authored entries on every apply (#3968): the
    # file got shorter, the script exited 0, and only a human remembering to
    # re-add them by hand kept the history alive.
    if bash "$HERE/lib/merge-append-only-log.sh" \
         "$TMPDIR/canonical/$f" "$ROOT/$f" "$TMPDIR/merged.$$" 2>/dev/null; then
      mv "$TMPDIR/merged.$$" "$ROOT/$f"
      echo "  merged $f  (append-only: instance entries kept, canonical entries added)"
    else
      # Never fall back to a clobber — that is the defect this replaces.
      echo "  SKIPPED $f — append-only merge failed; left untouched, reconcile by hand" >&2
    fi
  else
    install_file "$TMPDIR/canonical/$f" "$ROOT/$f"
    echo "  wrote $f"
  fi
done < "$CHANGED_FILE"

echo "$CANONICAL_SHA" > "$ROOT/.sdlc-version"
echo ""
echo "done. agentic-sdlc/.sdlc-version now records canonical@${CANONICAL_SHA}."
echo "Review the diff (git status / git diff) and commit like any other change."
