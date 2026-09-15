#!/usr/bin/env bash
#
# pick-worker.sh: which worker definition runs one item, from the item's tier
# label (workflow/fresh-context-workers.md, "Tiers").
#
# The tier is the item's one tier: label; an item with none is standard.
#   tier:light     Sonnet, low effort    <role>-worker-light
#   tier:standard  Opus, medium effort   <role>-worker
#   tier:deep      Opus, high effort     <role>-worker-deep
#
# Two rules move an item off its label's tier:
#   - Quality floor: a quality worker on an item carrying one of the
#     QUALITY_FLOOR_LABELS (default: area:agentic, agentic, agent-ops,
#     area:eval — matched case-insensitively) runs at standard or above. A
#     wrong PASS on agent work is the cheapest to make and the most
#     expensive to find. Set QUALITY_FLOOR_LABELS to replace the default
#     list (not add to it) for a repo whose agentic work uses other labels.
#   - Escalation: an engineer rework (--fails 1 or more) runs one tier above
#     the label, capped at deep. A build that failed QA gets more model, not
#     the same model again.
#
# A value this script cannot read is refused, never replaced by the default:
# a second tier label, a tier: label it does not know (including one that
# is tier:light/standard/deep in any other case, e.g. TIER:LIGHT), an
# unknown role or argument, a --fails that is not a whole number, or
# --fails for the quality role. Running a tier nobody chose, silently, is
# the weakened-default failure
# (feedback/architecture/weakening-a-default-must-signal.md).
#
# Usage:  pick-worker.sh --role engineer|quality --labels "a,b,c" [--fails N]
#         --labels is the item's labels, comma-separated ("" for none).
#         --fails is the number of QA FAIL verdicts on the item (default 0).
#         QUALITY_FLOOR_LABELS (env, optional) overrides the default quality
#         floor label list above; comma-separated, matched case-insensitively.
# Stdout: the worker name; its definition is agents/<name>.md.
# Exit 0: picked. Exit 2: refused (cause on stderr).
set -uo pipefail

USAGE='pick-worker.sh --role engineer|quality --labels "a,b" [--fails N]'
refuse() { echo "pick-worker: $1" >&2; exit 2; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

role="" labels="" fails=0 have_labels=0 have_fails=0
while [ $# -gt 0 ]; do
  case "$1" in
    --role)   [ $# -ge 2 ] || refuse "--role needs a value"; role="$2"; shift 2 ;;
    --labels) [ $# -ge 2 ] || refuse "--labels needs a value (\"\" for an item with no labels)"; labels="$2"; have_labels=1; shift 2 ;;
    --fails)  [ $# -ge 2 ] || refuse "--fails needs a value"; fails="$2"; have_fails=1; shift 2 ;;
    *) refuse "unknown argument '$1' (usage: $USAGE)" ;;
  esac
done

case "$role" in
  engineer|quality) ;;
  "") refuse "--role is required (engineer or quality)" ;;
  *)  refuse "--role '$role' is not engineer or quality" ;;
esac
[ "$have_labels" -eq 1 ] || refuse "--labels is required (\"\" for an item with no labels)"
case "$fails" in
  ''|*[!0-9]*) refuse "--fails '$fails' is not a whole number" ;;
esac
[ "${#fails}" -le 3 ] || refuse "--fails '$fails' has more than 3 digits"
if [ "$have_fails" -eq 1 ] && [ "$role" = quality ]; then
  refuse "--fails applies to --role engineer only; a verifier's tier does not escalate"
fi

floor_labels="${QUALITY_FLOOR_LABELS:-area:agentic,agentic,agent-ops,area:eval}"
floor_items=()
IFS=',' read -r -a floor_items <<< "$floor_labels"
floor_lc=()
for fl in "${floor_items[@]+"${floor_items[@]}"}"; do
  floor_lc+=("$(lower "$(trim "$fl")")")
done

tier="" agentic=0
items=()
[ -z "$labels" ] || IFS=',' read -r -a items <<< "$labels"
for raw in "${items[@]+"${items[@]}"}"; do
  label="$(trim "$raw")"
  lc="$(lower "$label")"
  case "$lc" in
    tier:light|tier:standard|tier:deep)
      [ "$label" = "$lc" ] || refuse "'$label' is not a tier (tier:light, tier:standard or tier:deep)"
      [ -z "$tier" ] || refuse "more than one tier label (tier:$tier and $label); an item carries one"
      tier="${lc#tier:}"
      ;;
    tier:*)
      refuse "'$label' is not a tier (tier:light, tier:standard or tier:deep)"
      ;;
    *)
      for fl in "${floor_lc[@]+"${floor_lc[@]}"}"; do
        [ "$lc" = "$fl" ] || continue
        agentic=1
        break
      done
      ;;
  esac
done

case "${tier:-standard}" in
  light)    level=0 ;;
  standard) level=1 ;;
  deep)     level=2 ;;
esac
if [ "$role" = quality ] && [ "$agentic" -eq 1 ] && [ "$level" -lt 1 ]; then
  level=1
fi
if [ "$role" = engineer ] && [ "$((10#$fails))" -ge 1 ] && [ "$level" -lt 2 ]; then
  level=$((level + 1))
fi

case "$level" in
  0) echo "$role-worker-light" ;;
  1) echo "$role-worker" ;;
  2) echo "$role-worker-deep" ;;
esac
