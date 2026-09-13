---
title: An AC must name who can satisfy it, and with what access, before the item goes Scoped
status: active
scope: pm
---

# An AC must name who can satisfy it — before `Backlog → Scoped`

**Rule.** Before flipping an item to `Scoped`, check every acceptance criterion against one
question: **who can satisfy this, with what they have today?** If the answer is not "the
producer seat, with the access it already has", the criterion is **not pre-merge** and must be
tagged inline as a gate, or split out.

## Why

On 2026-08-19/20 a single PM seat produced **nine** blocked items in one day. Not one was an
engineering failure. Every one was an acceptance criterion that named no one who could satisfy it:

| Item | The criterion demanded | Who could actually do it |
|---|---|---|
| #4191 | a blind panel verdict | 3 humans, scheduled |
| #4194 · #4195 | measurements "on DEV" | nobody — no DB access exists |
| #4193 | a *required* check on `main` | the owner (branch protection) |
| #4189 | ">= 20 real-content exemplars" | real deals closing |
| #4324 | two named incident artifacts | nobody — the files are not in the repo |
| #4331 | `n_panelists >= 3` | 3 humans, scheduled |

Each surfaced only when the quality seat physically reached it, so clearing one exposed the next.
From the outside this reads as endless churn; it is actually **a queue of framing defects being
discovered in sequence**. The producer builds correctly, the verifier fails it correctly, and the
item bounces — costing a full cycle every time, on work that was never wrong.

## How to apply

At scoping time, tag **every** AC line inline. Do not append a note at the bottom of the body — a
verifier reads the numbered criteria, and a trailing caveat does not change what line 4 says.

- **`[PRE-MERGE]`** — the producer can prove it with the access it has (local Postgres, fixtures,
  test suites). QA can pass it now.
- **`[POST-<X> GATE — #NNNN]`** — needs something the producer cannot conjure: a deployed
  environment, real data, people's time, an owner-gated setting. **Gates `Released`, never merge**,
  and names the issue that unblocks it.
- **Split** when the gated half is a materially different build. The successor is
  **EPIC-blocking** — relocating a requirement in time must never shorten an exit gate.

Three sharpening questions that catch most of it:

1. **Access** — does satisfying this need an environment, database, or credential the seat has?
   If unsure, assume no and check.
2. **Existence** — does every file, fixture, mechanism, and constant the AC names actually exist
   on `origin/main` today? Grep for it.
3. **Authority** — can the producer seat do this, or does it need an owner decision, a repo
   setting, or another squad?

## The corollary that costs the most

**Nobody fails a producer for infrastructure it cannot reach.** When a criterion turns out to be
unmeetable by access, the verifier marks it *unverifiable-by-access*, names the gap, and routes it
to the PM. The PM re-frames it. It is never absorbed by the producer as rework, and never waived
to make a build pass.

Related: [`finish-report-stop.md`](finish-report-stop.md) ·
[`../../workflow/definition-of-ready-done.md`](../../workflow/definition-of-ready-done.md)
(the Definition of Ready's "dependencies known" box is what this rule operationalises).
