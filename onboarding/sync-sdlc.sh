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
ROOT="${SDLC_ROOT:-$(cd "$HERE/.." && pwd)}"        # agentic-sdlc/ (SDLC_ROOT: tests only)
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
git clone --quiet "${CANONICAL_URL:-https://github.com/${CANONICAL_REPO}.git}" "$TMPDIR/canonical"  # CANONICAL_URL: tests only
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

# ── Guarded link-table indexes ───────────────────────────────────────────────
# The other half of #3968. These are NOT append-only logs and must not go
# through merge-append-only-log.sh: that merger keys on `## <heading>` and
# orders by the ISO date in it, while feedback/INDEX.md is 30+ table rows under
# mostly-undated headings. Feeding it there would drop undated sections while
# reporting a successful merge — worse than the clobber it replaces.
#
# An index should normally be pure canonical (instance rules live under
# instance/<name>/rules/, already excluded above). So instead of inventing a
# second merge semantics, detect the condition that makes a clobber lossy and
# REFUSE. A local-only row means either a rule that belongs upstream or one
# that belongs in the instance overlay — both want a human, not a merge.
GUARDED_INDEX=( 'feedback/INDEX.md' )
is_guarded_index() {
  local f="$1" a
  for a in "${GUARDED_INDEX[@]}"; do [ "$f" = "$a" ] && return 0; done
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

# ── Retired upstream ─────────────────────────────────────────────────────────
# A local-only file is RETIRED when canonical shipped it at the version this
# repo last synced to (.sdlc-version) and no longer ships it. It is removed on
# apply only if it is byte-identical to what canonical shipped then: a file the
# instance authored, or edited since, is never removed, only reported.
: > "$TMPDIR/retired.txt"; : > "$TMPDIR/retired_modified.txt"
PINNED="$(cat "$ROOT/.sdlc-version" 2>/dev/null || true)"
if [ -n "$PINNED" ] && git -C "$TMPDIR/canonical" cat-file -e "${PINNED}^{commit}" 2>/dev/null; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if git -C "$TMPDIR/canonical" cat-file -e "${PINNED}:$f" 2>/dev/null; then
      if git -C "$TMPDIR/canonical" show "${PINNED}:$f" | cmp -s - "$ROOT/$f"; then
        echo "$f" >> "$TMPDIR/retired.txt"
      else
        echo "$f" >> "$TMPDIR/retired_modified.txt"
      fi
    fi
  done < "$TMPDIR/local_only.txt"
  grep -vxF -f "$TMPDIR/retired.txt" -f "$TMPDIR/retired_modified.txt" "$TMPDIR/local_only.txt" > "$TMPDIR/local_only.rest" || true
  mv "$TMPDIR/local_only.rest" "$TMPDIR/local_only.txt"
  LOCAL_ONLY_COUNT=$(wc -l < "$TMPDIR/local_only.txt" | tr -d ' ')
fi
RETIRED_COUNT=$(wc -l < "$TMPDIR/retired.txt" | tr -d ' ')
RETIRED_MOD_COUNT=$(wc -l < "$TMPDIR/retired_modified.txt" | tr -d ' ')

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
echo "RETIRED upstream, unchanged locally (${RETIRED_COUNT}) — removed on apply:"
sed 's/^/  - /' "$TMPDIR/retired.txt"
echo ""
if [ "$RETIRED_MOD_COUNT" -gt 0 ]; then
  echo "RETIRED upstream but EDITED locally (${RETIRED_MOD_COUNT}) — kept; decide by hand:"
  sed 's/^/  ! /' "$TMPDIR/retired_modified.txt"
  echo ""
fi
[ -n "$PINNED" ] || { echo "(no .sdlc-version recorded — retired files cannot be told apart from instance files, so none are removed)"; echo ""; }
echo "LOCAL-ONLY, not in canonical (${LOCAL_ONLY_COUNT}) — instance-specific or diverged, NEVER auto-touched:"
sed 's/^/  ? /' "$TMPDIR/local_only.txt"
echo ""

if [ "$APPLY" -eq 0 ]; then
  echo "Report-only (default) — nothing written."
  echo "Re-run with --apply to write the ADDED + CHANGED files and remove the RETIRED ones (local-only"
  echo "files are never touched, and files marked [append-only] are merged rather"
  echo "than replaced); apply mode asks for a typed confirmation first."
  exit 0
fi

TOTAL_WRITES=$((ADDED_COUNT + CHANGED_COUNT + RETIRED_COUNT))
if [ "$TOTAL_WRITES" -eq 0 ]; then
  echo "Nothing to apply — local copy already matches canonical@${CANONICAL_SHA}."
  exit 0
fi

echo ""
echo "!! --apply will OVERWRITE or REMOVE ${TOTAL_WRITES} file(s) under agentic-sdlc/ to match"
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
  elif is_guarded_index "$f"; then
    # Guarded index — overwrite only if the instance has no rows canonical
    # lacks. The guard exits non-zero and lists them; never clobber past it.
    if bash "$HERE/lib/check-no-local-only-rows.sh" \
         "$TMPDIR/canonical/$f" "$ROOT/$f"; then
      install_file "$TMPDIR/canonical/$f" "$ROOT/$f"
      echo "  wrote $f  (guarded index: no local-only rows, safe to replace)"
    else
      echo "  SKIPPED $f — local-only rows would be lost; left untouched, reconcile by hand" >&2
    fi
  else
    install_file "$TMPDIR/canonical/$f" "$ROOT/$f"
    echo "  wrote $f"
  fi
done < "$CHANGED_FILE"

while IFS= read -r f; do
  [ -z "$f" ] && continue
  rm -f "$ROOT/$f"
  echo "  removed $f  (retired upstream)"
done < "$TMPDIR/retired.txt"
find "$ROOT" -type d -empty -not -path "$ROOT/.git*" -delete 2>/dev/null || true

echo "$CANONICAL_SHA" > "$ROOT/.sdlc-version"
echo ""
echo "done. agentic-sdlc/.sdlc-version now records canonical@${CANONICAL_SHA}."
echo "Review the diff (git status / git diff) and commit like any other change."
