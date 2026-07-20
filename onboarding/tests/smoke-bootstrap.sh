#!/usr/bin/env bash
#
# smoke-bootstrap.sh — offline end-to-end smoke test of the bootstrap golden
# path (#21). No network, no real gh: a stub gh answers every call, the
# framework checkout under test is vendored into a throwaway product repo, and
# $HOME is isolated. Asserts the config-driven run, seat naming/branching,
# lane + model resolution, the secret-safety gitignore, the expanded
# SessionStart hook, idempotent re-runs, and the wizard path.
#
# Run locally:  bash onboarding/tests/smoke-bootstrap.sh
# CI:           the `bootstrap-smoke` job in .github/workflows/ci.yml
#
# Requires: git · node · jq · tar (bootstrap's own deps, minus a real gh).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW="$(cd "$HERE/../.." && pwd)"                    # the framework checkout under test
T="$(mktemp -d -t sdlc-smoke.XXXXXX)"
trap 'rm -rf "$T"' EXIT

FAIL=0
pass(){ printf '  ok    %s\n' "$*"; }
fail(){ printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
assert_grep(){ # assert_grep <pattern> <file> <desc>
  if grep -q "$1" "$2" 2>/dev/null; then pass "$3"; else fail "$3 — pattern '$1' not in $2"; fi
}

# ── stub gh: canned answers for every call bootstrap makes ────────────────────
mkdir -p "$T/bin" "$T/home" "$T/seats"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "auth status")     exit 0 ;;
  "api graphql")     echo '{}' ;;
  "repo view")       exit 0 ;;
  "api users/tester") echo 'User' ;;
  "project list")    echo '{"projects":[{"title":"Fake — Delivery","number":42}]}' ;;
  "label create")    exit 0 ;;
  "issue list")      echo '7' ;;
  *)                 exit 0 ;;
esac
STUB
chmod +x "$T/bin/gh"

vendor_into(){ # vendor_into <product-dir> — fake product repo carrying THIS checkout
  git init -qb main "$1"
  mkdir "$1/agentic-sdlc"
  tar -C "$FW" --exclude .git --exclude node_modules -cf - . | tar -x -C "$1/agentic-sdlc"
  git -C "$1" -c user.name=t -c user.email=t@t add -A -f >/dev/null
  git -C "$1" -c user.name=t -c user.email=t@t commit -qm vendor >/dev/null
}

vendor_into "$T/prod"
cat > "$T/prod/sdlc.config" <<CFG
INSTANCE="fake"
REPO="tester/fake-prod"
OWNER="tester"
BASE="$T/seats"
SEATS="pm:Pim engineer:Finn scrum-master:Cas:haiku engineer:Dex:opus"
GIT_USER_NAME="Test User"
GIT_USER_EMAIL="t@example.com"
AWS_PROFILE=""
AWS_ACCOUNT_ID=""
SEED_EPIC="n"
BUILD_APPS="n"
CFG

run_bootstrap(){ ( cd "$T/prod" && HOME="$T/home" PATH="$T/bin:$PATH" bash agentic-sdlc/onboarding/bootstrap.sh --yes </dev/null ); }

echo "── first run (config-driven, --yes) ──"
if OUT1="$(run_bootstrap 2>&1)"; then
  pass "bootstrap exited 0"
else
  printf '%s\n' "$OUT1" | tail -15
  fail "bootstrap exited non-zero"
fi
printf '%s' "$OUT1" | grep -q "Instance 'fake' is live" && pass "completion banner" || fail "no completion banner"

