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

# PM finding: this test previously ran `git config --global ...` straight
# against the REAL global ~/.gitconfig — on 2026-09-13 at 14:12 it clobbered
# the machine's actual identity to "t <t@example.com>", misattributing
# commits made in OTHER worktrees afterward. GIT_CONFIG_GLOBAL (git >=2.32)
# points every git invocation in this script (and anything it execs, since
# it's exported) at an isolated file under $T instead.
export GIT_CONFIG_GLOBAL="$T/gitconfig"
: > "$GIT_CONFIG_GLOBAL"
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

runguard() { # $1 = cwd, $2 = command, $3 = stamp dir, $4 = optional dir to
             # prepend to PATH (a stub gh), $5 = optional FAKE_GH_PR_HEAD
             # -> exit code on stdout as "exit=N"
  printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | ( cd "$1" && [ -n "${4:-}" ] && PATH="$4:$PATH"; \
        AGENTIC_SDLC_DELIVERY_STAMP_DIR="$3" FAKE_GH_PR_HEAD="${5:-}" bash "$GUARD" >/dev/null 2>&1 ); echo $?
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
# #5239 QA re-delivery review round 2 ("a check must be able to report its
# own failure"): --pr is now mandatory — Delivered means "PR open, awaiting
# QA" by definition, so every fixture standing in for a real PASS needs a
# full, hermetic PR context (no reliance on a real `gh` call failing quietly
# against these fixtures' non-GitHub remotes).
cat > "$T/pass/pr-body.md" <<'EOF'
No close keyword here — proven separately before merge.
EOF
SDIR="$T/pass-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/pass" && bash "$CHECK" --issue 1 --pr 99 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref main --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/pass" rev-parse HEAD)" \
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
cat > "$T/stale/pr-body.md" <<'EOF'
No close keyword here — proven separately before merge.
EOF
SDIR="$T/stale-stamps"; mkdir -p "$SDIR"
( cd "$T/stale" && bash "$CHECK" --issue 1 --pr 99 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref main --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/stale" rev-parse HEAD)" \
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
  --pr-base-ref main \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/close" rev-parse HEAD)" \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
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
cat > "$T/base/epic/pr-body.md" <<'EOF'
No close keyword here — proven separately before merge.
EOF
SDIR="$T/base-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/base/epic" && bash "$CHECK" --issue 1 --pr 99 \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref "feat/900-epic" --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/base/epic" rev-parse HEAD)" \
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
  --pr-base-ref main \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/numbered" rev-parse HEAD)" \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
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
  --issue-body-file issue-body.md --pr-body-file pr-body.md --pr-mergeable MERGEABLE \
  --pr-base-ref "some-other-branch" \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/pass" rev-parse HEAD)" \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'wrong target branch'; then
  ok "a PR opened against a base that does not match the resolved base fails"
else
  bad "a PR base/resolved-base mismatch MUST fail — got rc=$rc: $out"
fi
SDIR2="$T/base-match-stamps"; mkdir -p "$SDIR2"
out2="$(cd "$T/pass" && bash "$CHECK" --issue 1 --pr 99 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md --pr-mergeable MERGEABLE \
  --pr-base-ref "main" \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/pass" rev-parse HEAD)" \
  --stamp-dir "$SDIR2" 2>&1)"; rc2=$?
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
# #5239 QA re-delivery review round 2 — five MORE live routes, each
# verified against the merged PR #86 fix before this round started:
check_route "-R repo flag BEFORE the subcommand" 'gh -R o/r issue edit 1 --add-label status:delivered' block
check_route "--repo flag BEFORE the subcommand" 'gh --repo o/r pr edit 1 --add-label status:delivered' block
check_route "gh api PATCH straight to issues/{n} with labels[]=" "gh api -X PATCH repos/o/r/issues/1 -f 'labels[]=status:delivered'" block
check_route "gh api POST to a QUOTED /labels path" 'gh api -X POST "repos/o/r/issues/1/labels" -f name=status:delivered' block
check_route "gh api graphql -F query=@file (external, unreadable payload)" 'gh api graphql -F query=@mutation.graphql' block
check_route "gh api graphql updateIssue(labelIds:) — second mutation shape" "gh api graphql -f query='mutation{updateIssue(input:{id:\"x\",labelIds:[\"y\"]}){clientMutationId}}'" block
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
cat > "$T/unpushed/pr-body.md" <<'EOF'
No close keyword here — proven separately before merge.
EOF
SDIR="$T/unpushed-stamps"; mkdir -p "$SDIR"
( cd "$T/unpushed" && bash "$CHECK" --issue 1 --pr 99 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref main --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/unpushed" rev-parse HEAD)" \
  --stamp-dir "$SDIR" >/dev/null 2>&1 )
git -C "$T/unpushed" commit -q --allow-empty -m "a real commit, never pushed"
SDIR2="$T/unpushed-stamps2"; mkdir -p "$SDIR2"
( cd "$T/unpushed" && bash "$CHECK" --issue 1 --pr 99 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref main --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/unpushed" rev-parse HEAD)" \
  --stamp-dir "$SDIR2" >/dev/null 2>&1 )
gexit_unpushed="$(runguard "$T/unpushed" "$DELIVER_CMD" "$SDIR2")"
pushwork unpushed
gexit_pushed="$(runguard "$T/unpushed" "$DELIVER_CMD" "$SDIR2")"
if [ "$gexit_unpushed" != "0" ] && [ "$gexit_pushed" = "0" ]; then
  ok "a valid stamp for an unpushed HEAD is refused; pushing the same commit then allows it"
else
  bad "expected unpushed=block(nonzero), pushed=allow(0) — got unpushed=$gexit_unpushed pushed=$gexit_pushed"
fi

# ═══ 12. a checkbox with no Proof: command must fail, write no stamp ════
# AC1 gap: a checkbox present but never paired with a Proof: line is a
# manual assertion, not proof — the same "no criterion was proven" failure
# as an all-numbered body (case 7), just partial instead of total.
mkrepo noproof
cat > "$T/noproof/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] A criterion with no Proof: command at all.
EOF
echo "VERDICT: PASS" > "$T/noproof/verdict.txt"
SDIR="$T/noproof-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/noproof" && bash "$CHECK" --issue 1 --base main \
  --issue-body-file issue-body.md --reviewer-verdict-file verdict.txt \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'no Proof: command'; then
  ok "a checkbox with no Proof: command is refused, not silently passed"
else
  bad "a checkbox missing its Proof: line MUST fail, named — got rc=$rc: $out"
fi
if [ -z "$(ls -A "$SDIR" 2>/dev/null)" ]; then
  ok "no stamp written for a checkbox missing its Proof: command"
else
  bad "a stamp was written despite an unproofed checkbox"
fi

# ═══ 13. no --pr at all must fail, not silently skip the PR checks ══════
# #5239 QA re-delivery review round 2: "a check must be able to report its
# own failure" — a run given no --pr used to let every PR subcheck's
# `if -n "$PR"` guard find nothing and skip, silently, scoring the same as
# a clean PASS. Delivered means "PR open, awaiting QA" by definition, so a
# run that cannot see a PR must say so, not stay silent.
mkrepo nopr
cat > "$T/nopr/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file says "fixed".
  Proof: `grep -q fixed f.txt`
EOF
echo "VERDICT: PASS" > "$T/nopr/verdict.txt"
SDIR="$T/nopr-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/nopr" && bash "$CHECK" --issue 1 --base main \
  --issue-body-file issue-body.md --reviewer-verdict-file verdict.txt \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'no --pr given'; then
  ok "no --pr at all is refused, not silently skipped"
else
  bad "a run with no --pr MUST fail, named — got rc=$rc: $out"
fi
if [ -z "$(ls -A "$SDIR" 2>/dev/null)" ]; then
  ok "no stamp written when no --pr was given"
else
  bad "a stamp was written despite no --pr being given"
fi

# ═══ 14. guard-git checks the PR's REAL remote head, not just @{u} ══════
# #5239 QA re-delivery review round 2, check 5's other half: the local
# `@{u}` tracking ref is only what THIS checkout last saw as its upstream —
# stale or misconfigured, it says nothing about what the PR actually shows
# on GitHub right now. A minimal stub `gh` on $PATH answers the REAL
# `gh pr view <n> --json headRefOid -q .headRefOid` call guard-git.sh
# makes, so this exercises genuine production code (command construction,
# parsing, comparison) against a scripted remote answer — no live network
# dependency, and "never calls gh" holds for every OTHER case (this is the
# only one that ever puts a `gh` on PATH, and only for these two calls).
#
# Stub discriminates by PR NUMBER, not just presence of a `pr view` call:
# an earlier cut of this stub answered ANY number, which coincidentally
# masked #5239 QA re-delivery round 3 check 4(b) — the write route used in
# production (`gh issue edit <n> --add-label status:delivered`, since a
# board item is an issue) derived its PRNUM from the ISSUE number, and a
# permissive stub let that wrong number "resolve" anyway. Only a stub that
# rejects an unexpected number reproduces `gh pr view`'s real failure mode
# on an issue number (issues and PRs share one number space; `gh pr view`
# on an issue # cannot resolve it) and so actually exercises the fix.
mkdir -p "$T/fakegh"
cat > "$T/fakegh/gh" <<'SCRIPT'
#!/usr/bin/env bash
# Stub: answers `gh pr view <n> [-R <repo>] --json headRefOid -q .headRefOid`
# with $FAKE_GH_PR_HEAD ONLY for PR number $FAKE_GH_PR_NUM — any other
# number fails, matching real `gh pr view`'s behaviour on a number that
# isn't actually a PR in this repo. Any other invocation is a test-design
# error.
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  n=""
  for a in "$@"; do
    case "$a" in [0-9]*) n="$a"; break ;; esac
  done
  if [ "$n" = "${FAKE_GH_PR_NUM:-}" ]; then
    printf '%s\n' "${FAKE_GH_PR_HEAD:-}"
    exit 0
  fi
  exit 1
