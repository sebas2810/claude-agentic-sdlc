#!/usr/bin/env bash
#
# check-worker-definitions.sh: every worker definition still carries the seat
# rules it must carry, and every rule file it names still exists
# (workflow/fresh-context-workers.md).
#
# Why this exists: a worker subagent loads no personal memory and none of the
# seat's conversation. The only rules it follows are the files its definition
# tells it to read. Drop one from the list, or rename the file, and the worker
# still runs and still reports while no longer holding that rule. Nothing else
# would notice.
#
# For each worker below, agents/<worker>.md must:
#   - exist and be readable
#   - open with frontmatter whose name: is <worker> and whose description: is set
#   - set model: and effort: to its tier (workflow/fresh-context-workers.md,
#     "Tiers"): <role>-worker-light sonnet/low, <role>-worker opus/medium,
#     <role>-worker-deep opus/high. onboarding/lib/pick-worker.sh starts a worker
#     for its tier, so a definition at another model runs every item of that
#     tier at a cost or a depth nobody chose.
#   - have a "## Rules you carry" section
#   - list every required path for that worker as a "- `path`" item there (a
#     tier variant's one required path is its base worker's definition)
#   - have every "- `path`" item in that section resolve to a file
#   - have every repo path its text names in backticks resolve to a file: a
#     token inside `...` shaped like dir/file.ext (a step that runs
#     `onboarding/lib/x.sh --flag`, a pointer to `skills/INDEX.md`). Delete the
#     file and the worker still follows the step. Fenced code blocks are skipped.
#
# Every path is relative to the framework root. A path with a '..' segment
# climbs out of it and an absolute path ignores it, so both are findings even
# when they resolve: they point at files this framework does not ship. (In the
# text, only the '..' form is read as a path; an absolute path there is not a
# repo path and is not checked.)
#
# Usage:  check-worker-definitions.sh [framework-root]   (default: this checkout)
# Exit 0: every worker conforms.
# Exit 1: findings, each named on stderr.
# Exit 2: usage or IO error (a root that is not a directory, an unreadable file).
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
[ -d "$ROOT" ] || { echo "check-worker-definitions: framework root is not a directory: $ROOT" >&2; exit 2; }

WORKERS="engineer-worker quality-worker engineer-worker-light engineer-worker-deep quality-worker-light quality-worker-deep"

# tier_frontmatter <worker>: the "model effort" its tier sets.
tier_frontmatter() {
  case "$1" in
    *-worker-light) echo "sonnet low" ;;
    *-worker-deep)  echo "opus high" ;;
    *)              echo "opus medium" ;;
  esac
}

required_rules() {
  case "$1" in
    *-worker-light|*-worker-deep) echo "agents/${1%-*}.md" ;;
    engineer-worker) cat <<'EOF'
seats/engineer/KICKOFF.md
commands/check.md
workflow/fresh-context-workers.md
skills/delivery-check/SKILL.md
feedback/workflow/author-is-the-ownership-boundary.md
feedback/workflow/audit-pr-history-before-pickup.md
feedback/workflow/seat-label-mirror.md
feedback/workflow/read-back-unlinked-board-via-node-query.md
feedback/workflow/a-slice-landing-does-not-make-the-item-merged.md
feedback/workflow/always-rebase-before-push.md
feedback/workflow/run-oversight-gates-locally.md
feedback/workflow/no-claude-attribution.md
feedback/workflow/deployed-env-smoke-before-ready.md
feedback/workflow/engineer-ready-signal.md
feedback/workflow/a-check-must-be-able-to-report-its-own-failure.md
feedback/workflow/finish-report-stop.md
feedback/architecture/no-silent-degradation-on-load-bearing-paths.md
EOF
      ;;
    quality-worker) cat <<'EOF'
seats/quality-engineer/KICKOFF.md
commands/check.md
workflow/fresh-context-workers.md
operations/metrics/returns.md
feedback/workflow/author-is-the-ownership-boundary.md
feedback/workflow/ac-must-name-who-can-satisfy-it.md
feedback/workflow/deployed-env-smoke-before-ready.md
feedback/workflow/a-null-result-is-not-evidence.md
feedback/workflow/a-check-must-be-able-to-report-its-own-failure.md
feedback/workflow/seat-label-mirror.md
feedback/workflow/read-back-unlinked-board-via-node-query.md
feedback/workflow/a-slice-landing-does-not-make-the-item-merged.md
feedback/workflow/live-eval-owns-its-teardown.md
feedback/workflow/finish-report-stop.md
EOF
      ;;
    *) echo "check-worker-definitions: no required-rule list for worker '$1'" >&2; exit 2 ;;
  esac
}

