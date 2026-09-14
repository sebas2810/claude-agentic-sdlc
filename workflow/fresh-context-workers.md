---
title: Fresh-context workers, one issue per context
status: active
scope: engineer, quality-engineer, pm, scrum-master
---

# Fresh-context workers

> A seat's session is the drain, not the workbench. Each item a producer builds
> and each item the quality seat verifies runs in a fresh subagent, and the seat
> keeps only that worker's report.

## Why

Fourteen days of one instance's seat transcripts: 78% of weighted token spend
was cache reads, the average call carried 450k to 490k tokens of context, and
93% of spend came from calls made above 200k tokens. Sessions compacted only
near the model's limit, so every item paid again for every item before it. A
replay of the same sessions estimated 44% less spend with a fresh context per
issue and 35% less with a fresh context per drain. Those are estimates, not
measurements; [`seat-tokens.py`](../operations/metrics/seat-tokens.py) measures
the result.

## The producer drain

The seat's `/check` still discovers, filters by author and orders by priority,
as [`commands/check.md`](../commands/check.md) says. For the item it picks:

1. Start [`engineer-worker`](../agents/engineer-worker.md) with the `item` and
   `phase: build`, in the seat's own worktree.
2. On `result=REVIEW-NEEDED`, start [`delivery-reviewer`](../agents/delivery-reviewer.md)
   yourself, as a fresh subagent, with the issue's acceptance criteria and the
   PR's base and head. It is read-only and returns a short per-AC verdict
   (under 40 lines) ending in its `VERDICT:` line. Do not re-read the diff or
   add to the verdict: every line the seat handles lands in the seat's
   context, and keeping it out is what the worker split is for.
3. Start `engineer-worker` again with `phase: deliver`, the PR, the reviewed
   head and the reviewer's response, unchanged. The worker writes it to a file
   outside the tracked tree, for example
   `"$(git rev-parse --git-dir)/delivery-review-<item>-<head>.txt"`, and passes
   that file to `delivery-check.sh`.
4. On `result=FAILED`, start a rework `phase: build` with the failing lines
   from the report, a reviewer's FAIL lines included, then continue from step 2. The item
   is still `status:in-progress` from its claim, and a rework `build` accepts
   that state. On `DELIVERED`, `BLOCKED` or `SKIPPED`, re-run discovery and
   take the next item. On `STALE` or `ERROR`, report it and stop the drain: an
   error is not a result to drain past.

The seat starts the reviewer, not the worker, for two reasons: a subagent
cannot start another subagent, and a reviewer started from the context that
built the fix would not be independent.

Producer items run one after another, because they share the seat's worktree.

## The quality drain

1. Resolve the cap: `CAP="$(bash onboarding/lib/resolve-qa-max-parallel.sh)"`.
   It reads `QA_MAX_PARALLEL` from the environment, then from `.env.local`
   (bootstrap copies it there from `sdlc.config`), and defaults to 3. A value
   that is not a whole number from 1 to 999, or a `.env.local` line that
   mentions `QA_MAX_PARALLEL` in any form but `QA_MAX_PARALLEL=<n>`, exits 2
   with the cause: report it and stop, rather than run with a cap nobody chose
   ([the rule](../feedback/architecture/weakening-a-default-must-signal.md)).
2. Discover `status:delivered` and drop rows authored outside
   `$SQUAD_AUTHORS`, as `commands/check.md` says.
3. Start one [`quality-worker`](../agents/quality-worker.md) per row in
   `mode: parallel`, at most `$CAP` at a time, each as a fresh subagent in its
   own clean worktree at the PR head. Note each item number as its worker starts. When one
   reports, start the next row, until every row has had a worker.
4. Run the rows reported `NEEDS-SERIAL` one at a time, in `mode: serial`.
   That serial run is the only second worker an item gets in one drain.
5. Re-run discovery immediately before reporting. Drain again only for
   `Delivered` rows whose number you have not noted. A `CONSULT` or an `ERROR`
   writes no label, so those items still read `Delivered`; another worker
   would repeat the run and post the consult twice. Report them instead.

Checks that need the local app, a local database or the browser run one at a
time because each is one resource per machine. Checks that change the
deployed environment (a deploy, a migration, seeding or resetting data, a
config or flag change) run one at a time for the same reason: every worker
shares that environment. Two workers driving the same browser, resetting the
same database or redeploying the same environment produce verdicts about each
other, not about their items.

## Tiers: model and effort per item

Not every item needs the same model. Moving a button and finding why an agent
drops a turn cost very different amounts of thinking, and one model at one
effort for both overpays for the first and can underpay for the second. Each
worker therefore comes in three tiers, set in its definition's frontmatter:

| Item's label | Worker | Model | Effort | For |
|---|---|---|---|---|
| `tier:light` | `<role>-worker-light` | sonnet | low | UI moves, copy, config, docs |
| none, or `tier:standard` | `<role>-worker` | opus | medium | normal features |
| `tier:deep` | `<role>-worker-deep` | opus | high | a root cause, agent or eval work, a P0 |

