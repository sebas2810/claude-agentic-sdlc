#!/usr/bin/env bash
#
# Both-directions test for setup-seat.sh's idempotent settings write (#76
# AC4).
#
# The defect it guards: setup-seat.sh appended a new SessionStart hook entry
# on every run instead of replacing the one it owns. Real-world worktrees
# were found carrying 12 to 19 duplicate copies of the same seat-brief cat
# hook — harmless individually (each just re-prints the same file), but each
# extra copy is dead weight on every session start, and the append-only
# write pattern that produced them is the same shape of bug this suite
# exists to catch generally: a control that "worked" (the hook fired) while
# silently getting worse every time it ran.
#
# Also covers the settings this same story adds: autoCompactWindow refuses
# an out-of-range value instead of writing it (Claude Code silently ignores
# one outside [100000, 1000000] — a bad value must fail loud, here, rather
# than "work" and do nothing), disableClaudeAiConnectors defaults true and
# is overridable, a statusLine gets wired, and ScheduleWakeup/CronCreate are
# denied — all without disturbing a key this script doesn't own.
#
# Usage: setup-seat-settings.test.sh <path-to-setup-seat.sh>
set -uo pipefail

SETUP="${1:-}"
[ -n "$SETUP" ] || { echo "usage: $0 <path-to-setup-seat.sh>" >&2; exit 1; }
case "$SETUP" in /*) ;; *) SETUP="$(cd "$(dirname "$SETUP")" && pwd)/$(basename "$SETUP")" ;; esac
[ -f "$SETUP" ] || { echo "no such script: $SETUP" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required to run this test" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }

# A fresh scratch git repo at $T/<name>, a minimal .env.local, and any extra
# KEY=VALUE lines appended to it. Prints the repo path.
fresh_repo() { # $1 = name, $2... = extra .env.local lines
  local name="$1"; shift
  local repo="$T/$name"
  mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.email ci@example.com
  git -C "$repo" config user.name ci
  {
    echo "INSTANCE=test"
    echo "SEAT_ROLE=engineer"
    echo "SEAT_NAME=Testy"
    echo 'GIT_USER_NAME="Test Seat"'
    echo 'GIT_USER_EMAIL="test@example.com"'
    for line in "$@"; do echo "$line"; done
  } > "$repo/.env.local"
  printf '%s' "$repo"
}

# Isolated invocation: an ambient SDLC_FRAMEWORK_DIR / INSTANCE / etc. in the
# CALLER's shell must never leak into what the script under test resolves —
# that is a property of the CALLER's environment, not of setup-seat.sh, and
# a test that inherited it would pass or fail by accident of who ran it.
run_setup() { # $1 = repo dir
  ( cd "$1" && env -i PATH="$PATH" HOME="${HOME:-/tmp}" bash "$SETUP" >/dev/null 2>&1 )
}

SETTINGS_REL=".claude/settings.local.json"

# 1. Run twice — byte-identical (the story's own falsifiable bar).
r="$(fresh_repo case1)"
run_setup "$r"
cp "$r/$SETTINGS_REL" "$T/run1.json"
run_setup "$r"
if diff -q "$T/run1.json" "$r/$SETTINGS_REL" >/dev/null; then
  ok "running setup-seat.sh twice leaves settings.local.json byte-identical"
else
  bad "second run changed settings.local.json — not idempotent"
fi

# 2. A duplicated / corrupted SessionStart hook set — the actual incident —
# collapses to exactly one seat-brief entry, and an UNRELATED hook survives.
r="$(fresh_repo case2)"
mkdir -p "$r/.claude"
cat > "$r/$SETTINGS_REL" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "cat \"$CLAUDE_PROJECT_DIR/.${INSTANCE}-seat.md\" 2>/dev/null || true"}]},
      {"hooks": [{"type": "command", "command": "cat \"$CLAUDE_PROJECT_DIR/.test-seat.md\" 2>/dev/null || true"}]},
      {"hooks": [{"type": "command", "command": "cat \"$CLAUDE_PROJECT_DIR/.test-seat.md\" 2>/dev/null || true"}]},
      {"matcher": "clear", "hooks": [{"type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-start.mjs", "timeout": 30}]}
    ]
  }
}
EOF
run_setup "$r"
seat_hooks="$(jq '[.hooks.SessionStart[] | select(.hooks[0].command | test("-seat\\.md"))] | length' "$r/$SETTINGS_REL")"
clear_hooks="$(jq '[.hooks.SessionStart[] | select(.matcher == "clear")] | length' "$r/$SETTINGS_REL")"
if [ "$seat_hooks" = "1" ] && [ "$clear_hooks" = "1" ]; then
  ok "3 duplicate/corrupted seat-brief hooks collapse to 1, unrelated 'clear' hook survives"
else
  bad "expected exactly 1 seat-brief hook + 1 clear hook, got seat=$seat_hooks clear=$clear_hooks"
fi

# 3. Unrelated top-level and permissions.allow entries survive untouched.
r="$(fresh_repo case3)"
mkdir -p "$r/.claude"
cat > "$r/$SETTINGS_REL" <<'EOF'
{"permissions": {"allow": ["Bash(aws ecs execute-command *)"]}, "someUnrelatedKey": "keep-me"}
EOF
run_setup "$r"
allow_kept="$(jq -r '.permissions.allow == ["Bash(aws ecs execute-command *)"]' "$r/$SETTINGS_REL")"
key_kept="$(jq -r '.someUnrelatedKey == "keep-me"' "$r/$SETTINGS_REL")"
if [ "$allow_kept" = "true" ] && [ "$key_kept" = "true" ]; then
  ok "permissions.allow and an unrelated top-level key survive untouched"
else
  bad "a key this script doesn't own was dropped or changed (allow_kept=$allow_kept key_kept=$key_kept)"
fi

# 4. autoCompactWindow: unset -> default 250000.
r="$(fresh_repo case4)"
run_setup "$r"
window="$(jq -r '.autoCompactWindow' "$r/$SETTINGS_REL")"
[ "$window" = "250000" ] && ok "autoCompactWindow defaults to 250000 when unset" \
  || bad "expected default autoCompactWindow=250000, got $window"

# 5. autoCompactWindow: an out-of-range override (too low AND too high) is
# REFUSED — Claude Code silently ignores it, so writing it would "work" and
# do nothing; refusing it here is the loud failure that's actually useful.
r="$(fresh_repo case5-low "AUTO_COMPACT_WINDOW=50")"
run_setup "$r"
window="$(jq -r '.autoCompactWindow' "$r/$SETTINGS_REL")"
[ "$window" = "250000" ] && ok "an out-of-range LOW autoCompactWindow (50) is refused, default written" \
  || bad "expected the low out-of-range override refused (250000), got $window"

r="$(fresh_repo case5-high "AUTO_COMPACT_WINDOW=5000000")"
run_setup "$r"
window="$(jq -r '.autoCompactWindow' "$r/$SETTINGS_REL")"
[ "$window" = "250000" ] && ok "an out-of-range HIGH autoCompactWindow (5000000) is refused, default written" \
  || bad "expected the high out-of-range override refused (250000), got $window"

# 6. autoCompactWindow: a VALID in-range override is honoured, not forced to
#    the default — only OUT-OF-RANGE values are refused.
r="$(fresh_repo case6 "AUTO_COMPACT_WINDOW=500000")"
run_setup "$r"
window="$(jq -r '.autoCompactWindow' "$r/$SETTINGS_REL")"
[ "$window" = "500000" ] && ok "a valid in-range autoCompactWindow override (500000) is honoured" \
  || bad "expected the valid override honoured (500000), got $window"

# 7. disableClaudeAiConnectors: defaults true, overridable to false.
r="$(fresh_repo case7)"
run_setup "$r"
val="$(jq -r '.disableClaudeAiConnectors' "$r/$SETTINGS_REL")"
[ "$val" = "true" ] && ok "disableClaudeAiConnectors defaults to true" \
  || bad "expected default disableClaudeAiConnectors=true, got $val"

r="$(fresh_repo case7-override "DISABLE_CLAUDE_AI_CONNECTORS=false")"
run_setup "$r"
val="$(jq -r '.disableClaudeAiConnectors' "$r/$SETTINGS_REL")"
[ "$val" = "false" ] && ok "disableClaudeAiConnectors=false override is honoured" \
  || bad "expected the override honoured (false), got $val"

# 8. permissions.deny carries ScheduleWakeup + CronCreate, and a pre-existing
#    custom deny entry survives alongside them (not replaced).
r="$(fresh_repo case8)"
mkdir -p "$r/.claude"
printf '{"permissions": {"deny": ["Bash(rm -rf /)"]}}\n' > "$r/$SETTINGS_REL"
run_setup "$r"
has_sw="$(jq -r '.permissions.deny | index("ScheduleWakeup") != null' "$r/$SETTINGS_REL")"
has_cc="$(jq -r '.permissions.deny | index("CronCreate") != null' "$r/$SETTINGS_REL")"
has_custom="$(jq -r '.permissions.deny | index("Bash(rm -rf /)") != null' "$r/$SETTINGS_REL")"
if [ "$has_sw" = "true" ] && [ "$has_cc" = "true" ] && [ "$has_custom" = "true" ]; then
  ok "permissions.deny gains ScheduleWakeup + CronCreate, keeps a pre-existing custom entry"
else
  bad "permissions.deny missing an expected entry (sw=$has_sw cc=$has_cc custom=$has_custom)"
fi

# 9. statusLine is wired as a command pointing at seat-statusline.sh.
r="$(fresh_repo case9)"
run_setup "$r"
type="$(jq -r '.statusLine.type' "$r/$SETTINGS_REL")"
cmd="$(jq -r '.statusLine.command' "$r/$SETTINGS_REL")"
case "$cmd" in
  *seat-statusline.sh*) statusline_ok=1 ;;
  *) statusline_ok=0 ;;
esac
if [ "$type" = "command" ] && [ "$statusline_ok" = "1" ]; then
  ok "statusLine is wired as a command pointing at seat-statusline.sh"
else
  bad "statusLine not wired as expected (type=$type command=$cmd)"
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "setup-seat-settings: all checks passed"
else
  echo "setup-seat-settings: $fails check(s) FAILED" >&2
fi
exit "$fails"
