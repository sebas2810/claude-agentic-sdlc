#!/usr/bin/env bash
#
# Both-directions test for the proof-before-Delivered gate
# (sebas2810/claude-agentic-sdlc#73): delivery-check.sh's mechanical proof
# and guard-git.sh's stamp enforcement, exercised together — each case here
# is the shape of a real incident #73 cites (a proof that stayed green with
# the fix reverted, a stale pass surviving a new commit, an auto-close
# racing ahead of open ACs).
#
# Usage: delivery-check.test.sh <path-to-delivery-check.sh> <path-to-guard-git.sh>
set -uo pipefail

CHECK="${1:-}"; GUARD="${2:-}"
[ -n "$CHECK" ] && [ -n "$GUARD" ] || {
  echo "usage: $0 <path-to-delivery-check.sh> <path-to-guard-git.sh>" >&2; exit 1; }
resolve() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s' "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" ;; esac; }
CHECK="$(resolve "$CHECK")"; GUARD="$(resolve "$GUARD")"
[ -f "$CHECK" ] || { echo "no such check script: $CHECK" >&2; exit 1; }
[ -x "$GUARD" ] || { echo "no such guard script (or not executable): $GUARD" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

git config --global user.email t@example.com 2>/dev/null || true
git config --global user.name t 2>/dev/null || true
git config --global init.defaultBranch main 2>/dev/null || true

# ── fixture: a tiny repo with a "bug", a branch that "fixes" it ────────────
# Pushed with a real bare "origin" and upstream tracking on `work` — #5239
# QA re-delivery check 5 requires HEAD to match its pushed upstream before a
# stamp is honored, so every fixture representing "ready to deliver" needs
# one, not just a local-only commit.
mkrepo() { # $1 = name
  local d="$T/$1"
  mkdir -p "$T/$1.origin" "$d"
  git -C "$T/$1.origin" init -q --bare
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name t
  git -C "$d" remote add origin "$T/$1.origin"
  printf 'buggy\n' > "$d/f.txt"
  git -C "$d" add f.txt
  git -C "$d" commit -qm base
  git -C "$d" branch -M main
  git -C "$d" push -q origin main 2>/dev/null
  git -C "$d" checkout -qb work
  printf 'fixed\n' > "$d/f.txt"
  git -C "$d" add f.txt
  git -C "$d" commit -qm "fix: #1 the bug"
  git -C "$d" push -qu origin work 2>/dev/null
}

# Re-push `work`'s current HEAD to its already-tracked origin — for a case
# that adds a commit AFTER the initial mkrepo push and still needs to count
# as "pushed" (contrast with a case that deliberately does NOT call this,
# to prove an unpushed HEAD is refused).
pushwork() { # $1 = name
  git -C "$T/$1" push -q origin work 2>/dev/null
}

runguard() { # $1 = cwd, $2 = command, $3 = stamp dir -> exit code on stdout as "exit=N"
  printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | ( cd "$1" && AGENTIC_SDLC_DELIVERY_STAMP_DIR="$3" bash "$GUARD" >/dev/null 2>&1 ); echo $?
}

DELIVER_CMD='gh issue edit 1 --add-label "status:delivered"'

# ═══ 1. a pass ══════════════════════════════════════════════════════════
mkrepo pass
cat > "$T/pass/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file says "fixed".
  Proof: `grep -q fixed f.txt`
EOF
echo "VERDICT: PASS" > "$T/pass/verdict.txt"
SDIR="$T/pass-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/pass" && bash "$CHECK" --issue 1 --base main \
  --issue-body-file issue-body.md --reviewer-verdict-file verdict.txt \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  ok "delivery-check exits 0 on a real, proven AC"
else
  bad "delivery-check should exit 0 on a real, proven AC — got: $out"
fi
gexit="$(runguard "$T/pass" "$DELIVER_CMD" "$SDIR")"
if [ "$gexit" = "0" ]; then
  ok "guard-git allows the status:delivered write once a passing stamp exists"
else
  bad "guard-git should allow the write with a passing stamp — got exit=$gexit"
fi
# The label-detection regex must not be fooled by the flag's equals-form —
# --add-label=X is valid cobra/gh syntax and, unfixed, matched nothing, so
# this write was never even evaluated against the (nonexistent) stamp dir.
NOSTAMP_SDIR="$T/nowhere-stamps"
gexit_eq="$(runguard "$T/pass" 'gh issue edit 1 --add-label=status:delivered' "$NOSTAMP_SDIR")"
if [ "$gexit_eq" != "0" ]; then
  ok "guard-git also catches the --add-label=status:delivered equals-form"
else
  bad "guard-git should block the equals-form write with no stamp — got exit=$gexit_eq"
fi

# ═══ 2. a hollow proof ══════════════════════════════════════════════════
# The defect #73 exists to catch: a "proof" that never discriminates — it
# passes with the bug present AND with it fixed. MUST be reported hollow and
# MUST NOT produce a stamp (so the label write stays blocked).
mkrepo hollow
cat > "$T/hollow/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file exists.
  Proof: `test -f f.txt`
EOF
echo "VERDICT: PASS" > "$T/hollow/verdict.txt"
SDIR="$T/hollow-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/hollow" && bash "$CHECK" --issue 1 --base main \
  --issue-body-file issue-body.md --reviewer-verdict-file verdict.txt \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q hollow; then
  ok "delivery-check refuses a proof that passes both reverted and fixed, and names it hollow"
else
  bad "a hollow proof MUST be refused and named — this is the defect #73 exists for. got rc=$rc: $out"
fi
gexit="$(runguard "$T/hollow" "$DELIVER_CMD" "$SDIR")"
if [ "$gexit" != "0" ]; then
  ok "guard-git still blocks the status:delivered write — no stamp was written"
else
  bad "guard-git MUST block when the check failed (no stamp) — got exit=$gexit"
fi

# ═══ 3. a stale stamp after a new commit ═══════════════════════════════
# A pass at commit A must not authorise a write once HEAD has moved to B —
# the fix could have been reverted, or anything else changed, since the
# check last ran.
mkrepo stale
cat > "$T/stale/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file says "fixed".
  Proof: `grep -q fixed f.txt`
EOF
echo "VERDICT: PASS" > "$T/stale/verdict.txt"
SDIR="$T/stale-stamps"; mkdir -p "$SDIR"
( cd "$T/stale" && bash "$CHECK" --issue 1 --base main \
  --issue-body-file issue-body.md --reviewer-verdict-file verdict.txt \
  --stamp-dir "$SDIR" >/dev/null 2>&1 )
gexit_fresh="$(runguard "$T/stale" "$DELIVER_CMD" "$SDIR")"
git -C "$T/stale" commit -q --allow-empty -m "one more commit after the pass"
gexit_stale="$(runguard "$T/stale" "$DELIVER_CMD" "$SDIR")"
if [ "$gexit_fresh" = "0" ] && [ "$gexit_stale" != "0" ]; then
  ok "a fresh stamp allows the write; a new commit invalidates it and guard-git blocks again"
else
  bad "expected fresh=allow(0), post-commit=block(nonzero) — got fresh=$gexit_fresh stale=$gexit_stale"
fi

# ═══ 4. a close keyword with open ACs ═══════════════════════════════════
# The PR auto-closes the issue while an AC checkbox is still unticked —
# AC3's job, independent of whether any AC has a Proof: command at all.
mkrepo close
cat > "$T/close/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file says "fixed".
  Proof: `grep -q fixed f.txt`
- [ ] A second criterion nobody has verified yet.
EOF
cat > "$T/close/pr-body.md" <<'EOF'
Closes #1
EOF
echo "VERDICT: PASS" > "$T/close/verdict.txt"
SDIR="$T/close-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/close" && bash "$CHECK" --issue 1 --pr 99 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'unticked'; then
  ok "delivery-check refuses a close keyword while an AC checkbox is still unticked"
else
  bad "a close keyword against open ACs MUST fail the check — got rc=$rc: $out"
fi
gexit="$(runguard "$T/close" "$DELIVER_CMD" "$SDIR")"
if [ "$gexit" != "0" ]; then
  ok "guard-git blocks the status:delivered write — the close-keyword check failed, no stamp"
else
  bad "guard-git MUST block when the close-keyword check failed — got exit=$gexit"
fi

# ═══ 5. DELIVERY_TEST_CMDS is actually sourced from sdlc.config ═════════
# Not just that the --test-cmds-file flag works in isolation (case 1
# already exercises AC1's mechanics) — that a real sdlc.config, with no
# --test-cmds-file override at all, is what feeds it by default.
mkrepo cfg
cat > "$T/cfg/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file says "fixed".
  Proof: `grep -q fixed f.txt`
EOF
echo "VERDICT: PASS" > "$T/cfg/verdict.txt"
# The marker only exists if DELIVERY_TEST_CMDS's command actually ran.
cat > "$T/cfg/sdlc.config" <<EOF
DELIVERY_TEST_CMDS="*.txt:touch $T/cfg/marker.txt"
EOF
SDIR="$T/cfg-stamps"; mkdir -p "$SDIR"
rm -f "$T/cfg/marker.txt"
( cd "$T/cfg" && bash "$CHECK" --issue 1 --base main \
  --issue-body-file issue-body.md --reviewer-verdict-file verdict.txt \
  --stamp-dir "$SDIR" >/dev/null 2>&1 )
if [ -f "$T/cfg/marker.txt" ]; then
  ok "DELIVERY_TEST_CMDS from a real sdlc.config runs with no --test-cmds-file override"
else
  bad "DELIVERY_TEST_CMDS in sdlc.config was not picked up — AC2 does not actually fire by default"
fi

# ═══ 6. --base auto-resolves via the SAME registry guard-git.sh uses ════
# Not origin/main, and not a copy of the resolution logic — the shared
# onboarding/lib/resolve-integration-base.sh script.
mkdir -p "$T/base/epic.origin" && git -C "$T/base/epic.origin" init -q --bare
git clone -q "$T/base/epic.origin" "$T/base/epic" 2>/dev/null
git -C "$T/base/epic" config user.email t@example.com
git -C "$T/base/epic" config user.name t
printf 'base\n' > "$T/base/epic/f.txt"
git -C "$T/base/epic" add f.txt; git -C "$T/base/epic" commit -qm base
git -C "$T/base/epic" branch -M main
git -C "$T/base/epic" push -q origin main 2>/dev/null
git -C "$T/base/epic" checkout -qb "feat/900-epic"
printf 'epic work\n' > "$T/base/epic/g.txt"
git -C "$T/base/epic" add g.txt; git -C "$T/base/epic" commit -qm "epic branch commit"
git -C "$T/base/epic" push -q origin "feat/900-epic" 2>/dev/null
git -C "$T/base/epic" checkout -qb work
printf 'fixed\n' > "$T/base/epic/f.txt"
git -C "$T/base/epic" add f.txt; git -C "$T/base/epic" commit -qm "fix: #1 the bug"
mkdir -p "$T/base/epic/agentic-sdlc/integration-branches/feat"
touch "$T/base/epic/agentic-sdlc/integration-branches/feat/900-epic"
cat > "$T/base/epic/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file says "fixed".
  Proof: `grep -q fixed f.txt`
EOF
echo "VERDICT: PASS" > "$T/base/epic/verdict.txt"
SDIR="$T/base-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/base/epic" && bash "$CHECK" --issue 1 \
  --issue-body-file issue-body.md --reviewer-verdict-file verdict.txt \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
if printf '%s' "$out" | grep -q "base origin/feat/900-epic"; then
  ok "--base auto-resolves to the registered integration branch, not origin/main"
else
  bad "expected auto-resolved base origin/feat/900-epic — got: $(printf '%s' "$out" | head -1)"
fi
if [ "$rc" -eq 0 ]; then
  ok "the proof still runs correctly against the auto-resolved base"
else
  bad "delivery-check should still pass with the auto-resolved base — got rc=$rc: $out"
fi

# ═══ 7. criteria written as a numbered list must block, write no stamp ══
# QA re-delivery check 1 (found reviewing #73's own adoption): its own
# body (six numbered criteria, zero GFM checkboxes) read as "0 AC lines, 0
# unticked" and PASSED — no criterion was proven, yet the stamp was written.
mkrepo numbered
cat > "$T/numbered/issue-body.md" <<'EOF'
## Acceptance criteria

1. **[PRE-MERGE]** Some criterion, in prose, no checkbox.
2. **[PRE-MERGE]** A second criterion, also no checkbox.
EOF
echo "VERDICT: PASS" > "$T/numbered/verdict.txt"
SDIR="$T/numbered-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/numbered" && bash "$CHECK" --issue 1 --base main \
  --issue-body-file issue-body.md --reviewer-verdict-file verdict.txt \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'no acceptance-criteria checkboxes'; then
  ok "a numbered-list body (no checkboxes) is refused, not silently passed"
else
  bad "a body with zero recognized AC checkboxes MUST fail loudly — got rc=$rc: $out"
fi
if [ -z "$(ls -A "$SDIR" 2>/dev/null)" ]; then
  ok "no stamp written for the numbered-list body"
else
  bad "a stamp was written despite zero criteria being provable"
fi

# ═══ 8. a close keyword against a numbered (unverifiable) body must fail ═
# QA re-delivery check 2: "found 0 AC line(s)... PASS close keyword present,
# no unticked ACs remain" — a close keyword raced ahead of six open,
# unverified criteria and the check said PASS.
cat > "$T/numbered/pr-body.md" <<'EOF'
Closes #1
EOF
SDIR="$T/numbered-stamps2"; mkdir -p "$SDIR"
out="$(cd "$T/numbered" && bash "$CHECK" --issue 1 --pr 99 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'no AC checkboxes were found'; then
  ok "close keyword against an unverifiable (numbered) body fails, names the gap"
else
  bad "a close keyword with zero verifiable ACs MUST fail — got rc=$rc: $out"
fi

# ═══ 9. a PR opened against the wrong base branch must fail ═════════════
# QA re-delivery check 3: the check resolves a base but never reads the
# PR's own base branch — a PR opened against main for an item that belongs
# on an integration branch was not caught.
SDIR="$T/base-mismatch-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/pass" && bash "$CHECK" --issue 1 --pr 99 --base main \
  --issue-body-file issue-body.md --pr-base-ref "some-other-branch" \
  --reviewer-verdict-file verdict.txt --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'wrong target branch'; then
  ok "a PR opened against a base that does not match the resolved base fails"
else
  bad "a PR base/resolved-base mismatch MUST fail — got rc=$rc: $out"
fi
SDIR2="$T/base-match-stamps"; mkdir -p "$SDIR2"
out2="$(cd "$T/pass" && bash "$CHECK" --issue 1 --pr 99 --base main \
  --issue-body-file issue-body.md --pr-base-ref "main" \
  --reviewer-verdict-file verdict.txt --stamp-dir "$SDIR2" 2>&1)"; rc2=$?
if [ "$rc2" -eq 0 ]; then
  ok "a PR opened against the matching base passes this check"
else
  bad "a matching PR base MUST NOT be flagged — got rc=$rc2: $out2"
fi

# ═══ 10. guard-git.sh's four other status:delivered write routes ════════
# QA re-delivery check 4, each verified live against the merged PR: `gh pr
# edit` (wrong subcommand matched), a label held in a shell variable
# (opaque — the literal text never appears in the command), `gh api`
# piping JSON via `--input -` (payload never in the command text), and a
# GraphQL `addLabelsToLabelable` mutation. "Refusing a label it cannot
# read counts as blocking" — QA's own framing, and the fail-closed design
# this case pins.
mkrepo routes
SDIR="$T/routes-stamps"; mkdir -p "$SDIR"
routes_ok=1
check_route() { # $1 = label, $2 = command, $3 = expect (block|allow)
  local rc
  rc="$(runguard "$T/routes" "$2" "$SDIR")"
  case "$3" in
    block) [ "$rc" != "0" ] && return 0 ;;
    allow) [ "$rc" = "0" ] && return 0 ;;
  esac
  bad "route '$1' expected $3, got exit=$rc"
  routes_ok=0
}
check_route "gh pr edit --add-label" 'gh pr edit 1 --add-label status:delivered' block
check_route "label in a shell variable" 'L=status:delivered; gh issue edit 1 --add-label "$L"' block
check_route "gh api --input - stdin JSON" 'gh api -X POST repos/o/r/issues/1/labels --input -' block
check_route "gh api graphql addLabelsToLabelable" "gh api graphql -f query='mutation{addLabelsToLabelable(input:{labelableId:\"x\",labelIds:[\"y\"]}){clientMutationId}}'" block
# A second independent review of THIS fix (before it shipped) found a fifth
# live bypass: `--add-label` legitimately repeats, and the first cut only
# inspected the FIRST occurrence's literal (`head -1`) — a second,
# malicious `--add-label status:delivered` after a harmless first one
# passed uninspected. Both flag orders, since the bug was position-blind.
check_route "repeated --add-label, malicious second" 'gh issue edit 1 --add-label seat:someone --add-label status:delivered' block
check_route "repeated --add-label, malicious first" 'gh issue edit 1 --add-label status:delivered --add-label seat:someone' block
# GitHub matches label names case-insensitively; a case-differing literal
# is not a different, safe label.
check_route "case-differing literal (Status:Delivered)" 'gh issue edit 1 --add-label "Status:Delivered"' block
check_route "unrelated literal label (seat:seb)" 'gh issue edit 1 --add-label "seat:seb"' allow
check_route "unrelated literal label (status:in-progress)" 'gh issue edit 1 --add-label "status:in-progress"' allow
check_route "repeated --add-label, both safe" 'gh issue edit 1 --add-label seat:someone --add-label P1' allow
[ "$routes_ok" = 1 ] && ok "all bypass routes blocked; routine (incl. repeated-flag) label writes still allowed"