The PM sets the label when it scopes the item. The drain never chooses a
tier by judgement: it runs
[`pick-worker.sh`](../onboarding/lib/pick-worker.sh) with the item's labels
and starts the worker it prints. Two rules move an item off its label:

- **Quality floor.** A quality worker on an `area:agentic` item runs at
  standard or above. A wrong PASS on agent work is the cheapest to make and
  the most expensive to find.
- **Escalation.** An engineer rework runs one tier above the label, capped at
  deep. A build that failed QA gets more model, not the same model again.

A second tier label, or a `tier:` label the script does not know, exits 2:
the drain reports it rather than run a tier nobody chose.
[`check-worker-definitions.sh`](../onboarding/lib/check-worker-definitions.sh)
fails CI when a worker's `model:` or `effort:` no longer matches its tier.
Each variant is a thin definition that points to its base worker, so the
rules a worker carries live in one file per role.

A seat without the plugin starts a general-purpose subagent with the picked
definition's text. The Agent tool's model override carries the tier's model;
effort applies only to a registered agent.

## Start every worker fresh, never as a fork

Start each worker, and the delivery reviewer, as a fresh subagent: the named
agent, or a general-purpose subagent given the definition file's text. Never
start one as a fork. A fork (`subagent_type: "fork"` in Claude Code's Agent
tool) copies the seat's whole conversation into the subagent, which re-reads
it on every call. The seat's own context stays small, so a fork looks like a
saving, but the item pays for the seat's history again inside the fork.

One instance's seat transcripts over about 20 hours: 17 forks started with
108k to 285k tokens of context and spent 12.4M input-equivalent tokens; 12
fresh subagents started with 15k to 55k (one at 234k) and spent 8.3M. A fork's
calls sit under `subagents/`, outside the seat's own context, so the
measurement below would pass a seat that forks; its pass line checks for forks
by name.

## What a worker carries

A subagent does not load personal memory or the seat's conversation. Each
worker definition therefore lists, under `## Rules you carry`, the repo files
that hold the seat's load-bearing rules, and reads them before acting.
[`check-worker-definitions.sh`](../onboarding/lib/check-worker-definitions.sh)
fails CI when a required file is dropped from a worker's list, when a listed
file or a repo path the definition names in backticks no longer resolves, or
when a path is absolute or climbs out of the framework root with `..`; its
test is
[`worker-definitions.test.sh`](../onboarding/tests/worker-definitions.test.sh).

A seat running the framework as a plugin gets the workers registered from
`agents/`. A seat without the plugin starts a general-purpose subagent and
gives it the definition file's text as its prompt, followed by the inputs.

## A fresh context per drain: PM and scrum-master

The PM and the scrum-master neither build nor verify, so they get no worker.
They get a fresh context per drain instead: the operator runs `/clear`, then
`/check`. Nothing a drain needs lives in the previous conversation; the board,
the labels and the issue threads carry the state.

## Measuring it

The producer criterion is "the seat session's context grows by less than 10k
tokens across one real item". Only a real item can show it, so it is checked
after adoption, not before merge:

- **Who:** the quality engineer. The producer seat ran the item, so it does
  not grade its own measurement.
- **Which item:** the first item a producer seat takes from `Scoped` to
  `Delivered` after the seats restart on the framework version that carries
  the workers.
- **Which transcript:** that producer seat's own session, not its workers'.
  It is `~/.claude/projects/<folder>/<session id>.jsonl` on the producer's
  machine, where `<folder>` is the seat worktree's absolute path with each
  `/` replaced by `-`; the session is the one that started the item's
  `engineer-worker`. Worker transcripts sit under `<session id>/subagents/`
  and are not part of the seat's context.

1. List the seat's own model calls in order, with each call's context size
   and the subagents it started:

   ```
   jq -s -c '
     map(select(.type == "assistant" and .isSidechain != true and .message.usage != null))
     | group_by(.message.id)
     | map({t: (map(.timestamp) | min),
            id: .[0].message.id,
            ctx: (.[0].message.usage | .input_tokens + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)),
            started: [.[].message.content[]? | select(.type == "tool_use" and (.name == "Agent" or .name == "Task"))
                      | "\(.input.subagent_type // "general-purpose"): \(.input.description // "")"]})
     | sort_by(.t) | .[]' <session id>.jsonl
   ```

   A call is written once per content block, so its lines are grouped by
   `id`. `isSidechain != true` keeps only the seat's own calls.
2. `before` is the `ctx` of the first call whose `started` names the item's
   `engineer-worker`. `after` is the `ctx` of the first call after the item's
   last worker report came back (the `deliver` run that reported `DELIVERED`).
3. **Pass line:** `after - before` is under 10000, and no `started` entry
   from the `before` call up to the `after` call begins with `fork:`, which is
   how the list shows a subagent started with `subagent_type: "fork"`. Post
   `before`, `after`, the difference, any `fork:` entries, the session id and
   PASS or FAIL on the issue that carries the criterion.

For drains as a whole, `operations/metrics/seat-tokens.py` reports each seat's
average context and spend per active day across a window, so a window before
this change can be compared with one after it.
