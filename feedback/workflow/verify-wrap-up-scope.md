---
title: Verify wrap-up scope concretely before estimating
status: active
scope: pm
added: 2026-05-12
last-confirmed: 2026-05-13
---

> Stands under the ORBIS Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

When estimating "small wrap-up" work to close an EPIC or release, verify each step concretely. "Just run the eval" is wrong when the eval has no goldens / no enum / no harness yet.

## Why

Wrap-up scope tends to look small from the outside ("just one more thing"). Inside, it often requires:
- Data setup (corpora, seeds, fixtures)
- Schema changes (enum additions, migrations)
- Test harnesses (the runner that hasn't been written yet)
- Flag validation (the conditions the rollout flag checks)

Estimating "small" without verifying each step means you'll miss days of actual work and surprise yourself/stakeholders.

## How to apply

For each "small wrap-up" step you list:

- [ ] Code path exists (open the file, confirm)
- [ ] Required inputs exist (corpora seeded, enum values added, fixtures present)
- [ ] Harness exists if needed (don't promise an eval that has no runner)
- [ ] Flag validation: what conditions does the rollout flag check, and are those met?
- [ ] Smoke evidence path: how will you prove the wrap-up succeeded?

If ANY of the above is "no" — the wrap-up is LARGER than "small." Estimate accordingly.

## The verification idiom

```bash
# For each wrap-up item, run a quick concrete check:
ls infra/scripts/check-meddpicc-scoring-anchors.ts       # harness exists?
ls infra/scripts/fixtures/meddpicc-scoring-anchors.json  # corpus exists?
grep "FOUNDATION_AGENT" packages/db/schema.prisma        # enum added?
gh issue view <flag-rollout-issue> --json closedAt       # flag conditions met?
```

5 minutes of verification saves hours of surprise.

## Cautionary tale

Pre-rule: a session estimated "we just need to run the v1.0 eval suite to call it done — 30 min." 30 min later: the eval suite didn't exist. Building the runner + seed corpus + flag wiring + tests + smoke evidence took ~2 days. The "30 min" estimate had been wishful.

Rule cost: 5 minutes of concrete verification per wrap-up unit. Saves: days of surprise.

## Especially relevant for

- Release-promote scope ("just need to sweep")
- EPIC close-out checklists
- "Last thing before we ship" lists
- Cross-EPIC dependencies that look resolved but aren't
