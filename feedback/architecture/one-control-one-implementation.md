---
title: One control, one implementation — a forked copy of a shared control drifts, and the drift is silent
status: active
scope: all-seats
added: 2026-08-13
last-confirmed: 2026-08-13
---

> Stands under the spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)),
> principle 6 (ACI / tool design is first-class) and invariant 5 (no false-green,
> no silent-degradation). A control that silently stops enforcing is a false green
> at the enforcement layer.

## Rule

An enforcement control — a hook, a gate, a guard, a policy check — has **exactly
one implementation** per behaviour. When a second copy exists, it is a **defect
with a deletion date**, not an architecture.

If a fork is genuinely unavoidable during a transition, it carries: a `## Retires`
line naming the copy to be deleted, an end date, and a check that fails while both
exist. "Both exist" is never the steady state.

## Why

A forked control does not fail loudly. It **keeps passing** — on the subset of
cases it still handles — while silently no longer enforcing the rule the other
copy learned about. Every signal you would normally rely on reads green:

- the hook still fires, so it is observably "installed"
- it still blocks the obvious cases, so spot-checking finds nothing
- the copy that lost a rule is byte-for-byte plausible; nothing distinguishes
  "this guard has 3 rules" from "this guard used to have 4"

The usual defences do not apply. Tests live with each copy, so each passes its
own. Code review sees one file, not the divergence between two. And the drift
grows monotonically: every fix applied to one copy widens the gap, so the longer
both survive, the less the weaker one enforces.

This is the enforcement-layer form of silent degradation. The control did not
break — it **quietly stopped covering a case**, which is indistinguishable from
covering it until someone reads both files side by side.

## How to apply

**Before adding a control**, check whether the behaviour is already intercepted.
Two hooks on the same tool, two validators of the same input, two scripts parsing
the same command class — that is one control with two heads.

```bash
# is this hook point already occupied?
jq '.hooks.PreToolUse' .claude/settings.json
ls .claude/hooks/
```

**Extend the existing implementation** rather than shipping a sibling. A new rule
inside one guard is a rule; a new guard beside an old one is a fork.

**If you find a fork**, do not patch the copy in front of you and move on — that
is what widens the gap. Diff the two, port the whole delta both ways, and file the
consolidation with a date.

**Make single-ownership assertable.** "One guard" is only true if something checks
it. Without a check, this recurs, and it recurs invisibly.

## Cautionary tale

2026-08-12, reference instance. The product repo ran `.claude/hooks/bash-guard.mjs`
— a parallel implementation of the framework's `onboarding/hooks/guard-git.sh`,
forked long enough ago that nobody treated them as the same control.

`git` accepts options **before** the subcommand. The `.mjs` detection was
adjacency-only, so:

- the plain protected-ref push was blocked
- the same push with `-C <dir>`, `--no-pager`, or `-c k=v` between `git` and the
  verb was **allowed**

The Tier-1 "never push to a protected ref" gate — the single most load-bearing
control in the SDLC — **did not exist** for any of those forms. `guard-git.sh`
already carried the fix, with a comment naming that exact hole. The fork never
received it.

Nothing detected it. No test compared the two, no CI job asserted they agreed,
and it surfaced only because someone hit an unrelated false-positive and happened
to read the file. The control had been reporting itself healthy the entire time,
because from the inside it was: it fired, it blocked things, it just no longer
blocked *that*.

Filed as orbis-platform#4064; consolidation steer on the framework side in
sebas2810/claude-agentic-sdlc#53.
