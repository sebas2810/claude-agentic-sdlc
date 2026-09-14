#!/usr/bin/env bash
#
# Both-directions test for pick-worker.sh.
#
# The defect it guards: an item that runs at a tier nobody chose. A typo in a
# tier label that falls back to standard, a second tier label that one of them
# silently wins, or a rework that runs at the tier that already failed: each
# still starts a worker and still reports, so only this test notices. Valid
# labels must pick exactly the documented worker, and every worker it can
# print must have a definition.
#
# Usage: pick-worker.test.sh <path-to-pick-worker.sh>
set -uo pipefail

S="${1:-}"
[ -n "$S" ] || { echo "usage: $0 <path-to-pick-worker.sh>" >&2; exit 1; }
case "$S" in /*) ;; *) S="$(cd "$(dirname "$S")" && pwd)/$(basename "$S")" ;; esac
[ -f "$S" ] || { echo "no such script: $S" >&2; exit 1; }
FW="$(cd "$(dirname "$S")/../.." && pwd)"

fails=0
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# picks <description> <expected worker> <args...>: exit 0 and exactly that name
picks() {
  local desc="$1" want="$2" out rc; shift 2
  out="$(bash "$S" "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "$want" ]; then ok "$desc"; else bad "$desc (exit $rc, got '$out', want '$want')"; fi
}
# refused <description> <text stderr must contain> <args...>: exit 2 and a named cause
refused() {
  local desc="$1" needle="$2" out rc; shift 2
  out="$(bash "$S" "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF -- "$needle"; then ok "$desc"; else bad "$desc (exit $rc, output '$out')"; fi
}

# Every tier, both roles.
picks "engineer, no tier label: standard" engineer-worker --role engineer --labels "status:scoped"
picks "engineer, no labels at all: standard" engineer-worker --role engineer --labels ""
picks "engineer, tier:light" engineer-worker-light --role engineer --labels "tier:light"
picks "engineer, tier:standard" engineer-worker --role engineer --labels "tier:standard"
picks "engineer, tier:deep" engineer-worker-deep --role engineer --labels "P1, tier:deep ,status:scoped"
picks "quality, no tier label: standard" quality-worker --role quality --labels "status:delivered"
picks "quality, tier:light" quality-worker-light --role quality --labels "tier:light"
picks "quality, tier:standard" quality-worker --role quality --labels "tier:standard"
picks "quality, tier:deep" quality-worker-deep --role quality --labels "tier:deep"

# The quality floor: agent work is never verified at light.
picks "quality, tier:light on area:agentic runs at standard" quality-worker --role quality --labels "tier:light,area:agentic"
picks "quality, tier:deep on area:agentic stays deep" quality-worker-deep --role quality --labels "area:agentic,tier:deep"
picks "the floor is the quality role's only: engineer tier:light on area:agentic stays light" \
  engineer-worker-light --role engineer --labels "tier:light,area:agentic"

# Escalation: a rework runs one tier up, capped at deep.
picks "engineer rework of tier:light runs at standard" engineer-worker --role engineer --labels "tier:light" --fails 1
picks "engineer rework of tier:light after 2 FAILs is still one step up" engineer-worker --role engineer --labels "tier:light" --fails 2
picks "engineer rework of standard runs at deep" engineer-worker-deep --role engineer --labels "status:scoped" --fails 1
picks "engineer rework of tier:deep stays deep" engineer-worker-deep --role engineer --labels "tier:deep" --fails 2
picks "--fails 0 is a fresh build, not a rework" engineer-worker-light --role engineer --labels "tier:light" --fails 0

# Every name the picker can print has a definition to start.
for name in engineer-worker-light engineer-worker engineer-worker-deep quality-worker-light quality-worker quality-worker-deep; do
  if [ -f "$FW/agents/$name.md" ]; then ok "agents/$name.md exists"; else bad "agents/$name.md is missing, so a picked worker cannot start"; fi
done

# A tier nobody chose is refused, never guessed.
refused "two tier labels are refused, naming both" "more than one tier label (tier:light and tier:deep)" \
  --role engineer --labels "tier:light,tier:deep"
refused "the same tier label twice is refused" "more than one tier label" \
  --role engineer --labels "tier:deep,tier:deep"
refused "an unknown tier is refused, not read as standard" "'tier:heavy' is not a tier" \
  --role engineer --labels "tier:heavy"
refused "a missing role is refused" "--role is required" --labels "tier:light"
refused "an unknown role is refused" "--role 'designer' is not engineer or quality" --role designer --labels ""
refused "missing labels are refused, not read as none" "--labels is required" --role engineer
refused "a non-number --fails is refused" "--fails 'one' is not a whole number" --role engineer --labels "" --fails one
refused "a negative --fails is refused" "--fails '-1' is not a whole number" --role engineer --labels "" --fails -1
refused "a --fails with more than 3 digits is refused" "has more than 3 digits" --role engineer --labels "" --fails 1000
refused "--fails for the quality role is refused" "--fails applies to --role engineer only" --role quality --labels "" --fails 1
refused "an unknown argument is refused" "unknown argument '--tier'" --role engineer --labels "" --tier deep
refused "a flag with no value is refused" "--labels needs a value" --role engineer --labels

echo ""
if [ "$fails" -eq 0 ]; then
  echo "pick-worker: all checks passed"
else
  echo "pick-worker: $fails check(s) FAILED" >&2
fi
exit "$fails"
