#!/usr/bin/env bash
#
# Both-directions test for check-worker-definitions.sh (#76, criterion 3).
#
# The defect it guards: a worker subagent loads no personal memory, so the
# rules it follows are exactly the files its definition lists. A definition
# that drops a rule, or names a file that has since been renamed, still runs
# and still reports. Only this check notices, so each case below breaks a copy
# of the real definitions and requires the check to fail and name the break.
#
# Usage: worker-definitions.test.sh <path-to-check-worker-definitions.sh>
set -uo pipefail

CHECK="${1:-}"
[ -n "$CHECK" ] || { echo "usage: $0 <path-to-check-worker-definitions.sh>" >&2; exit 1; }
case "$CHECK" in /*) ;; *) CHECK="$(cd "$(dirname "$CHECK")" && pwd)/$(basename "$CHECK")" ;; esac
[ -f "$CHECK" ] || { echo "no such check script: $CHECK" >&2; exit 1; }
FW="$(cd "$(dirname "$CHECK")/../.." && pwd)"

T="$(mktemp -d)"
trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT
fails=0
ok()   { printf '  OK    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
skip() { printf '  SKIP  %s\n' "$1"; }

fresh_copy() {
  rm -rf "$T/fw" && mkdir -p "$T/fw"
  tar -C "$FW" -cf - agents commands seats skills workflow feedback operations | tar -x -C "$T/fw"
}

# expect <exit-code> <text the output must contain> <description>
expect() {
  local want="$1" needle="$2" desc="$3" out rc
  out="$(bash "$CHECK" "$T/fw" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then
    bad "$desc (exit $rc, want $want): $(printf '%s' "$out" | tail -3)"
  elif ! printf '%s' "$out" | grep -qF -- "$needle"; then
    bad "$desc (exit $rc, but the output does not name: $needle)"
  else
    ok "$desc"
  fi
}

# 1. The definitions in this checkout conform.
out="$(bash "$CHECK" "$FW" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "the checkout's worker definitions conform"; else bad "the checkout's worker definitions must conform (exit $rc): $out"; fi

# 2. A required rule dropped from a definition's list.
fresh_copy
grep -v 'feedback/workflow/author-is-the-ownership-boundary.md' "$T/fw/agents/engineer-worker.md" > "$T/edit" && mv "$T/edit" "$T/fw/agents/engineer-worker.md"
expect 1 'agents/engineer-worker.md: no longer lists required rule `feedback/workflow/author-is-the-ownership-boundary.md`' \
  "a dropped required rule fails and is named"

# 3. A listed rule file that no longer exists.
fresh_copy
rm "$T/fw/feedback/workflow/live-eval-owns-its-teardown.md"
expect 1 'agents/quality-worker.md: lists `feedback/workflow/live-eval-owns-its-teardown.md`, which does not resolve' \
  "a listed rule that no longer resolves fails and is named"

# 4. An extra listed path that does not resolve (not on the required list).
fresh_copy
awk '{ print } /^## Rules you carry$/ { print ""; print "- `feedback/workflow/no-such-rule.md`" }' \
  "$T/fw/agents/quality-worker.md" > "$T/edit" && mv "$T/edit" "$T/fw/agents/quality-worker.md"
expect 1 '`feedback/workflow/no-such-rule.md`, which does not resolve' \
  "any listed path that does not resolve fails, required or not"

# 5. The section renamed, so nothing is carried.
fresh_copy
sed 's/^## Rules you carry$/## Rules/' "$T/fw/agents/quality-worker.md" > "$T/edit" && mv "$T/edit" "$T/fw/agents/quality-worker.md"
expect 1 "agents/quality-worker.md: no '## Rules you carry' section" \
  "a missing rules section fails and is named"

# 6. Frontmatter name that no longer matches the file.
fresh_copy
sed '2s/^name: quality-worker$/name: qa-worker/' "$T/fw/agents/quality-worker.md" > "$T/edit" && mv "$T/edit" "$T/fw/agents/quality-worker.md"
expect 1 "frontmatter name is 'qa-worker', expected 'quality-worker'" \
  "a renamed worker fails and is named"

# 7. A definition deleted.
fresh_copy
rm "$T/fw/agents/engineer-worker.md"
expect 1 "agents/engineer-worker.md: missing" "a deleted definition fails and is named"

# 8. An unreadable definition is an IO error (2), not a finding and not a pass.
if [ "$(id -u)" -eq 0 ]; then
  skip "unreadable definition (root reads a mode-000 file)"
else
  fresh_copy
  chmod 000 "$T/fw/agents/quality-worker.md"
  expect 2 "cannot read agents/quality-worker.md" "an unreadable definition exits 2 and names the file"
  chmod 644 "$T/fw/agents/quality-worker.md"
fi

# 9. A root that is not a directory is an IO error.
out="$(bash "$CHECK" "$T/no-such-root" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF "not a directory"; then
  ok "a missing framework root exits 2 and says so"
else
  bad "a missing framework root must exit 2 (exit $rc): $out"
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "worker-definitions: all checks passed"
else
  echo "worker-definitions: $fails check(s) FAILED" >&2
fi
exit "$fails"