fi
exit 1
SCRIPT
chmod +x "$T/fakegh/gh"

mkrepo prhead
cat > "$T/prhead/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file says "fixed".
  Proof: `grep -q fixed f.txt`
EOF
echo "VERDICT: PASS" > "$T/prhead/verdict.txt"
cat > "$T/prhead/pr-body.md" <<'EOF'
No close keyword here — proven separately before merge.
EOF
SDIR="$T/prhead-stamps"; mkdir -p "$SDIR"
# issue #1, PR #7 — deliberately DIFFERENT numbers. #5239 QA re-delivery
# round 3's own repro used this split to defeat a fixture that had
# accidentally used the same number for both, which let the pre-fix
# issue-number-as-PRNUM bug produce the right answer by coincidence and
# masked the defect entirely.
( cd "$T/prhead" && bash "$CHECK" --issue 1 --pr 7 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref main --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/prhead" rev-parse HEAD)" \
  --stamp-dir "$SDIR" >/dev/null 2>&1 )
REAL_HEAD="$(git -C "$T/prhead" rev-parse HEAD)"
runguard_pr7() { # $1 = command, $2 = FAKE_GH_PR_HEAD
  printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" \
    | ( cd "$T/prhead" && PATH="$T/fakegh:$PATH" \
        AGENTIC_SDLC_DELIVERY_STAMP_DIR="$SDIR" FAKE_GH_PR_NUM=7 FAKE_GH_PR_HEAD="$2" bash "$GUARD" >/dev/null 2>&1 ); echo $?
}
gexit_match="$(runguard_pr7 "$DELIVER_CMD" "$REAL_HEAD")"
gexit_mismatch="$(runguard_pr7 "$DELIVER_CMD" "0000000000000000000000000000000000000000")"
if [ "$gexit_match" = "0" ] && [ "$gexit_mismatch" != "0" ]; then
  ok "guard-git compares against the PR's actual remote head (gh pr view), not just the local @{u} ref"