findings=0
finding() { printf '  %s\n' "$1" >&2; findings=$((findings + 1)); }

# check_ref <definition> <lists|mentions> <path>: a finding unless the path is
# repo-relative, stays inside the framework root, and resolves to a file.
check_ref() {
  local rel="$1" how="$2" path="$3"
  case "$path" in
    /*) finding "$rel: $how \`$path\`, an absolute path (paths are relative to the framework root)"; return ;;
  esac
  case "/$path/" in
    */../*) finding "$rel: $how \`$path\`, which climbs out of the framework root with '..'"; return ;;
  esac
  [ -f "$ROOT/$path" ] || finding "$rel: $how \`$path\`, which does not resolve to a file"
}

# body_paths <file>: the repo paths a definition's text names in backticks,
# outside the frontmatter, fenced code blocks and the rules list itself.
body_paths() {
  awk '
    NR == 1 && $0 == "---" { front = 1; next }
    front { if ($0 == "---") front = 0; next }
    /^```/ { fence = !fence; next }
    fence { next }
    /^## / { rules = ($0 ~ /^## Rules you carry[[:space:]]*$/) }
    rules && /^- `/ { next }
    { print }
  ' "$1" \
    | grep -o '`[^`]*`' | tr -d '`' | tr -s '[:blank:]' '\n' \
    | grep -E '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+$' | grep -E '/[^/]*[^./][^/]*\.[A-Za-z0-9]+$' \
    | sort -u
}

for worker in $WORKERS; do
  rel="agents/$worker.md"
  file="$ROOT/$rel"
  if [ ! -e "$file" ]; then
    finding "$rel: missing (the drains start this worker, so it needs a definition)"
    continue
  fi
  [ -r "$file" ] || { echo "check-worker-definitions: cannot read $rel" >&2; exit 2; }

  front="$(awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit } { print }' "$file")"
  name="$(printf '%s\n' "$front" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  description="$(printf '%s\n' "$front" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  [ "$name" = "$worker" ] || finding "$rel: frontmatter name is '$name', expected '$worker'"
  [ -n "$description" ] || finding "$rel: frontmatter has no description"
  model="$(printf '%s\n' "$front" | sed -n 's/^model:[[:space:]]*//p' | head -1)"
  effort="$(printf '%s\n' "$front" | sed -n 's/^effort:[[:space:]]*//p' | head -1)"
  read -r want_model want_effort <<< "$(tier_frontmatter "$worker")"
  [ "$model" = "$want_model" ] || finding "$rel: frontmatter model is '$model', expected '$want_model' for its tier"
  [ "$effort" = "$want_effort" ] || finding "$rel: frontmatter effort is '$effort', expected '$want_effort' for its tier"

  if ! grep -q '^## Rules you carry[[:space:]]*$' "$file"; then
    finding "$rel: no '## Rules you carry' section, so the worker carries no rules"
    continue
  fi
  section="$(awk '/^## Rules you carry[[:space:]]*$/ { on = 1; next } on && /^## / { exit } on { print }' "$file")"
  listed="$(printf '%s\n' "$section" | sed -n 's/^- `\([^`]*\)`.*/\1/p')"
  [ -n "$listed" ] || finding "$rel: '## Rules you carry' lists no rule files"

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    check_ref "$rel" lists "$path"
  done <<< "$listed"

  mentioned="$(body_paths "$file")"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf '%s\n' "$listed" | grep -qxF -- "$path" && continue
    check_ref "$rel" mentions "$path"
  done <<< "$mentioned"

  required="$(required_rules "$worker")" || exit 2
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf '%s\n' "$listed" | grep -qxF -- "$path" || finding "$rel: no longer lists required rule \`$path\`"
  done <<< "$required"
done

if [ "$findings" -gt 0 ]; then
  echo "check-worker-definitions: $findings finding(s) above" >&2
  exit 1
fi
echo "check-worker-definitions: every worker definition carries its rules ($WORKERS)"
exit 0
