#!/usr/bin/env bash
#
# check-no-local-only-rows.sh — refuse to overwrite a link-table index that
# carries rows canonical does not have.
#
# Why this exists, and why it is NOT the append-only merger (#3968):
#
# `merge-append-only-log.sh` union-merges a DATED, NEWEST-FIRST log — entries
# are `## <heading>` blocks keyed on the heading and ordered by the ISO date in
# it. `feedback/INDEX.md` is not that shape at all: it is 30+ markdown table
# rows grouped under mostly-undated section headings. Feeding it to that merger
# would key on headings that carry no date, producing arbitrary ordering and
# silently dropping undated sections — a worse failure than the one being
# fixed, because it would look like a successful merge.
#
# The unit of meaning in an index is the ROW, not the section. So rather than
# invent a second merge semantics and risk getting it wrong, this is a GUARD:
# it detects the condition that makes a clobber lossy and refuses. The sync
# then leaves the file untouched and says so, loudly.
#
# That is deliberately conservative. An index SHOULD normally be pure canonical
# — instance-specific rules live under `instance/<name>/rules/`, which sync
# already excludes — so a local-only row is either (a) a rule that belongs
# upstream and has not been raised yet, or (b) a genuine instance addition that
# needs a human decision about where it lives. Both want a person, not an
# automatic merge.
#
# Exit 0 — no local-only rows; the caller may overwrite safely.
# Exit 1 — local-only rows found (listed on stderr); the caller must NOT
#          overwrite.
# Exit 2 — usage/IO error.
#
# Rule: feedback/architecture/no-silent-degradation-on-load-bearing-paths.md
set -uo pipefail

CANON="${1:-}"; LOCAL="${2:-}"
[ -n "$CANON" ] && [ -n "$LOCAL" ] || {
  echo "usage: $0 <canonical-file> <local-file>" >&2; exit 2; }
[ -f "$CANON" ] || { echo "no such canonical file: $CANON" >&2; exit 2; }
# A local file that does not exist yet cannot lose anything.
[ -f "$LOCAL" ] || exit 0

# The key is the row's first markdown link target — the rule path — not the
# whole line. Prose in the one-liner column drifts upstream all the time; the
# path is what identifies the rule, so keying on the line would report a
# reworded row as local-only and block every sync.
row_keys() {
  grep -oE '^\| \[`[^`]+`\]\([^)]+\)' "$1" 2>/dev/null \
    | sed -E 's#.*\(([^)]+)\).*#\1#' \
    | sort -u
}

CANON_KEYS="$(row_keys "$CANON")"
LOCAL_KEYS="$(row_keys "$LOCAL")"

# Rows the instance has that canonical does not — the ones a clobber destroys.
ONLY_LOCAL="$(comm -23 <(printf '%s\n' "$LOCAL_KEYS") <(printf '%s\n' "$CANON_KEYS") | grep -v '^$' || true)"

[ -z "$ONLY_LOCAL" ] && exit 0

count="$(printf '%s\n' "$ONLY_LOCAL" | wc -l | tr -d ' ')"
{
  echo "$(basename "$LOCAL"): $count row(s) exist locally but not in canonical:"
  printf '%s\n' "$ONLY_LOCAL" | sed 's/^/    /'
  echo ""
  echo "  Overwriting would delete them silently — the #3968 failure mode."
  echo "  Either upstream the rule so canonical carries the row, or move it to"
  echo "  instance/<name>/rules/ (which sync excludes), then re-run."
} >&2
exit 1
