#!/usr/bin/env bash
#
# merge-append-only-log.sh — union-merge a dated, newest-first markdown log.
#
# Why this exists: `sync-sdlc.sh` treated learning-loop/CHANGELOG.md as an
# ordinary syncable file and overwrote it with canonical's copy. A changelog is
# an APPEND-ONLY PER-INSTANCE LOG: it records what happened in *this* instance,
# so it diverges by design and can never be "brought up to date" by replacement.
#
# Every apply silently deleted the instance's own entries. Observed three times
# on one instance (2026-08-12, twice, and 2026-08-13); each time the entries
# survived only because a human happened to remember to re-add them by hand. It
# never errored — it produced a shorter file, which reads exactly like a
# successful sync.
#
# The merge: entries are `## <heading>` blocks, newest first. The result is the
# UNION of both sides keyed on the heading line, ordered by the ISO date in the
# heading (descending). An entry present in both takes canonical's body, so
# upstream edits still land; an entry only the instance has is kept, which is
# the whole point.
#
# Usage: merge-append-only-log.sh <canonical-file> <local-file> <output-file>
#
# Rule: feedback/architecture/no-silent-degradation-on-load-bearing-paths.md
set -uo pipefail

CANON="${1:-}"; LOCAL="${2:-}"; OUT="${3:-}"
[ -n "$CANON" ] && [ -n "$LOCAL" ] && [ -n "$OUT" ] || {
  echo "usage: $0 <canonical-file> <local-file> <output-file>" >&2; exit 1; }
[ -f "$CANON" ] || { echo "no such canonical file: $CANON" >&2; exit 1; }

# A local file that does not exist yet is simply canonical's copy.
if [ ! -f "$LOCAL" ]; then cp "$CANON" "$OUT"; exit 0; fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Split a log into: _header (everything before the first `## `) + one file per entry.
split_log() { # $1 = source file, $2 = destination dir
  mkdir -p "$2"
  : > "$2/_header"
  awk -v out="$2" '
    /^## / { n++; f = sprintf("%s/e%04d", out, n) }
    n == 0 { print >> (out "/_header"); next }
    { print >> f }
  ' "$1"
}

split_log "$CANON" "$WORK/canon"
split_log "$LOCAL" "$WORK/local"

# Index every entry as: <sort-date> \t <heading> \t <path>
# Undated headings sort last (0000-00-00) but are still kept — never dropped.
index_entries() { # $1 = dir
  for f in "$1"/e[0-9]*; do
    [ -e "$f" ] || continue
    heading="$(head -1 "$f")"
    date="$(printf '%s' "$heading" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
    printf '%s\t%s\t%s\n' "${date:-0000-00-00}" "$heading" "$f"
  done
}

index_entries "$WORK/canon" > "$WORK/canon.idx"
index_entries "$WORK/local" > "$WORK/local.idx"

# Union keyed on the heading: every canonical entry, plus local entries whose
# heading canonical does not have.
cp "$WORK/canon.idx" "$WORK/merged.idx"
while IFS="$(printf '\t')" read -r d h p; do
  [ -z "$h" ] && continue
  if ! cut -f2 "$WORK/canon.idx" | grep -qxF "$h"; then
    printf '%s\t%s\t%s\n' "$d" "$h" "$p" >> "$WORK/merged.idx"
  fi
done < "$WORK/local.idx"

# Canonical's header (identical boilerplate in practice; canonical is the source
# of truth for the framing text, and entry content is what must not be lost).
cat "$WORK/canon/_header" > "$OUT"

# Newest first. -s keeps same-date entries in encounter order (canonical, then
# instance-local), so a same-day pair stays deterministic rather than shuffling.
sort -rs -k1,1 "$WORK/merged.idx" | cut -f3 | while IFS= read -r p; do
  [ -n "$p" ] && cat "$p" >> "$OUT"
done
