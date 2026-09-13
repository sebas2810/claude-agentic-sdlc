#!/usr/bin/env bash
#
# Both-directions test for the guarded-index check (#3968, second half).
#
# The defect it guards: sync overwrote feedback/INDEX.md with canonical's copy,
# silently deleting instance-local rows. Same shape as the CHANGELOG defect the
# append-only merger fixed — a shorter file and exit 0, indistinguishable from
# a clean sync — but INDEX.md is a link table, not a dated log, so it needs a
# guard rather than that merger.
#
# The third case is the one that makes this usable rather than merely safe: an
# upstream REWORDING of a row must not read as a local-only row. Keying on the
# whole line would block every sync the moment canonical edits any one-liner.
#
# Usage: check-no-local-only-rows.test.sh <path-to-check-no-local-only-rows.sh>
set -uo pipefail

CHECK="${1:-}"
[ -n "$CHECK" ] || { echo "usage: $0 <path-to-check-no-local-only-rows.sh>" >&2; exit 1; }
case "$CHECK" in /*) ;; *) CHECK="$(cd "$(dirname "$CHECK")" && pwd)/$(basename "$CHECK")" ;; esac
[ -f "$CHECK" ] || { echo "no such check script: $CHECK" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { printf '  OK    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }

canon() {
  cat > "$T/canon.md" <<'EOF'
# Feedback Index

## Rules

| Rule | One-liner |
|---|---|
| [`workflow/always-pr-never-push.md`](workflow/always-pr-never-push.md) | All changes go through PRs |
| [`workflow/branch-per-epic.md`](workflow/branch-per-epic.md) | One feature branch per EPIC |
EOF
}

# 1. Identical — nothing can be lost, so the caller may overwrite.
canon; cp "$T/canon.md" "$T/local.md"
if bash "$CHECK" "$T/canon.md" "$T/local.md" >/dev/null 2>&1; then
  ok "identical files exit 0 (overwrite is safe)"
else
  bad "identical files should exit 0"
fi

# 2. Local-only row — the actual #3968 failure mode. MUST refuse.
canon; cp "$T/canon.md" "$T/local.md"
printf '| [`workflow/instance-only.md`](workflow/instance-only.md) | local rule |\n' >> "$T/local.md"
out="$(bash "$CHECK" "$T/canon.md" "$T/local.md" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  case "$out" in
    *workflow/instance-only.md*) ok "local-only row exits non-zero AND names the row" ;;
    *) bad "local-only row refused but did not name which row" ;;
  esac
else
  bad "local-only row MUST exit non-zero — this is the defect being guarded"
fi

# 3. Canonical reworded a one-liner, same path. MUST NOT read as local-only,
#    or every upstream copy edit blocks the sync.
canon; cp "$T/canon.md" "$T/local.md"
sed 's#| All changes go through PRs #| Completely different wording #' "$T/canon.md" > "$T/local2.md"
if bash "$CHECK" "$T/canon.md" "$T/local2.md" >/dev/null 2>&1; then
  ok "reworded row with the same path exits 0 (no false block)"
else
  bad "a reworded row must NOT count as local-only"
fi

# 4. Local file absent — nothing to lose.
canon
if bash "$CHECK" "$T/canon.md" "$T/does-not-exist.md" >/dev/null 2>&1; then
  ok "absent local file exits 0"
else
  bad "absent local file should exit 0"
fi

# 5. Canonical absent — a usage/IO error, distinct from 'unsafe'. Must not be
#    mistaken for a clean pass by a caller that only checks for zero.
if bash "$CHECK" "$T/nope.md" "$T/local.md" >/dev/null 2>&1; then
  bad "missing canonical file must not exit 0"
else
  ok "missing canonical file exits non-zero"
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "check-no-local-only-rows: all checks passed"
else
  echo "check-no-local-only-rows: $fails check(s) FAILED" >&2
fi
exit "$fails"