else
  bad "expected remote-head match=allow(0), mismatch=block(nonzero) — got match=$gexit_match mismatch=$gexit_mismatch"
fi
# #5239 QA re-delivery round 3, check 4(b): the route labels are actually
# applied through — `gh issue edit <n> --add-label status:delivered` — used
# to derive PRNUM from the ISSUE number (1), so `gh pr view 1` could never
# resolve (it isn't a PR), REMOTE_HEAD stayed empty, and the check silently
# fell back to the (matching, in this fixture) local @{u} ref — wrongly
# ALLOWING a write against a PR whose real remote head had moved. Fixed:
# PRNUM is read from the stamp's own `pr:` line (7), independent of which
# gh subcommand is writing the label.
gexit_issueroute_mismatch="$(runguard_pr7 "$DELIVER_CMD" "0000000000000000000000000000000000000000")"
gexit_issueroute_match="$(runguard_pr7 "$DELIVER_CMD" "$REAL_HEAD")"
if [ "$gexit_issueroute_mismatch" != "0" ] && [ "$gexit_issueroute_match" = "0" ]; then
  ok "the issue-edit route (production's actual delivery-label write) also compares against the PR's real head, not just @{u}"
else
  bad "issue-edit route: expected mismatch=block(nonzero) match=allow(0) — got mismatch=$gexit_issueroute_mismatch match=$gexit_issueroute_match"
