---
title: A live eval that writes to a deployed environment owns its teardown
status: active
scope: engineer + quality-engineer
added: 2026-08-13
last-confirmed: 2026-08-13
---

> Stands under the spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)),
> invariant 2 (evals are the oracle) and invariant 5 (no false-green). An eval
> that pollutes the environment it measures is corrupting its own oracle.

## Rule

Any eval or harness that mints real records against a **deployed** environment is
responsible for cleaning them up. A green eval that leaves orphaned
production-shaped data behind is itself a **no-false-green failure**: it reports
success while quietly degrading the environment every other eval — and every real
user — shares.

## Why

The data is invisible and therefore un-purgeable. Rows created by an eval look
exactly like rows created by a user, so nobody can tell them apart later, and the
cleanup that never happened compounds silently for as long as the eval has
existed.

It also corrupts measurement. Evals are the oracle for "done"; an oracle running
against an environment its own prior runs polluted is measuring its own residue.

## How to apply

A live eval writing to a deployed environment needs, at minimum:

1. **A marker on every record it creates** — a visible tag on a name/title field,
   or a dedicated synthetic identity. Never rely on finding the record by content
   alone.
2. **An idempotent pre-run sweep** — before minting this run's records, clean up
   anything marker-tagged left from a prior run. This is what survives a crash:
   the eval's *own* teardown need not be perfect if the *next* run collects what
   it missed.
3. **Same-run teardown in a `finally`** — delete exactly what this run minted,
   regardless of pass, fail, or raise. The pre-run sweep alone leaves a stray
   record from every run until the next one happens to fire.
4. **Never delete cost-ledger rows.** A live run incurs real spend and writes a
   real cost record for it. Deleting that would make the ledger understate actual
   billing — a worse failure than the orphaned records the teardown exists to fix.
   Clean up what the eval *created*, never what it *spent*.
5. **Build it once, shared.** If more than one eval mints the same shape of
   record, put the marker + sweep + teardown primitive in one importable place
   rather than bolting a bespoke `finally: delete` onto each script.

## When the write path isn't a database row

Not every side effect is a row. On the instance that surfaced this, a second real
write path had gone unmodeled in the eval's own acceptance criteria: an agent's
write tool created an internal record **and** mirrored it to an external tracker.

External systems are not delete-and-forget — some have no delete at all, or gate
it behind org-owner permissions. The right pattern there is usually **close and
tag**, not delete, and the teardown must never touch a genuinely user-created item
it did not make. When a live eval's write surface reaches an external system,
treat that as its own design question, not an assumed extension of the row-teardown
primitive.

## Verify it, don't assert it

Hold out the teardown call: confirm the eval leaves a marker-tagged record behind
and that the next run's sweep catches it. Restore it: confirm a normal run leaves
**zero net-new records**.

A teardown primitive with no test proving it actually fires — including on the
exception path — is exactly the kind of control that silently stops working the
next time someone refactors the caller. That is
[`../architecture/one-control-one-implementation.md`](../architecture/one-control-one-implementation.md)'s
failure mode wearing different clothes.

## Cautionary tale

2026-07-13, a live instance: the intake evals minted a real opportunity record, a
real session, and cost rows on **every** run against deployed DEV, with no
teardown anywhere in the call chain and no marker distinguishing an eval record
from a real one. It had been accumulating for as long as the evals existed, and
nothing had ever failed.

## Provenance

Written on a live instance and carried there as a local-only rule until
2026-08-13. Generalised on upstreaming — the principle binds any fork running
evals against a deployed environment.
