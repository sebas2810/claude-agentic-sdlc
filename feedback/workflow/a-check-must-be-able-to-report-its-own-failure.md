---
title: A check that folds an error into a negative answer cannot report its own failure
status: active
scope: all-seats
added: 2026-09-06
last-confirmed: 2026-09-06
---

> Stands under the ORBIS Agentic SDLC spine (../../agentic-operating-model.md).

# A check that folds an error into a negative answer cannot report its own failure

Most tools distinguish **"no"** from **"I could not tell you"**. Shell idioms
routinely destroy that distinction, and a check that cannot signal its own
breakage will answer confidently while being blind.

Two habits do the damage, usually together:

- `2>/dev/null` — discards the message explaining *why* it failed
- `cmd && A || B` — folds **every** non-zero exit into `B`, including the ones
  that mean *error*, not *false*

## Why

- A verification you cannot distinguish from a broken verification is not
  evidence. It has the shape of a finding and the content of a coin flip.
- It fails in the confident direction. A crashed check returns the negative
  branch, which reads as a real result and gets reported as one.
- It is the anti-guard family in miniature: a control that reports a state it
  did not establish. Same class as a test pinning the buggy value, or a gate
  that exits 0 unconditionally.

## How to apply

- **Verify the input resolves before asking a question about it.** Most false
  negatives are a missing file/ref/row, not a real "no".
- **Branch on the actual exit code** when a tool has more than two outcomes:

  ```bash
  git rev-parse --verify -q "origin/$b" >/dev/null || { echo "ref absent — no merge claim"; exit 2; }
  git merge-base --is-ancestor "origin/$b" origin/main; rc=$?
  case $rc in
    0) echo merged ;;
    1) echo "not merged" ;;
    *) echo "ERROR rc=$rc — not an answer" >&2; exit 2 ;;
  esac
  ```

- **Do not `2>/dev/null` a check whose result you intend to act on.** Silence
  the noise, never the diagnosis.
- **Reserve a third outcome.** `pass` / `fail` / `could-not-determine`. Two
  states force an error to impersonate one of them.
- **Reviewers:** when a finding rests on a negative, ask what the check does
  when its input is missing. If the answer is "the same thing", the finding is
  unverified.

## Cautionary tale

2026-09-06, the PM seat reported that `feat/4488-flow-integrity` was carrying
13 days of unshipped work, filed it as a P1 class finding (#5080), told a
producer their issue (#4516) was correctly blocked on it, and stated all of it
as independently verified.

It had promoted on time — PR #4541 to `main`, 2026-08-25 — and its branch was
deleted on merge, correctly. The check was:

```bash
git merge-base --is-ancestor origin/$b origin/main 2>/dev/null && echo "on main" || echo "NOT an ancestor"
```

Git had reported the truth plainly: `fatal: Not a valid object name`, **exit
128** — a missing ref, versus **exit 1** for a real "not merged". The `2>/dev/null`
swallowed the `fatal:`, and `||` folded 128 into the same branch as 1. A second
"corroborating" check, `git log main..origin/$b` returning 0, shared the
identical blind spot.

Cost: a wrong P1 issue, a producer told a phantom blocker was verified, and a
first correction that *also* got the mechanism wrong — claiming git could not
distinguish the two cases, when it always had. The owner caught it by running
the command by hand.

## Related

- [`a-null-result-is-not-evidence.md`](a-null-result-is-not-evidence.md) — the
  sibling, at the other end. That rule governs **reading** an absence; this one
  governs **building** the check that produced it.
- [`../architecture/no-silent-degradation-on-load-bearing-paths.md`](../architecture/no-silent-degradation-on-load-bearing-paths.md)
  — invariant 5. A swallowed error on a load-bearing path is a defect.
- [`../architecture/weakening-a-default-must-signal.md`](../architecture/weakening-a-default-must-signal.md)
  — a control that stops controlling must fail loudly, not answer quietly.
