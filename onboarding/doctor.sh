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

if [ "$FAIL" -eq 0 ]
then echo "✓ parity: labels match the $CFG roster"
else echo "✗ drift found — fix the above before the next /check"
fi
exit "$FAIL"
