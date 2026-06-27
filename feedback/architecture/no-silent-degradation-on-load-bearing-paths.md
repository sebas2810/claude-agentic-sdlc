---
title: No silent degradation on load-bearing paths
status: active
scope: engineer / pm
added: 2026-05-18
last-confirmed: 2026-05-18
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

**On a load-bearing path, a swallowed failure is a defect.** A path is
**load-bearing** iff its silent failure makes a downstream consumer
present incomplete/incorrect state as correct (the #985 empty-summary /
#1017 businessLine-drop class). On such a path:

1. **Surface the failure** — raise *and* flip a detectable health signal.
   Never `except/catch → log.warning → continue` as if it succeeded. A
   server-log-only `warning` the user/monitor never sees is not surfacing.
2. **Schema-validate structured output before any persist or tool call** —
   invalid → repair-or-fail-loud, never a silent partial write.

`except/catch → log → continue` is allowed **only** where failure is
self-healing/retried and never corrupts the user-facing record — and that
classification must be **explicit** (stated in the change, not assumed).

## Why

"never raise; log.warning; continue" is *why* the empty-summary and
businessLine-drop bugs survived invisibly for weeks — every static gate
was green while the app was behaviourally broken (#985). FLOOR-2 (#1067)
+ FLOOR-3 (#1068) exist to kill this class. The reference implementation
is the converged intake write-back: `_api_call(required=True)` →
`WriteError` + write-health signal; `validate_finalize_payload`
schema-gate pre-POST; the TS-side `slotData.transcriptIntegrity` marker
(#1079) is the cross-language parity pattern.

## How to apply

- Before changing a swallow-site, **inventory** the load-bearing call-sites
  and classify each load-bearing vs deliberately-best-effort *with stated
  rationale* (scope is defined against the inventory, not hand-waved).
- Convert load-bearing swallows to surface + health signal.
- Gate structured agent output through a schema validator (stdlib is fine
  and preferred when the schema lib is container-only and the test must be
  CI-runnable — a gate whose own test can't run in CI is itself a defect).
- Ship a falsifiable, CI-runnable, non-credential-gated test proving both
  directions: seeded failure surfaces; happy path unaffected; malformed
  output rejected with **no partial persist**.

Cautionary tale: WP1/WP2 EPIC #1065 — FLOOR-1 surfaced that the intake
create-path swallowed persist failures into an ignorable `{"error"}` dict
the agent never checked, so "finalized" was reported while the structured
outcome was silently lost.
