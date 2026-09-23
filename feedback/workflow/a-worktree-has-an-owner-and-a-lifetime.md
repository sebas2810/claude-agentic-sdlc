---
title: A worktree has an owner and a lifetime, and the sweep is what makes that true
status: active
scope: all seats + all workers
added: 2026-09-20
last-confirmed: 2026-09-20
---

> Extends the owner's `~/Code` placement rule (#5409) from **where** a temporary
> worktree lives to **how long** it lives. Same shape as
> [`live-eval-owns-its-teardown.md`](live-eval-owns-its-teardown.md): the thing
> that creates a side effect owns its removal, and because the creator can die
> before it cleans up, a **sweep by the next run** is the part that actually
> holds.

## Rule

**Whoever creates a worktree removes it in the same unit of work.** The seat that
cuts a scratchpad checkout to compare two commits, the worker that cuts one at a
PR head, the Agent tool that cuts one for an isolated subagent — each owns its
removal, on the failure path as much as the success path.

**And because a session can be compacted, crash, or simply be closed mid-flight,
every seat sweeps orphans at kickoff.** Teardown alone does not survive the
failure mode that actually happens.

**Never leave a worktree locked past your own session.** A lock outlives the
process that took it and makes the worktree unremovable by anyone else — it
converts a temporary resource into a permanent one that only a human can clear.

## Why

The placement rule alone does not bound lifetime, and lifetime is what bit us.

2026-09-20, one clone (`~/Code/capgemini-orbis`) carried **60 worktrees**. The
owner found them by eye. Their distribution is the whole argument:

| source | count | placement rule |
|---|---|---|
| `.claude/worktrees/agent-*` (Agent-tool isolation) | 22 | not covered — the rule never contemplated them |
| QA scratchpad `wt-*` (seat-level hand verification) | 17 | **compliant** |
| `<seat>/.worktrees/*` | 8 | **compliant** |
| `/private/tmp` hand-made | 3 | compliant |
| `~/.claude/jobs/*` | 2 | not covered |
| `~/Code` siblings | 8 | the only ones the rule forbade |

