#!/usr/bin/env bash
#
# Both-directions test: the seat launcher must never start a session with the
# permission gate disabled.
#
# Why this exists (2026-08-10 → 2026-08-12): seat-launch.sh launched every seat
# with `--permission-mode acceptEdits`. A PR replaced it with
# `--dangerously-skip-permissions`, on the premise that the flag had been removed
# from the CLI. The premise was false — the flag was present the whole time. For
# ~53 hours every seat in every vendoring instance launched with no permission
# gate. Nothing caught it: this file had no test at all, the change was the
# smaller half of a PR about something else, and the file is vendored, so the
# blast radius was invisible on the PR's face.
#
# It asserts POSTURE, not one string: any mode that disables the gate fails,
# whatever it is called, and an invocation carrying no explicit mode fails too.
#
# Rule: feedback/architecture/weakening-a-default-must-signal.md
set -uo pipefail

LAUNCHER="${1:-}"
[ -n "$LAUNCHER" ] || { echo "usage: $0 <path-to-seat-launch.sh>" >&2; exit 1; }
[ -f "$LAUNCHER" ] || { echo "no such launcher: $LAUNCHER" >&2; exit 1; }

# Modes/flags that start a session with the gate off. Add to this list, never remove.
DISABLING='--dangerously-skip-permissions|--permission-mode[[:space:]=]+(bypassPermissions|dontAsk)'
# An explicit permission mode must be present — omitting it is not "the default is
# fine", it is an unstated posture that a CLI default change can silently flip.
EXPLICIT='--permission-mode[[:space:]=]+[A-Za-z]'

fails=0
ok()   { printf '  OK    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# The line that actually starts the session.
launch="$(grep -E '^[[:space:]]*exec[[:space:]]+claude' "$LAUNCHER" || true)"

echo "── the launcher's own posture ──"
if [ -z "$launch" ]; then
  bad "no 'exec claude' invocation found in $LAUNCHER — cannot verify posture"
else
  if printf '%s' "$launch" | grep -qE -- "$DISABLING"; then
    bad "launcher starts sessions with the permission gate DISABLED: $launch"
  else
    ok "no permission-disabling flag in the launch invocation"
  fi

  if printf '%s' "$launch" | grep -qE -- "$EXPLICIT"; then
    ok "an explicit --permission-mode is set"
  else
    bad "no explicit --permission-mode — posture is implicit and can flip under a CLI default change"
  fi
fi

# Both directions: assertions that cannot fail are not evidence. Feed the checks
# the exact line from the incident and require them to reject it.
echo "── the check must reject the known-bad line (anti-tautology) ──"
BAD_LINE='exec claude "${MODEL_FLAG[@]}" --dangerously-skip-permissions "$PROMPT"'
if printf '%s' "$BAD_LINE" | grep -qE -- "$DISABLING"; then
  ok "the 2026-08-10 regression line is detected as disabling"
else
  bad "the regression line was NOT detected — this gate would not have caught the incident it exists for"
fi

BAD_LINE2='exec claude "${MODEL_FLAG[@]}" "$PROMPT"'
if printf '%s' "$BAD_LINE2" | grep -qE -- "$EXPLICIT"; then
  bad "an invocation with no --permission-mode was accepted as explicit"
else
  ok "an invocation with no explicit mode is rejected"
fi

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $((fails > 0))
