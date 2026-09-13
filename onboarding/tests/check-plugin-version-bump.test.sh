#!/usr/bin/env bash
#
# Both-directions test for check-plugin-version-bump.sh (#77): a change to shipped plugin content
# (commands, skills, agents, hooks, the manifest) must raise plugin.json's version, or installed
# caches keep serving the old commands. Every case builds a throwaway repository, so the check runs
# against real git history, not a mocked diff.
#
# Usage: check-plugin-version-bump.test.sh <path-to-check-plugin-version-bump.sh>
set -uo pipefail

CHECK="${1:-}"
[ -n "$CHECK" ] && [ -f "$CHECK" ] || { echo "usage: $0 <path-to-check-plugin-version-bump.sh>" >&2; exit 2; }
CHECK="$(cd "$(dirname "$CHECK")" && pwd)/$(basename "$CHECK")"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
R="$T/repo"
fails=0
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
g()   { git -C "$R" -c user.name=t -c user.email=t@example.com "$@"; }
manifest() { printf '{\n  "name": "agentic-sdlc",\n  "version": "%s",\n  "commands": "./commands"\n}\n' "$1" > "$R/.claude-plugin/plugin.json"; }

git init -qb main "$R"
mkdir -p "$R/.claude-plugin" "$R/commands" "$R/skills/review" "$R/agents" "$R/onboarding/hooks"
manifest 1.4.2
echo "check v1"  > "$R/commands/check.md"
echo "skill v1"  > "$R/skills/review/SKILL.md"
echo "guard v1"  > "$R/onboarding/hooks/guard-git.sh"
echo "test v1"   > "$R/onboarding/hooks/guard-git.test.sh"
echo "readme v1" > "$R/README.md"
g add -A && g commit -qm base

OUT="" ; RC=0
# run_case <description> <expected exit> <base-ref> <change...>: a fresh branch off main, apply
# the change, commit, run the check from inside the repository.
run_case() {
  local desc="$1" want="$2" base="$3"; shift 3
  g checkout -q -B case main
  "$@"
  g add -A && g commit -qm "$desc" --allow-empty
  OUT="$(cd "$R" && bash "$CHECK" "$base" 2>&1)"; RC=$?
  if [ "$RC" = "$want" ]; then ok "$desc -> exit $RC"
  else bad "$desc -> exit $RC, expected $want"; printf '%s\n' "$OUT" | sed 's/^/        /'; fi
}
edit_command()      { echo "more" >> "$R/commands/check.md"; }
edit_skill()        { echo "more" >> "$R/skills/review/SKILL.md"; }
edit_hook()         { echo "more" >> "$R/onboarding/hooks/guard-git.sh"; }
edit_hook_test()    { echo "more" >> "$R/onboarding/hooks/guard-git.test.sh"; }
edit_readme()       { echo "more" >> "$R/README.md"; }
add_agent()         { echo "reviewer" > "$R/agents/reviewer.md"; }
command_patch()     { edit_command; manifest 1.4.3; }
skill_major()       { edit_skill; manifest 2.0.0; }
command_numeric()   { edit_command; manifest 1.4.10; }
command_lowered()   { edit_command; manifest 1.4.1; }
command_garbage()   { edit_command; manifest banana; }
command_no_manifest(){ edit_command; rm "$R/.claude-plugin/plugin.json"; }

echo "── shipped change without a higher version fails ──"
run_case "a command changes, version unchanged" 1 main edit_command
case "$OUT" in *commands/check.md*) ok "the failure names the changed file" ;; *) bad "the failure does not name commands/check.md" ;; esac
case "$OUT" in *"NOT raised"*) ok "the failure says the version was not raised" ;; *) bad "the failure does not say NOT raised" ;; esac
run_case "a hook script changes, version unchanged" 1 main edit_hook
run_case "an agent is added, version unchanged" 1 main add_agent
run_case "a command changes, version lowered" 1 main command_lowered

echo "── a raised version, or no shipped change, passes ──"
run_case "a command changes, patch bump" 0 main command_patch
run_case "a skill changes, major bump" 0 main skill_major
run_case "a command changes, 1.4.2 -> 1.4.10 (numeric, not string, comparison)" 0 main command_numeric
run_case "only a hook TEST changes" 0 main edit_hook_test
run_case "only the README changes" 0 main edit_readme

echo "── could not determine: exit 2 with the cause named, never a pass ──"
run_case "the base ref does not exist" 2 no-such-ref edit_command
case "$OUT" in *no-such-ref*) ok "names the missing base ref" ;; *) bad "does not name the missing base ref" ;; esac
run_case "the version at HEAD is not MAJOR.MINOR.PATCH" 2 main command_garbage
case "$OUT" in *banana*) ok "names the bad version" ;; *) bad "does not name the bad version" ;; esac
run_case "plugin.json is missing at HEAD" 2 main command_no_manifest
OUT="$(cd "$T" && bash "$CHECK" main 2>&1)"; RC=$?
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q 'not inside a git repository'; then ok "outside a repository -> exit 2, named"
else bad "outside a repository -> exit $RC: $OUT"; fi

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES: $fails"; fi
exit $((fails > 0))
