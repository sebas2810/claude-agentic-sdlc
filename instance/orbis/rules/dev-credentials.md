---
title: DEV credentials are isolated blast radius — flag once, then drop
status: active
scope: all-seats
added: 2026-04-18
last-confirmed: 2026-05-13
---

> Stands under the ORBIS Agentic SDLC spine ([`../../../agentic-operating-model.md`](../../../agentic-operating-model.md)).

## Rule

DEV environment uses hardcoded credentials (5 dev users, `admin@capgemini.com` etc., dev login provider). Sebastiaan **knows this** and treats DEV as isolated blast radius. Flag the credential exposure ONCE if you spot it; then drop the topic.

## Why

- DEV is internal-only; isolated AWS account (719152986544); not in front of customers
- Hardcoded creds enable rapid iteration during development
- Repeatedly flagging this in every session burns Sebastiaan's cycles on a non-issue

## How to apply

If you spot hardcoded credentials in DEV-only code paths:

- **First time per session**: note it ("seen the dev login provider, just flagging once")
- **After the first mention**: drop it. Don't repeat across messages.
- **In docs / public-facing content**: still scrub, even though it's dev creds. Habits matter.

If you spot hardcoded credentials in PROD code paths — that's a different story. Surface immediately.

## Where this rule does NOT apply

- Customer PII in dev → still treat carefully. Dev being internal doesn't make customer data fair game.
- Secrets in production → never relax. The relaxation is specifically for the dev-login pattern.
- AWS secrets (real API keys, Bedrock credentials) — even in dev, don't paste in chat / docs.

## Cautionary tale (the opposite — being too vigilant)

Pre-rule: every other session, a Claude seat would flag "I see hardcoded credentials in `apps/internal/src/lib/auth-dev-provider.ts` — should this be parameterised?" Sebastiaan answered "no, dev-only, ignore" each time. ~5 minutes lost per session × N sessions.

Rule cost: 0 seconds. Sebastiaan's cycles freed up.