fi
# Same route with an explicit -R/--repo flag before the subcommand.
gexit_repoflag_mismatch="$(printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' 'gh -R o/r issue edit 1 --add-label "status:delivered"')" \
  | ( cd "$T/prhead" && PATH="$T/fakegh:$PATH" AGENTIC_SDLC_DELIVERY_STAMP_DIR="$SDIR" FAKE_GH_PR_NUM=7 FAKE_GH_PR_HEAD="0000000000000000000000000000000000000000" bash "$GUARD" >/dev/null 2>&1 ); echo $?)"
if [ "$gexit_repoflag_mismatch" != "0" ]; then
  ok "the issue-edit route still blocks on a mismatched PR head with an explicit -R repo flag"
else
  bad "issue-edit route with -R MUST block on a mismatched PR head — got exit=$gexit_repoflag_mismatch"
fi

# ═══ 15. delivery-check.sh itself refuses when HEAD != the PR's real head ═
# #5239 QA re-delivery round 3, check 4(a): delivery-check.sh wrote a
# passing stamp for local HEAD without ever asking whether that HEAD is
# what the PR actually shows on GitHub — only guard-git.sh's later,
# separate check caught a mismatch, and only on some write routes. Fixed
# by giving delivery-check.sh its own comparison: a --pr-head-sha override
# (a caller that already has the real head, e.g. from CI) or a `gh pr view`
# fallback when the override isn't given.
mkrepo prheadself
cat > "$T/prheadself/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file says "fixed".
  Proof: `grep -q fixed f.txt`
EOF
echo "VERDICT: PASS" > "$T/prheadself/verdict.txt"
cat > "$T/prheadself/pr-body.md" <<'EOF'
No close keyword here — proven separately before merge.
EOF
REAL_HEAD_SELF="$(git -C "$T/prheadself" rev-parse HEAD)"

# 15a. --pr-head-sha override: mismatch must fail, name the gap, write no stamp.
SDIR="$T/prheadself-mismatch-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/prheadself" && bash "$CHECK" --issue 1 --pr 7 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref main --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "0000000000000000000000000000000000000000" \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "does not match PR"; then
  ok "delivery-check itself refuses when --pr-head-sha does not match local HEAD"
else
  bad "a --pr-head-sha mismatch MUST fail the check, named — got rc=$rc: $out"
fi
if [ -z "$(ls -A "$SDIR" 2>/dev/null)" ]; then
  ok "no stamp written when --pr-head-sha does not match local HEAD"
else
  bad "a stamp was written despite --pr-head-sha not matching local HEAD"
fi

# 15b. --pr-head-sha override matching local HEAD: passes.
SDIR2="$T/prheadself-match-stamps"; mkdir -p "$SDIR2"
out2="$(cd "$T/prheadself" && bash "$CHECK" --issue 1 --pr 7 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref main --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$REAL_HEAD_SELF" \
  --stamp-dir "$SDIR2" 2>&1)"; rc2=$?
if [ "$rc2" -eq 0 ]; then
  ok "delivery-check itself passes when --pr-head-sha matches local HEAD"
else
  bad "a matching --pr-head-sha MUST NOT be flagged — got rc=$rc2: $out2"
fi

# 15c. no override given: falls back to a real `gh pr view` call — proven
# with the same discriminating stub as case 14, reused here for delivery-
# check.sh's OWN gh call rather than guard-git.sh's.
mkdir -p "$T/prheadself-fallback-match-stamps" "$T/prheadself-fallback-mismatch-stamps"
out3="$(cd "$T/prheadself" && PATH="$T/fakegh:$PATH" FAKE_GH_PR_NUM=7 FAKE_GH_PR_HEAD="$REAL_HEAD_SELF" \
  bash "$CHECK" --issue 1 --pr 7 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref main --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --stamp-dir "$T/prheadself-fallback-match-stamps" 2>&1)"; rc3=$?
if [ "$rc3" -eq 0 ]; then
  ok "with no --pr-head-sha override, delivery-check.sh falls back to a real gh pr view lookup that matches"
else
  bad "the gh-fallback PR-head lookup MUST pass on a real match — got rc=$rc3: $out3"
fi
out4="$(cd "$T/prheadself" && PATH="$T/fakegh:$PATH" FAKE_GH_PR_NUM=7 FAKE_GH_PR_HEAD="0000000000000000000000000000000000000000" \
  bash "$CHECK" --issue 1 --pr 7 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref main --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --stamp-dir "$T/prheadself-fallback-mismatch-stamps" 2>&1)"; rc4=$?
if [ "$rc4" -ne 0 ] && printf '%s' "$out4" | grep -qi "does not match PR"; then
  ok "with no --pr-head-sha override, the gh-fallback lookup also catches a mismatch"
