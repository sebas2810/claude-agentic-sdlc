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
   yourself, in a fresh context, with the issue's acceptance criteria and the
   PR's base and head. Save its whole response to a file outside the tracked
   tree, for example `"$(git rev-parse --git-dir)/delivery-review-<item>-<head>.txt"`.
3. Start `engineer-worker` again with `phase: deliver`, the PR, the reviewed
   head and that file.
4. On `result=FAILED`, start a rework `phase: build` with the failing lines,
   then continue from step 2. On `DELIVERED`, `BLOCKED` or `SKIPPED`, re-run
   discovery and take the next item. On `STALE` or `ERROR`, report it and stop
   the drain: an error is not a result to drain past.

The seat starts the reviewer, not the worker, for two reasons: a subagent
cannot start another subagent, and a reviewer started from the context that
built the fix would not be independent.

Producer items run one after another, because they share the seat's worktree.

## The quality drain

1. Resolve the cap: `CAP="$(bash onboarding/lib/resolve-qa-max-parallel.sh)"`.
   It reads `QA_MAX_PARALLEL` from the environment, then from `.env.local`
   (bootstrap copies it there from `sdlc.config`), and defaults to 3. A value
   that is not a whole number of at least 1 exits 2 with the cause: report it
   and stop, rather than run with a cap nobody chose
   ([the rule](../feedback/architecture/weakening-a-default-must-signal.md)).
2. Discover `status:delivered` and drop rows authored outside
   `$SQUAD_AUTHORS`, as `commands/check.md` says.
3. Start one [`quality-worker`](../agents/quality-worker.md) per row in
   `mode: parallel`, at most `$CAP` at a time, each in its own clean worktree
   at the PR head. When one reports, start the next row, until every row has
   had a worker.
4. Run the rows reported `NEEDS-SERIAL` one at a time, in `mode: serial`.
5. Re-run discovery immediately before reporting, and drain again if new
   `Delivered` items appeared.

Checks that need the local app, a local database or the browser run one at a
time because each is one resource per machine. Two workers driving the same
browser or resetting the same database produce verdicts about each other, not
about their items.

## What a worker carries

A subagent does not load personal memory or the seat's conversation. Each
worker definition therefore lists, under `## Rules you carry`, the repo files
that hold the seat's load-bearing rules, and reads them before acting.
[`check-worker-definitions.sh`](../onboarding/lib/check-worker-definitions.sh)
fails CI when a required file is dropped from a worker's list or no longer
resolves; its test is
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
tokens across one real item". Measure it on the seat's own transcript, not the
workers':

1. Run a producer `/check` that takes exactly one item from `Scoped` to `Delivered`.
2. Open that seat session's transcript, `~/.claude/projects/<seat folder>/<session id>.jsonl`.
   Worker transcripts sit under `subagents/` and are not part of the seat's context.
3. List each assistant call's context and the tools it called:

   ```
   jq -c 'select(.type == "assistant" and .message.usage != null)
          | {t: .timestamp, id: .message.id,
             ctx: (.message.usage.input_tokens + .message.usage.cache_creation_input_tokens + .message.usage.cache_read_input_tokens),
             tools: [.message.content[]? | select(.type == "tool_use") | .name]}' <session id>.jsonl
   ```

   A call repeats once per content block; keep one line per `id`.
4. `before` is the `ctx` of the call that started the item's first
   `engineer-worker`. `after` is the `ctx` of the first call after the item's
   last worker report came back. The criterion holds when `after - before < 10000`.

For drains as a whole, `operations/metrics/seat-tokens.py` reports each seat's
average context and spend per active day across a window, so a window before
this change can be compared with one after it.
