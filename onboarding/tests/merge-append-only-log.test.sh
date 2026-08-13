#!/usr/bin/env bash
#
# Both-directions test for the append-only log merge.
#
# The defect it guards: sync overwrote learning-loop/CHANGELOG.md with
# canonical's copy, silently deleting every instance-local entry. It produced a
# shorter file and exited 0 — indistinguishable from a clean sync.
#
# Usage: merge-append-only-log.test.sh <path-to-merge-append-only-log.sh>
set -uo pipefail

MERGE="${1:-}"
[ -n "$MERGE" ] || { echo "usage: $0 <path-to-merge-append-only-log.sh>" >&2; exit 1; }
case "$MERGE" in /*) ;; *) MERGE="$(cd "$(dirname "$MERGE")" && pwd)/$(basename "$MERGE")" ;; esac
[ -f "$MERGE" ] || { echo "no such merge script: $MERGE" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

cat > "$T/canon.md" <<'EOF'
# Way of Working — Changelog

Newest at top.

## 2026-08-13 — canonical newest

canonical body newest

## 2026-08-12 — shared entry

canonical version of the shared body

## 2026-08-06 — canonical oldest

canonical body oldest
EOF

cat > "$T/local.md" <<'EOF'
# Way of Working — Changelog

Newest at top.

## 2026-08-12 — shared entry

LOCAL version of the shared body

## 2026-08-08 — instance-only entry

the entry three syncs kept deleting

## 2026-08-06 — canonical oldest

canonical body oldest
EOF

bash "$MERGE" "$T/canon.md" "$T/local.md" "$T/out.md" || bad "merge exited non-zero"

echo "── nothing is lost ──"
grep -q '## 2026-08-08 — instance-only entry' "$T/out.md" \
  && ok "the instance-only entry survives the merge" \
  || bad "the instance-only entry was DROPPED — this is the exact #3968 data loss"

grep -q 'the entry three syncs kept deleting' "$T/out.md" \
  && ok "its body survives, not just its heading" \
  || bad "the instance-only entry's BODY was lost"

grep -q '## 2026-08-13 — canonical newest' "$T/out.md" \
  && ok "new canonical entries arrive" \
  || bad "canonical's new entry did not arrive — the sync half is broken"

echo "── shape is preserved ──"
if [ "$(grep -c '^## ' "$T/out.md")" -eq 4 ]; then
  ok "exactly 4 entries — union with no duplicates"
else
  bad "expected 4 entries, got $(grep -c '^## ' "$T/out.md") — dedupe by heading is broken"
fi

if [ "$(grep -c 'LOCAL version of the shared body' "$T/out.md")" -eq 0 ] \
   && [ "$(grep -c 'canonical version of the shared body' "$T/out.md")" -eq 1 ]; then
  ok "an entry present in both takes canonical's body"
else
  bad "shared-heading resolution wrong — upstream edits must win on a shared entry"
fi

order="$(grep '^## ' "$T/out.md" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tr '\n' ' ')"
if [ "$order" = "2026-08-13 2026-08-12 2026-08-08 2026-08-06 " ]; then
  ok "entries are ordered newest-first across both sources"
else
  bad "wrong order: $order"
fi

head -1 "$T/out.md" | grep -q '^# Way of Working' \
  && ok "the file header is preserved" \
  || bad "header lost"

echo "── anti-tautology: the test must detect the old behaviour ──"
# Simulate the pre-fix sync: a straight overwrite.
cp "$T/canon.md" "$T/clobbered.md"
if grep -q '## 2026-08-08 — instance-only entry' "$T/clobbered.md"; then
  bad "the overwrite fixture still contains the local entry — the test proves nothing"
else
  ok "a plain overwrite loses the entry, which is what this merge prevents"
fi

echo "── a missing local file is not an error ──"
bash "$MERGE" "$T/canon.md" "$T/nonexistent.md" "$T/fresh.md" >/dev/null 2>&1
if [ -f "$T/fresh.md" ] && grep -q '## 2026-08-13' "$T/fresh.md"; then
  ok "a first-time instance just receives canonical's copy"
else
  bad "missing local file was not handled"
fi

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $((fails > 0))
