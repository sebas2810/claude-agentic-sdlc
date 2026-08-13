#!/usr/bin/env bash
#
# doctor.sh — the parity gate: sdlc.config IS the roster; verify the repo's
# label taxonomy matches it. Catches the drift class where identity exists by
# convention only: a configured producer seat with no routing lane, a foreign
# seat:* label masquerading as a queue (another squad in the same repo?), a
# status:* index entry missing so a whole state is invisible to /check.
#
# sdlc.config stays the single machine-readable roster — deliberately no
# second seats.json to drift from it.
#
# Read-only against GitHub. Exit 0 = parity; exit 1 = drift (each ✗ printed).
#
# Usage: onboarding/doctor.sh [path/to/sdlc.config]     (default: ./sdlc.config)
set -euo pipefail

CFG="${1:-sdlc.config}"
[ -f "$CFG" ] || { echo "config not found: $CFG" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CFG"
: "${REPO:?REPO not set in $CFG}" ; : "${SEATS:?SEATS not set in $CFG}"

FAIL=0
ok()  { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s\n' "$1"; FAIL=1; }

echo "→ parity gate: $CFG vs $REPO"
LABELS="$(gh label list --repo "$REPO" -L 200 --json name --jq '.[].name')"

# 1. every configured PRODUCER seat has its seat:<key> routing lane label
#    (pm / scrum-master / quality-engineer drain by status: no lane by design)
EXPECTED=""
for pair in $SEATS; do
  role="${pair%%:*}" ; rest="${pair#*:}" ; name="${rest%%:*}"
  case "$role" in pm|scrum-master|quality-engineer) continue ;; esac
  key="$(printf '%s' "$name" | tr '[:upper:] ' '[:lower:]-')"
  EXPECTED="$EXPECTED seat:$key"
  if printf '%s\n' "$LABELS" | grep -qx "seat:$key"
  then ok "lane seat:$key ($name, $role)"
  else bad "MISSING lane seat:$key ($name, $role) — this producer's /check queue does not exist; re-run bootstrap.sh"
  fi
done

# 2. every seat:* label in the repo maps back to a configured seat — a foreign
#    lane is another squad's (or a retired seat's); label-only filters would
#    surface its work as yours. Either way: loud.
while IFS= read -r l; do
  [ -n "$l" ] || continue
  case " $EXPECTED " in *" $l "*) ;; *)
    bad "FOREIGN lane $l — maps to no seat in $CFG (another squad in this repo? a retired seat?)" ;;
  esac
done <<EOF
$(printf '%s\n' "$LABELS" | grep '^seat:' || true)
EOF

# 3. the status:* discovery index is complete — a missing entry hides a STATE
for s in backlog scoped in-progress delivered tested merged released blocked cancelled; do
  if printf '%s\n' "$LABELS" | grep -qx "status:$s"
  then ok "index status:$s"
  else bad "MISSING status:$s — items in this state are invisible to every /check; re-run bootstrap.sh"
  fi
done

# 3. exactly ONE push-intercepting PreToolUse hook.
#    A forked second guard drifts silently — it keeps blocking the obvious cases
#    while quietly losing a rule the other copy learned, and every signal stays
#    green. One instance ran a fork that had lost the pre-verb bypass fix, so
#    "never push to a protected ref" did not exist for `git -C <dir> push`, and
#    nothing noticed until a human read the file.
#    feedback/architecture/one-control-one-implementation.md
echo "PreToolUse guard:"
SETTINGS=".claude/settings.json"
if [ ! -f "$SETTINGS" ]; then
  bad "no $SETTINGS — the git guard is not wired at all; re-run bootstrap.sh"
elif ! command -v jq >/dev/null 2>&1; then
  ok "skipped (jq not installed)"
else
  HOOKS="$(jq -r '[.hooks.PreToolUse[]?.hooks[]?.command // empty] | .[]' "$SETTINGS" 2>/dev/null)"
  GITHOOKS="$(printf '%s\n' "$HOOKS" | grep -c 'guard-git\|bash-guard' || true)"
  case "$GITHOOKS" in
    0) bad "no push-intercepting hook wired in $SETTINGS — the non-negotiables are documented but not enforced" ;;
    1) if printf '%s\n' "$HOOKS" | grep -q 'guard-git.sh'
       then ok "exactly one push-intercepting hook, and it is the framework guard"
       else bad "exactly one push-intercepting hook, but it is NOT guard-git.sh — a forked guard is untested by this framework and drifts silently" ; fi ;;
    *) bad "$GITHOOKS push-intercepting hooks wired — two guards on one tool WILL drift; consolidate onto guard-git.sh" ;;
  esac
fi

if [ "$FAIL" -eq 0 ]
then echo "✓ parity: labels match the $CFG roster"
else echo "✗ drift found — fix the above before the next /check"
fi
exit "$FAIL"
