---
title: Weakening a safety default must emit a signal — the change that removes a gate looks like any other one-line diff
status: active
scope: all-seats
added: 2026-08-13
last-confirmed: 2026-08-13
---

> Stands under the spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)),
> invariant 5 (no false-green, no silent-degradation) and principle 7 (the human
> owns the irreversible). A default that moves from *gate* to *allow* is a change
> in what the system is permitted to do, and it must be visible as one.

## Rule

A change that moves a default **toward permissiveness** — gate → allow, ask →
auto, verify → assume — is not an ordinary diff. It requires, in the PR itself:

1. **The claim it rests on, verified.** If the justification is "the old value no
   longer works", show the command and its output. One `--help` invocation is
   cheaper than the outage it prevents.
2. **Its own subject line.** It never rides along inside a PR about something
   else. A permission change bundled into a feature PR is reviewed by whoever was
   reading about the feature — which is to say, not reviewed.
3. **A test asserting the posture**, not the string, so a rename does not silently
   drop coverage.
4. **The blast radius, named.** In vendored or forked code, say how far it reaches.

The `--dangerously-*` flag family, permission modes, verification toggles, and any
rule removed from a guard are all in this class.

## Why

These changes are indistinguishable from routine ones by every signal we normally
use. The diff is one line. The tests pass — because no test asserted the default.
The CI is green, and *stays* green, because green measures whether the code runs,
not whether the system is still gated.

They are also disproportionately likely to arrive on a **false premise**, because
the motivating symptom is usually real and urgent (something is broken, the seat
will not start, the build fails). Under that pressure the first plausible
explanation gets acted on, and "remove the thing that is blocking us" is always
plausible. The premise itself is rarely checked — before *or* after.

And in vendored code the reach is invisible at review time. A file that every fork
inherits on its next sync has the same review surface as a local script, so the
reviewer weighing a one-line change has nothing telling them it lands in every
instance downstream.

## How to apply

**Authoring** — if a change reduces a default, split it into its own PR and state
the verification inline:

```bash
$ claude --help | grep -A3 permission-mode
  --permission-mode <mode>   Permission mode to use for the session
                             (choices: "acceptEdits", "auto",
                              "bypassPermissions", "manual", "dontAsk", "plan")
```

**Reviewing** — for any diff touching a permission, a `--dangerously-*` flag, or a
guard's rule set, ask two questions: *what is the evidence for the premise*, and
*what fails if this is wrong?* If the answer to the second is "nothing, silently",
that is the finding.

**Diagnosing** — before removing a gate to fix a symptom, rule out the environment.
A binary that exits at launch, a command that will not run, a hook that misfires:
these look like configuration defects and are frequently local breakage. Removing
a safety control is never the cheapest hypothesis to test first.

## Cautionary tale

2026-08-10 → 2026-08-12, framework repo. `onboarding/seat-launch.sh` launched every
seat with `--permission-mode acceptEdits`. An issue reported that seats exited
immediately at launch and diagnosed the flag as removed in the claude 2.x CLI. The
fix replaced it with `--dangerously-skip-permissions` and merged as the smaller
half of a PR whose stated subject was multi-cloud provider support.

The premise was false. The flag was present in the installed CLI the whole time,
with `acceptEdits` a valid choice — verifiable in one command that nobody ran, in
either direction. The actual cause was a broken `/opt/homebrew/bin/claude` symlink
pointing at a Linux ELF binary from another platform's bundle: local breakage that
no framework change could fix, and that this change did not fix.

For ~53 hours, **every seat in every instance that vendored the framework launched
with the permission gate removed.** Nothing detected it: `seat-launch.sh` had no
test, the change was not the PR's subject, and the file is vendored, so the reach
was never visible on the PR's face. It was found by someone reading the file for an
unrelated reason.

Fixed in sebas2810/claude-agentic-sdlc#63; the gate that would have caught the
class is sebas2810/claude-agentic-sdlc#64.
