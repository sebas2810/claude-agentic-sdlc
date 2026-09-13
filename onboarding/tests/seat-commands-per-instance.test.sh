#!/usr/bin/env bash
#
# seat-commands-per-instance.test.sh — each seat runs ITS OWN instance's /check (#77).
#
# Claude Code resolves a /name clash "enterprise over personal, and personal over project", and a
# skill over a command file (code.claude.com/docs/en/skills). The old launchers copied every
# instance's commands into ~/.claude/commands, so the instance launched last decided /check for all
# of them: one day every seat of one instance ran a stale /check without --include-prs.
#
# Offline: an isolated HOME, stub `claude`, `docker` and `gh`, and two fake product repos that each
# vendor THIS framework checkout with their own marker in commands/check.md. Both seats are launched
# through the real seat-launch.sh, one after the other, and each seat's EFFECTIVE /check (resolved
# with the precedence above) must be its own instance's copy. Then: relaunch idempotency, a stale
# personal copy named by the launcher and by doctor.sh, a tracked product command left untouched,
# and unreadable input reported as an error.
#
# Usage: seat-commands-per-instance.test.sh [framework-checkout]     (default: this checkout)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW="$(cd "${1:-$HERE/../..}" && pwd)"
[ -f "$FW/onboarding/seat-launch.sh" ] || { echo "no onboarding/seat-launch.sh under $FW" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required (setup-seat.sh uses it)" >&2; exit 2; }

T="$(mktemp -d -t seat-commands.XXXXXX)"
trap 'rm -rf "$T"' EXIT
fails=0
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
gitc(){ git -c user.name=t -c user.email=t@example.com "$@"; }

mkdir -p "$T/home" "$T/bin"
cat > "$T/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$STUB_LOG"
exit 0
STUB
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/docker"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "label list") printf '%s\n' status:backlog status:scoped status:in-progress status:delivered \
                  status:tested status:merged status:released status:blocked status:cancelled seat:finn ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$T/bin/claude" "$T/bin/docker" "$T/bin/gh"
export STUB_LOG="$T/claude.log"

# make_instance <key>: $T/<key>-prod vendors the framework (own check.md marker); $T/<key>-seat is its seat
make_instance() {
  local k="$1" prod="$T/$1-prod" seat="$T/$1-seat"
  git init -qb main "$prod"
  mkdir "$prod/agentic-sdlc"
  tar -C "$FW" --exclude .git --exclude node_modules -cf - . | tar -x -C "$prod/agentic-sdlc"
  printf 'instance %s check\n' "$k" > "$prod/agentic-sdlc/commands/check.md"
  gitc -C "$prod" add -A >/dev/null && gitc -C "$prod" commit -qm vendor
  git -C "$prod" worktree add -q -b "seat/$k" "$seat" main
  cat > "$seat/.env.local" <<ENV
INSTANCE=$k
SEAT_ROLE=engineer
SEAT_NAME=Finn
SEAT_MODEL=sonnet
GIT_USER_NAME="Test"
GIT_USER_EMAIL="t@example.com"
CLOUD_PROVIDER=local
ENV
}
launch() { # launch <key>: the real launcher, isolated HOME, stubs first on PATH
  ( cd "$T" && HOME="$T/home" PATH="$T/bin:$PATH" bash "$T/$1-prod/agentic-sdlc/onboarding/seat-launch.sh" --worktree "$T/$1-seat" ) 2>&1
}
doctor() { # doctor <key>: the instance's doctor.sh against a minimal config
  printf 'REPO="tester/fake"\nSEATS="engineer:Finn"\n' > "$T/sdlc.config"
  ( cd "$T" && HOME="$T/home" PATH="$T/bin:$PATH" bash "$T/$1-prod/agentic-sdlc/onboarding/doctor.sh" "$T/sdlc.config" ) 2>&1
}
effective_check() { # effective_check <key>: the file Claude Code runs for /check in that seat
  if   [ -f "$T/home/.claude/skills/check/SKILL.md" ]; then printf '%s' "$T/home/.claude/skills/check/SKILL.md"
  elif [ -f "$T/home/.claude/commands/check.md" ];     then printf '%s' "$T/home/.claude/commands/check.md"
  else printf '%s' "$T/$1-seat/.claude/commands/check.md"; fi
}

make_instance alpha
make_instance beta

echo "── two instances launched one after the other ──"
OUT_A="$(launch alpha)"; RC_A=$?
OUT_B="$(launch beta)";  RC_B=$?
if [ "$RC_A" = 0 ] && [ "$RC_B" = 0 ] && [ "$(grep -c '^claude ' "$STUB_LOG" 2>/dev/null)" = 2 ]; then
  ok "both launchers ran through to exec claude"
else
  bad "launchers did not both reach claude (alpha=$RC_A beta=$RC_B)"; printf '%s\n%s\n' "$OUT_A" "$OUT_B" | tail -20 | sed 's/^/        /'
fi
if [ -e "$T/home/.claude/commands" ]; then bad "a launcher wrote ~/.claude/commands"
else ok "nothing written under ~/.claude/commands"; fi
for k in alpha beta; do
  eff="$(effective_check "$k")"
  if cmp -s "$eff" "$T/$k-prod/agentic-sdlc/commands/check.md"; then
    ok "$k seat's effective /check is $k's own copy"
  else
    bad "$k seat's effective /check is $eff ($(head -1 "$eff" 2>/dev/null || echo missing)), not $k's own copy"
  fi
done
missing="$(cd "$T/alpha-prod/agentic-sdlc/commands" && for f in *.md; do cmp -s "$f" "$T/alpha-seat/.claude/commands/$f" || echo "$f"; done)"
if [ -z "$missing" ]; then ok "every framework command is installed in the alpha seat"
else bad "missing or different in the alpha seat: $missing"; fi
if git -C "$T/alpha-seat" status --porcelain --untracked-files=all | grep -q '\.claude/commands/'; then
  bad "installed commands show up in the seat's git status"
else ok "installed commands stay out of git status"; fi

echo "── relaunching is idempotent ──"
EXCL="$(git -C "$T/alpha-seat" rev-parse --git-path info/exclude)"
case "$EXCL" in /*) ;; *) EXCL="$T/alpha-seat/$EXCL" ;; esac
before="$(cat "$EXCL" 2>/dev/null)"
launch alpha >/dev/null
if [ -n "$before" ] && [ "$(cat "$EXCL")" = "$before" ]; then ok "info/exclude unchanged by a relaunch"
else bad "info/exclude changed by a relaunch (or was empty)"; fi
dups="$(sort "$EXCL" | uniq -d)"
if [ -z "$dups" ]; then ok "no duplicate exclude lines"; else bad "duplicate exclude lines: $dups"; fi

echo "── a stale personal copy is named by the launcher and by doctor.sh ──"
DOC="$(doctor alpha)"
if printf '%s' "$DOC" | grep -q "no personal command or skill shadows"; then ok "doctor is clean when nothing shadows"
else bad "doctor did not report a clean slash-commands check"; printf '%s\n' "$DOC" | tail -8 | sed 's/^/        /'; fi
mkdir -p "$T/home/.claude/commands"
echo "stale shared check" > "$T/home/.claude/commands/check.md"
OUT="$(launch alpha)"
if printf '%s' "$OUT" | grep -qF "$T/home/.claude/commands/check.md shadows"; then ok "the launcher names the shadowing file"
else bad "the launcher does not name the shadowing file"; fi
DOC="$(doctor alpha)"
if printf '%s' "$DOC" | grep -qF "⚠ $T/home/.claude/commands/check.md shadows this instance's /check"; then
  ok "doctor warns, naming the shadowing command file"
else bad "doctor does not name the shadowing command file"; printf '%s\n' "$DOC" | tail -8 | sed 's/^/        /'; fi
rm -f "$T/home/.claude/commands/check.md"
mkdir -p "$T/home/.claude/skills/check" && echo "personal skill" > "$T/home/.claude/skills/check/SKILL.md"
DOC="$(doctor alpha)"
if printf '%s' "$DOC" | grep -qF "⚠ $T/home/.claude/skills/check/SKILL.md shadows"; then ok "doctor also names a personal skill of the same name"
else bad "doctor does not name the shadowing personal skill"; fi
rm -rf "$T/home/.claude/skills"

echo "── the installer never overwrites a tracked command, and fails loudly on bad input ──"
INSTALL="$FW/onboarding/lib/install-seat-commands.sh"
SHADOW="$FW/onboarding/lib/check-shadowed-commands.sh"
P="$T/tracked"
git init -qb main "$P" && mkdir -p "$P/.claude/commands" && echo "product check" > "$P/.claude/commands/check.md"
gitc -C "$P" add -A && gitc -C "$P" commit -qm product
OUT="$(bash "$INSTALL" "$T/alpha-prod/agentic-sdlc" "$P" 2>&1)"; RC=$?
if [ "$RC" = 3 ]; then ok "a tracked check.md with other content -> exit 3"; else bad "tracked conflict -> exit $RC, expected 3"; fi
if [ "$(cat "$P/.claude/commands/check.md")" = "product check" ]; then ok "the tracked file is untouched"
else bad "the tracked file was overwritten"; fi
if printf '%s' "$OUT" | grep -qF "$P/.claude/commands/check.md is tracked"; then ok "the tracked file is named"
else bad "the tracked file is not named: $OUT"; fi
if [ -f "$P/.claude/commands/board.md" ]; then ok "the other commands still install"; else bad "the other commands were not installed"; fi
OUT="$(bash "$INSTALL" "$T/nowhere" "$T/alpha-seat" 2>&1)"; RC=$?
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -qF "$T/nowhere/commands"; then ok "installer: missing commands dir -> exit 2, named"
else bad "installer with a missing commands dir -> exit $RC: $OUT"; fi
OUT="$(bash "$INSTALL" "$T/alpha-prod/agentic-sdlc" "$T/no-seat" 2>&1)"; RC=$?
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -qF "$T/no-seat"; then ok "installer: missing worktree -> exit 2, named"
else bad "installer with a missing worktree -> exit $RC: $OUT"; fi
OUT="$(bash "$SHADOW" "$T/nowhere" "$T/home" 2>&1)"; RC=$?
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -qF "$T/nowhere/commands"; then ok "shadow check: missing commands dir -> exit 2, named"
else bad "shadow check with a missing commands dir -> exit $RC: $OUT"; fi

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES: $fails"; fi
exit $((fails > 0))