else
  bad "the gh-fallback PR-head lookup MUST catch a real mismatch — got rc=$rc4: $out4"
fi

# ═══ 16/17. DELIVERY_TEST_CMDS: each glob's command runs isolated ═══════
# PM finding: a bare `eval "$cmd"` (no subshell, no closed stdin) shares
# this loop's OWN shell and stdin with every command it runs — a `cd`
# leaks into every later command (and the rest of the script), and a
# command that reads stdin consumes the rest of TEST_CMDS_FILE's lines,
# silently skipping later globs as an undetected false PASS. #73's fix
# wraps each command in `( eval "$cmd" ) </dev/null`; these two cases pin
# that both failure shapes stay fixed.
mkrepo cdiso
mkdir -p "$T/cdiso/a" "$T/cdiso/b"
touch "$T/cdiso/a/x.txt" "$T/cdiso/b/y.txt"
git -C "$T/cdiso" add a b
git -C "$T/cdiso" commit -qm "add a/ and b/ subdirs"
cat > "$T/cdiso/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file says "fixed".
  Proof: `grep -q fixed f.txt`
EOF
echo "VERDICT: PASS" > "$T/cdiso/verdict.txt"
cat > "$T/cdiso/pr-body.md" <<'EOF'
No close keyword here — proven separately before merge.
EOF
# `cd b` only succeeds from cdiso's own root. Sharing one un-subshelled
# shell across both commands would leave the first `cd a` in effect when
# the second command runs, so `cd b` would look for cdiso/a/b (absent) and
# fail — a false FAIL for a glob whose real target directory exists.
cat > "$T/cdiso/test-cmds.txt" <<'EOF'
a/**:cd a && true
b/**:cd b && true
EOF
SDIR="$T/cdiso-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/cdiso" && bash "$CHECK" --issue 1 --pr 99 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref main --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/cdiso" rev-parse HEAD)" \
  --test-cmds-file test-cmds.txt \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  ok "a cd in one DELIVERY_TEST_CMDS command does not leak into the next command's glob"
else
  bad "each DELIVERY_TEST_CMDS command MUST run cd-isolated from its siblings — got rc=$rc: $out"
fi

mkrepo stdiniso
mkdir -p "$T/stdiniso/a" "$T/stdiniso/b"
touch "$T/stdiniso/a/x.txt" "$T/stdiniso/b/y.txt"
git -C "$T/stdiniso" add a b
git -C "$T/stdiniso" commit -qm "add a/ and b/ subdirs"
cat > "$T/stdiniso/issue-body.md" <<'EOF'
## Acceptance criteria

- [ ] The file says "fixed".
  Proof: `grep -q fixed f.txt`
EOF
echo "VERDICT: PASS" > "$T/stdiniso/verdict.txt"
cat > "$T/stdiniso/pr-body.md" <<'EOF'
No close keyword here — proven separately before merge.
EOF
# If `a/**`'s command shares the outer loop's stdin (TEST_CMDS_FILE itself)
# instead of a closed one, `cat` reads to EOF and swallows the b/** line —
# the loop ends having never run it, an undetected false PASS.
cat > "$T/stdiniso/test-cmds.txt" <<'EOF'
a/**:cat >/dev/null
b/**:false
EOF
SDIR="$T/stdiniso-stamps"; mkdir -p "$SDIR"
out="$(cd "$T/stdiniso" && bash "$CHECK" --issue 1 --pr 99 --base main \
  --issue-body-file issue-body.md --pr-body-file pr-body.md \
  --pr-base-ref main --pr-mergeable MERGEABLE \
  --reviewer-verdict-file verdict.txt \
  --pr-head-sha "$(git -C "$T/stdiniso" rev-parse HEAD)" \
  --test-cmds-file test-cmds.txt \
  --stamp-dir "$SDIR" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF 'DELIVERY_TEST_CMDS[b/**] failed'; then
  ok "a stdin-reading DELIVERY_TEST_CMDS command does not swallow sibling commands' input"
else
  bad "b/** MUST still run and fail after a stdin-reading a/** command — got rc=$rc: $out"
fi
if [ -z "$(ls -A "$SDIR" 2>/dev/null)" ]; then
  ok "no stamp written when a later DELIVERY_TEST_CMDS command fails"
else
  bad "a stamp was written despite a failing DELIVERY_TEST_CMDS command"
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "delivery-check: all checks passed"
else
  echo "delivery-check: $fails check(s) FAILED" >&2
fi
exit "$fails"