**Forty-three of the sixty were in locations the rule explicitly blesses.** The
2026-09-18 fix (#5409) moved the sprawl; it did not stop it. A rule that says
"put it here" and never says "and take it away" relocates the problem into the
approved directory.

Three specific holes this exposed:

1. **The teardown that exists binds the worker, not the seat.**
   `agents/quality-worker.md` step 7 already says *"remove your worktree… report a
   removal that fails; never ignore it"*, and its report carries
   `worktree=<removed | NOT REMOVED: cause>`. That rule is sound and was not the
   problem. The 17 QA scratchpad worktrees were cut **by the seat**, by hand,
   outside the worker protocol — named `wt-5340-base`, `wt-pr5345`, `wt5339v2` —
   and nothing bound them at all. The seat was obeying
   [`a rule of ours`](../../seats/quality-engineer/KICKOFF.md) that says verify on
   a clean worktree, with no counterpart telling it to clean up.

2. **Agent-tool worktrees are created `locked`.** Nobody wrote them and nobody
   could remove them. Ten survived every sweep, including two held by duplicate
   sessions that had already exited. They only cleared once those sessions were
   confirmed gone and the locks were released by hand.

3. **Removal is slow enough to look like a no-op.** Each of these carries a full
   `node_modules`; `git worktree remove --force` on three of them exceeded a
   120-second timeout. A loop over thirty is a half-hour job. The owner ran a
   sweep twice and reported it doing nothing — which is exactly what a long
   silent loop looks like. **A bulk sweep must print per-item progress**, or its
   operator cannot distinguish "working" from "broken". Same family as
   [`a-check-must-be-able-to-report-its-own-failure.md`](a-check-must-be-able-to-report-its-own-failure.md).

## Never sweep blind — preserve first, then remove

A sweep that discards unpushed work is worse than the sprawl. On 2026-09-20 one
of these worktrees held the **only** copy of a real fix (`5f67f0b0f`, #5426) —
committed, never pushed, invisible on GitHub, and reported by this seat as *"no
branch, no PR, nothing"* because the check looked only at the remote.

Before removing any worktree you did not create this session, in this order:

1. **Is its HEAD reachable from a remote?**
   `git branch -r --contains <sha>` — non-empty means the commits are safe.
2. **If not, pin it before you touch it.**
   `git update-ref refs/salvage/<name> <sha>` — a ref makes the commits
   unreachable-proof regardless of what happens to the directory.
3. **Is the tree clean?**
   `git -C <wt> status --porcelain` — non-empty means uncommitted work that
   `--force` will destroy. Capture a diff to the scratchpad before deciding.
4. **Only then remove**, and print each removal as it happens.

Steps 1–3 are cheap and mechanical. They are what made today's cleanup lossless:
15 salvage refs, every HEAD accounted for, nothing discarded.

### Report the invariant you actually held, not its easier half

The invariant is **reachable OR salvaged**. It is not "reachable".

Having run the sweep, this seat reported to the owner that *"every HEAD [was]
checked reachable-from-origin first"*. That is false, and the salvage refs are
themselves the proof: **14 of the 15 are unreachable from any remote branch** —
they exist precisely because step 1 said no and step 2 fired. The one reachable
ref is reachable only because the sweep pushed it. The QA seat caught it by
running `git branch -r --contains` on one salvage ref and getting zero, against a
positive control returning non-zero.

Nothing was lost and the procedure worked exactly as written. The defect is in
the *sentence*, and it is the more dangerous artifact: "I checked, they were all
reachable" is a reassurance that stops the next reader checking, and here the
check would have contradicted it. A two-branch invariant summarised as its easier
branch reads as a stronger claim than the one you are entitled to, and it is
unfalsifiable in exactly the place someone would want to falsify it.

When you report a disjunctive check, report both branches with counts:
*"n reachable, m salvaged, here are the refs"*. Same family as
[`a-null-result-is-not-evidence.md`](a-null-result-is-not-evidence.md) — the claim
must survive the reader re-running it.

## How to apply

**Every seat, at kickoff: list worktrees with reachability and age, never a bare
count.** This is the load-bearing step — it is what collects whatever the last
session did not.

```sh
git worktree list --porcelain | awk '/^worktree /{w=substr($0,10)} /^HEAD /{print substr($0,6), w}' |
  while read -r SHA WT; do
    printf '%s  reachable=%s  %s\n' \
      "$(git log -1 --format=%ad --date=short "$SHA")" \
      "$(git branch -r --contains "$SHA" 2>/dev/null | grep -c .)" \
      "$WT"
  done | sort
```

Anything unreachable **and** older than the current sprint is a fossil: verify
its substance shipped, then remove it under the preserve-first discipline below.

**A count is not a check, and this rule shipped with one.** The first draft of
this section said `git worktree list | wc -l`. The QA seat killed it the same
day: after the 2026-09-20 sweep the count reads 7 and looks healthy forever,
because **two of the seven survivors were two-month-old fossils** —
`~/.claude/jobs/aa5bb19d/tmp/hotfix-v130` and `.../forwardport-main`, both on
branches that exist on no remote, both carrying a #3466 P0 fix that shipped on
2026-07-16 via PRs #3468 and #3469. They survived two months and every pass of
the sweep that was looking for them, because the sweep's own residue had become
the baseline. A threshold check cannot distinguish five live worktrees from five
live plus two fossils, and the fossils are exactly what accumulates silently.

That is this week's defect one layer up, in the guard written to stop it: the
instrument reads a number that no longer means what it meant when the threshold
was chosen. **Whenever a kickoff check is a count, ask what a stale entry inside
a plausible total would look like.** Usually: identical.

**Every seat, before you stop:** remove the worktrees you created this session.
Report any that would not remove, with the cause — never silently leave one.

**When cutting one by hand:** put it where #5409 says, and decide its removal in
the same breath you decide its creation. If you cannot say when it dies, do not
cut it.

**Never `git worktree lock`** unless you are protecting a removable-media or
network path, which is the feature's actual purpose. A lock as
"don't touch my stuff" is a leak with a longer fuse.

**When a sweep is bulk:** echo per item. Silence for thirty seconds reads as
failure and invites someone to re-run it, or to conclude — as this seat wrongly
did — that the operator never ran it.

## Verify it, don't assert it

List before and list after, in the same report — the reachability-and-age listing
above, not a count. A seat reporting "cleaned up" without it is asserting, not
verifying, and a seat reporting only a total has verified that the number moved,
which is a weaker claim than it reads as. See
[`a-null-result-is-not-evidence.md`](a-null-result-is-not-evidence.md).

## Cautionary tale

The 60 accumulated over roughly three weeks across five seats, none of them doing
anything wrong by the rules as written. The cost was not disk: it was that
`git worktree list` — the instrument every seat uses to orient — became unreadable,
duplicate sessions held live branches hostage behind locks, and a real fix sat
unpushed and invisible inside one of them while its issue read `In Progress` to
everybody else.

Related: [`live-eval-owns-its-teardown.md`](live-eval-owns-its-teardown.md),
[`finish-report-stop.md`](finish-report-stop.md),
[`../architecture/a-guard-inspects-the-artifact-not-the-invocation.md`](../architecture/a-guard-inspects-the-artifact-not-the-invocation.md).
