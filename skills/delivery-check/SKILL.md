---
name: delivery-check
description: Prove an item's acceptance criteria before writing status:delivered — run onboarding/lib/delivery-check.sh, invoke the delivery-reviewer subagent, and paste the summary into the ready-signal. Use this whenever a producer is about to move a Scoped/In-Progress item to Delivered.
---

# Principal Delivery Check — proof before Delivered

> A Principal skill is a domain operating standard a seat *embodies* while delivering an EPIC — the **floor** it holds itself to when the work touches this domain. This one is seat-agnostic in a stricter sense than most: it does not govern a technical surface (AWS, privacy, a language) but the **producer→Delivered transition itself**, so every producer seat embodies it on every item, every time. This file conforms to the **Agent Skills** spec (`name` + `description` frontmatter + instructions; see [anthropics/skills](https://github.com/anthropics/skills) `spec/agent-skills-spec.md`).

## When the engineer embodies this

Every time, immediately before dual-writing an item's status to `Delivered` — no exceptions for "this one is small" or "the fix is obviously right." That confidence is exactly what produced the 14-of-121 "proof missing or hollow" bounces this skill exists to catch (sebas2810/claude-agentic-sdlc#73): a suite that stayed green with the fix reverted, or an artifact an AC named that was never actually produced.

## Operating standard

1. **Write acceptance criteria as GFM task-list items with a `Proof:` line**, so the check has something to run:

   ```markdown
   - [ ] The file says "fixed".
     Proof: `grep -q fixed f.txt`
   ```

   Not every AC has a mechanical proof (a UX judgment call, a product decision) — those stay as prose without a `Proof:` line and are the reviewer subagent's job (step 3), not the script's.

2. **Run `onboarding/lib/delivery-check.sh --issue <n> --pr <n>`** from the PR's own branch, HEAD at the commit you intend to deliver — `--base` is optional; omitted, it auto-resolves via `onboarding/lib/resolve-integration-base.sh` (the registered integration branch your branch descends from, else `origin/main` — the same resolution `guard-git.sh`'s own rebase check uses, never a second copy). Pass `--base` explicitly only to override. It:
   - runs every `Proof:` command **twice** — once in a worktree of the resolved base (the fix reverted; must **fail**) and once at your current HEAD (the fix present; must **pass**), and **prints each command before running it** (it came from the issue body, not from you — see the script's own SECURITY note; never run this against an issue you have not read). A command that passes **both ways proves nothing** and is reported `hollow` — a blocker, not a warning.
   - runs your instance's own `DELIVERY_TEST_CMDS` (path glob → command, in `sdlc.config`), auto-discovered by walking up from cwd (override with `--sdlc-config`/`--test-cmds-file`), for whichever globs the diff touches.
   - checks the PR: no close keyword (`Closes #<n>` etc.) while an AC checkbox is still unticked; `git log <base>..HEAD` holds only this item's commits (no sibling-item contamination); the PR is `MERGEABLE` against the current base tip.

3. **Invoke the `delivery-reviewer` subagent** ([`agents/delivery-reviewer.md`](../../agents/delivery-reviewer.md)) in a **fresh context** (a Task/Agent-tool call, not inline reasoning in your own already-invested context — a session that built the fix is a poor grader of whether the fix is enough) — give it the diff and the AC, nothing else. Save its verdict (`VERDICT: PASS` or `VERDICT: FAIL` + why, on its own line) to a file and pass `--reviewer-verdict-file <path>` on your next `delivery-check.sh` run so the mechanical check counts it.

4. **On an overall PASS**, `delivery-check.sh` writes a stamp keyed to your current HEAD sha. `guard-git.sh` then allows the `status:delivered` label write; without a matching stamp it blocks with the same escape-hatch discipline as the pre-push gate (`AGENTIC_SDLC_SKIP_DELIVERY_CHECK=1`, one-off, never a standing default).

5. **Paste the check's summary into your ready-signal** (the `## Unit landed` report) — the PASS/FAIL lines per AC, not just "delivery-check: PASS". The point is a reviewer can see WHAT was proven, not just that a gate went green.

## Hard rules & refusals

- **A hollow proof is a FAIL, not a PASS-with-a-note.** If reverting the fix does not make the proof command fail, the command is not proof of anything and the check must refuse — silently accepting it is exactly the false-green this skill exists to close.
- **Never re-run the reviewer subagent in the same context that built the fix.** Its value is independence; a subagent sharing your context (or you grading your own diff inline) is produce == adjudicate, the invariant this whole skill exists to hold.
- **Never bypass with `AGENTIC_SDLC_SKIP_DELIVERY_CHECK` to save time.** It exists for a genuine owner-authorised exception (e.g. a hotfix where the proof infrastructure itself is broken), not for "I already tested it manually."
- **A stale stamp is not a pass.** Any new commit after `delivery-check.sh` ran invalidates its stamp — re-run after every change, including a rebase.

## Decision checklist (run before any "ready" signal)

1. Does every `Proof:`-bearing AC line's command fail against the reverted fix and pass against HEAD? — Y/N
2. Does `DELIVERY_TEST_CMDS` run clean for every path glob the diff touches? — Y/N
3. Is the PR free of a close keyword racing ahead of an unticked AC? — Y/N
4. Does `git log <base>..HEAD` hold only this item's own commits? — Y/N
5. Is the PR `MERGEABLE` against the current base tip? — Y/N
6. Did the `delivery-reviewer` subagent return `VERDICT: PASS` from a fresh context? — Y/N
7. Did `delivery-check.sh` exit 0 and write a stamp for your current HEAD sha? — Y/N

A failed check is a **blocker, not a note** — fix it and re-run rather than deliver around it.

## Bundled eval (ADR-0001)

`onboarding/tests/delivery-check.test.sh` — both-directions, exercising `delivery-check.sh` and `guard-git.sh` together, every case shown failing against a tree missing the fix it pins. Representative cases:

1. **a pass** — a real, discriminating proof: `delivery-check.sh` exits 0 and writes a stamp; `guard-git.sh` then allows the `status:delivered` write.
2. **a hollow proof** — a proof command that passes with the bug present too: `delivery-check.sh` refuses and names it `hollow`; no stamp; `guard-git.sh` still blocks.
3. **a stale stamp after a new commit** — a valid pass, then one more commit: the write is allowed immediately after the pass and blocked again once HEAD has moved.
4. **a close keyword with open ACs** — a PR body closing the issue while an AC checkbox is still unticked: `delivery-check.sh` refuses; `guard-git.sh` blocks (no stamp).
5. **an unverifiable body** — zero recognized checkboxes, or a checkbox present with no `Proof:` line: refused, not silently passed as a clean run.
6. **no `--pr` given at all** — refused; Delivered means "PR open, awaiting QA" by definition, so a run that cannot see a PR cannot report PASS.
7. **a PR opened against the wrong base branch** — refused.
8. **every known bypass route on the `status:delivered` label write** — `gh pr edit`, a shell-variable value, `gh api` REST/GraphQL in several payload shapes, a `-R`/`--repo` prefix before the subcommand — each blocked; an unrelated literal label write (`--add-label seat:seb`) is still allowed.
9. **a stamp for an unpushed commit** — refused; pushing that same commit then allows the write.
10. **the PR's actual remote head, not just the local `@{u}` tracking ref** — a mismatch between HEAD and what the PR really shows on GitHub (via a scripted `gh` stub, no live network dependency) is refused.

Run against `onboarding/hooks/guard-git.sh` as checked out on `main` before sebas2810/claude-agentic-sdlc#73 (no stamp-enforcement section at all), most of these cases fail outright — the suite is a genuine regression guard on the guard itself, not merely on the check script.
