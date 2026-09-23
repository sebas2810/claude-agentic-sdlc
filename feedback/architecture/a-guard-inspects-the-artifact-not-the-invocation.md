---
title: A guard inspects the artifact, not the invocation — a check that cannot see the artifact must fail, not pass
status: active
scope: all-seats
added: 2026-09-18
last-confirmed: 2026-09-18
---

> Stands under the spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)),
> principle 6 (ACI / tool design is first-class) and invariant 5 (no false-green).
> A guard reading a proxy for the thing it forbids is a false green at the
> enforcement layer, and it is green **precisely when it is blind**.

## Rule

A control must read the **artifact** it governs — the commit object, the
rendered output, the persisted row, the deployed config. Reading a **proxy**
for that artifact — the command line that produced it, the arguments a function
was called with, a status field describing a budget, a test fixture standing in
for a behaviour — is a defect whenever the proxy can diverge from the artifact.

And when the artifact is not inspectable, the check **fails**. It does not pass.

This is the generalisation of `guard-git.sh` check 6, which already states it
for one case:

> *No extractable literal (a variable, stdin, a GraphQL payload) is treated as
> UNSAFE, not safe.*

Invert the default. The unsafe case is the one the instrument **cannot see**,
not the one it sees and dislikes.

## The test

Two questions, asked of any gate, hook, AC verifier, grep, log filter, metric
query or control test:

1. **What object is it actually reading?**
2. **Can the thing it forbids exist without appearing in that object?**

If the answer to 2 is yes, the check is decorative. It will return green for
"absent" and green for "unobservable", and nothing downstream can tell those
apart.

## Why

On 2026-09-18, four failures across three seats turned out to be one failure:

> **a check whose passing state is "I did not see anything", with nothing
> establishing that it could have seen it.**

| # | Check | Artifact it governs | Proxy it actually read |
|---|---|---|---|
| 1 | `guard-git.sh` check 2 | the commit message | the bash command string |
| 2 | a control test for "the agent asked honestly" (#5427) | that the agent asked | an `agent_text` fixture with **no question in it** |
| 3 | an AC verifier, `git grep "code=" turn_finalize.py` (#5275) | the codes in the file | a pattern matching nothing in the repo |
| 4 | `gh api rate_limit` | the GraphQL budget | a field reporting `5000/5000` at zero remaining |

Each returned green. In each case green meant **no signal**, and no one had
asked whether signal was reachable.

## Cautionary tale

`guard-git.sh:222` screens commits for AI attribution with:

```bash
if printf '%s' "$CMD" | grep -Eqi 'co-authored-by:[[:space:]]*claude|generated with .{0,3}claude code'; then
```

`$CMD` is the command string, so the trailer is caught only when the author
typed it inline. Transcribing the exact regex and running real command shapes
against it, with two positive controls:

```
COMMAND SHAPE                                verdict
-----------------------------------------------------
POSITIVE CONTROL: -m with trailer inline     BLOCKED
POSITIVE CONTROL: -m with generated-with     BLOCKED
git commit -F msgfile                        PASSES THROUGH
git commit -m "$MSG" (variable)              PASSES THROUGH
git commit --template=/tmp/t.txt             PASSES THROUGH
git commit (opens editor)                    PASSES THROUGH
git commit --amend --no-edit                 PASSES THROUGH
heredoc to file, then commit -F              PASSES THROUGH
```

Both controls block, so the six pass-throughs are read zeros rather than a
broken harness. The commit is never inspected — only the sentence that produced
it. An attributed commit reached an open PR this way (`7c533b594`) with the hook
installed and working exactly as written.

The demonstration that settles it: the QA seat's first attempt to build that
table **was itself blocked**, because the trailer text appeared in its own bash
command. The hook stopped a seat *describing* an attributed commit while a real
one went past untouched.

Check 6 sits eight lines below check 2 in the same file, holding the correct
principle. The inversion was applied to label writes and never propagated.

## How to apply

- **Name the object in the check's own comment.** "Reads `COMMIT_EDITMSG`", not
  "checks for attribution". A check that cannot name its object is reading a
  proxy.
- **Reserve a third outcome** — `pass` / `fail` / `could-not-inspect` — and
  route the third to fail. Two states force "unobservable" to impersonate
  "absent".
- **Write the positive control into the check, not into the reviewer's
  memory.** A gate whose passing state is an absence ships with a case that
  makes it fire.
- **For control tests specifically: the honest case must contain the thing
  being guarded.** A control standing for "the agent asked and the operator
  answered" must contain a question. A control without one cannot distinguish a
  working guard from a broken one, and its green is why a suite's `N passed`
  and an AC's claim can disagree.
- **For ACs: if "no results" is the passing state, the criterion carries the
  query that must return non-zero first.** See
  [`../workflow/a-null-result-is-not-evidence.md`](../workflow/a-null-result-is-not-evidence.md).
- **Reviewers:** when a gate is cited as coverage, ask what it reads before
  accepting it as enforcement. "There is a hook for that" is not the same claim
  as "the hook can see that".

## Related

- [`one-control-one-implementation.md`](one-control-one-implementation.md) — the
  sibling failure: the control is real and correct, but a forked copy drifts.
  Here there is one copy and it reads the wrong object.
- [`weakening-a-default-must-signal.md`](weakening-a-default-must-signal.md) — a
  control that stops controlling must fail loudly. A proxy-reading guard stops
  controlling without ever changing.
- [`../workflow/a-null-result-is-not-evidence.md`](../workflow/a-null-result-is-not-evidence.md)
  — governs **reading** an absence.
- [`../workflow/a-check-must-be-able-to-report-its-own-failure.md`](../workflow/a-check-must-be-able-to-report-its-own-failure.md)
  — governs **building** a check that can say "I could not tell you". This rule
  is the third case: the check runs fine, reports confidently, and is looking at
  the wrong thing.
