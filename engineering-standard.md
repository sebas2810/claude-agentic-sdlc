# Engineering Standard — the production-ready floor

> **The floor.** Every change ships production-ready. This is the generic, portable bar; an instance defines the concrete *tiered* standard + per-area "done means" on top of it (e.g., the reference instance: its ADR-0006 Tier-1/Tier-2 model, in `instance/orbis/engineering-standard.md`).

## Non-negotiable — production-ready only

Rejected, without exception:

- **Stubs / placeholders** — code that exists but doesn't do the thing its name suggests.
- **Non-working workflows** — scripts or infra that build / synth but don't deploy, or don't fire on a real event.
- **Half-logic / TODOs** on a code path that reaches production.
- **Mocked boundaries as proof** — every change is proven by a **live deployed-env round-trip**, never by green CI alone.
- **Producer-as-sole-adjudicator** — the author of a thing is never the only one to score whether it works; falsifiable evidence (a bundled eval, smoke output, a real state row) MUST exist.
- **Hand-seeded state rows** — a row in a system-of-record table comes from a real event, not a seed script.
- **Eval-on-fixtures** — evals run against the real boundary, not a synthetic mock of it.
- **Log-only-pretending-enforced guardrails** — a guardrail logs OR blocks, not "logs and we hope someone notices".
- **Silent-catch** — `catch {}` / `except: pass` on a load-bearing path; errors surface or fail the deploy.
- **False-green acceptance** — a test that passes by not exercising the thing it claims to test.
- **Leftover TODOs at merge** — every TODO cites a follow-up issue inline (`TODO(#NNNN)`) or a date.
- **Silent issue drops** — a review issue closes with a recorded adopt / skip / defer rationale, never without a comment.

## Forbidden anti-patterns (grep-able)

The same bar in a form a reviewer can grep for and a producer can self-check against:

1. `// TODO` / `# TODO` on a load-bearing path.
2. `try { } catch { /* ignore */ }` / `except: pass` on a load-bearing path.
3. Seed scripts that populate a system-of-record table from a fixture.
4. Tests that mock the exact boundary the change claims to fix.
5. Multiple sources of truth for a value that should be one canonical file (lexicons, model IDs, ARNs, secrets).
6. Log-only guardrails — a warning log without a `raise` / `reject` in the same path.
7. Closing a review issue without a comment recording the decision.

## How an instance extends this

This bar is the portable floor. An instance adds, in its overlay:

- its **concrete tiered standard** — which violations are hard-fail vs fixable-in-PR;
- its **per-area "done means"** — what "done" is for each subsystem, with falsifiable evidence;
- its **hygiene contract** — PR conventions, status-flip discipline, the citation format.

Yours goes at `instance/<you>/engineering-standard.md`; the reference instance's lives at `instance/orbis/engineering-standard.md`, under its ADR-0006 tiered model.