# seat worktrees: named checkout, seat/<name> branch, role + model in .env.local
for spec in pim:pm:opus finn:engineer:sonnet cas:scrum-master:haiku dex:engineer:opus; do
  k="${spec%%:*}"; rest="${spec#*:}"; role="${rest%%:*}"; model="${rest#*:}"
  WT="$T/seats/fake-prod-$k"
  [ -d "$WT" ] && pass "worktree $k exists" || fail "worktree $k missing"
  [ "$(git -C "$WT" branch --show-current 2>/dev/null)" = "seat/$k" ] \
    && pass "branch seat/$k" || fail "wrong/missing branch for $k"
  assert_grep "^SEAT_ROLE=$role\$"   "$WT/.env.local" "$k role = $role"
  assert_grep "^SEAT_MODEL=$model\$" "$WT/.env.local" "$k model = $model"
done

# routing lanes: producers get seat:<name>; pm/sm/qa key off role (no lane)
assert_grep '^SEAT_LABEL=seat:finn$' "$T/seats/fake-prod-finn/.env.local" "producer lane seat:finn"
assert_grep '^SEAT_LABEL=seat:dex$'  "$T/seats/fake-prod-dex/.env.local"  "producer lane seat:dex"
assert_grep '^SEAT_LABEL=$'          "$T/seats/fake-prod-pim/.env.local"  "pm has no lane"
assert_grep '^SEAT_LABEL=$'          "$T/seats/fake-prod-cas/.env.local"  "scrum-master has no lane"

# secret safety: the PRODUCT root ignores the seat env/identity files
assert_grep '^\.env\.local$' "$T/prod/.gitignore" "root .gitignore covers .env.local"
assert_grep '^\.claude/settings\.local\.json$' "$T/prod/.gitignore" "root .gitignore covers settings.local.json"

# native start: the stored hook carries the EXPANDED instance name (a bare
# `claude` later has no INSTANCE env var — the literal filename must be baked in)
assert_grep 'fake-seat\.md' "$T/seats/fake-prod-finn/.claude/settings.local.json" "SessionStart hook expanded"

# gates: the git guard is wired at the product root
assert_grep 'guard-git' "$T/prod/.claude/settings.json" "PreToolUse guard wired"

echo "── second run (idempotency) ──"
if OUT2="$(run_bootstrap 2>&1)"; then
  pass "re-run exited 0"
else
  printf '%s\n' "$OUT2" | tail -15
  fail "re-run exited non-zero"
fi
printf '%s' "$OUT2" | grep -q 'reusing project #42'      && pass "board reused (no duplicate project)" || fail "board not reused"
printf '%s' "$OUT2" | grep -q 'worktree already exists'  && pass "worktrees reused"                    || fail "worktrees not reused"
printf '%s' "$OUT2" | grep -q '(exists — #7)'            && pass "standing epics deduped"              || fail "standing epics not deduped"

echo "── wizard path (scripted answers, abort at confirm) ──"
vendor_into "$T/prod2"
# On macOS the wizard asks one extra question (.app build) that Linux skips;
# aborting at the confirm gate keeps the answer script portable either way.
# (Answers via a file — bash 5.x rejects a heredoc + `||` inside $(...).)
cat > "$T/answers" <<ANSWERS
tester
tester/fake2
fake2
$T/seats2
pm engineer

Vera
T2
t2@x.nl

n
n
no
ANSWERS
WOUT="$( (cd "$T/prod2" && HOME="$T/home" PATH="$T/bin:$PATH" bash agentic-sdlc/onboarding/bootstrap.sh < "$T/answers") 2>&1 || true )"
printf '%s' "$WOUT" | grep -q 'aborted — nothing was changed' && pass "wizard aborts cleanly on 'no'" || fail "wizard abort missing"
assert_grep '^SEATS="pm:Pim engineer:Vera"$' "$T/prod2/sdlc.config" "wizard wrote suggested + overridden names"
assert_grep '^INSTANCE="fake2"$' "$T/prod2/sdlc.config" "wizard wrote instance"

echo
if [ "$FAIL" -gt 0 ]; then
  echo "✗ smoke-bootstrap: $FAIL assertion(s) failed"
  exit 1
fi
echo "✓ smoke-bootstrap: all assertions passed"