# ═══ 11. a stamp for an unpushed commit does not let the write through ══
# QA re-delivery check 5: "the stamp is keyed to local git rev-parse HEAD…
# not to the PR's head. A commit that was never pushed gets a stamp." This
# is distinct from case 3 (a NEW commit invalidates the old SHA's stamp) —
# here the SHA matches its own stamp exactly; what's missing is that HEAD
# was ever pushed anywhere reviewable.
mkrepo unpushed
cat > "$T/unpushed/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file says "fixed".
  Proof: `grep -q fixed f.txt`
EOF
echo "VERDICT: PASS" > "$T/unpushed/verdict.txt"
SDIR="$T/unpushed-stamps"; mkdir -p "$SDIR"
( cd "$T/unpushed" && bash "$CHECK" --issue 1 --base main \
  --issue-body-file issue-body.md --reviewer-verdict-file verdict.txt \
  --stamp-dir "$SDIR" >/dev/null 2>&1 )
git -C "$T/unpushed" commit -q --allow-empty -m "a real commit, never pushed"
SDIR2="$T/unpushed-stamps2"; mkdir -p "$SDIR2"
( cd "$T/unpushed" && bash "$CHECK" --issue 1 --base main \
  --issue-body-file issue-body.md --reviewer-verdict-file verdict.txt \
  --stamp-dir "$SDIR2" >/dev/null 2>&1 )
gexit_unpushed="$(runguard "$T/unpushed" "$DELIVER_CMD" "$SDIR2")"
pushwork unpushed
gexit_pushed="$(runguard "$T/unpushed" "$DELIVER_CMD" "$SDIR2")"
if [ "$gexit_unpushed" != "0" ] && [ "$gexit_pushed" = "0" ]; then
  ok "a valid stamp for an unpushed HEAD is refused; pushing the same commit then allows it"
else
  bad "expected unpushed=block(nonzero), pushed=allow(0) — got unpushed=$gexit_unpushed pushed=$gexit_pushed"
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "delivery-check: all checks passed"
else
  echo "delivery-check: $fails check(s) FAILED" >&2
fi
exit "$fails"
