---
title: auth.ts top-level imports MUST be edge-runtime compatible
status: active
scope: engineer
added: 2026-05-09
last-confirmed: 2026-05-13
---

> Stands under the ORBIS Agentic SDLC spine ([`../../../agentic-operating-model.md`](../../../agentic-operating-model.md)).

## Rule

`apps/internal/src/auth.ts` is imported by `middleware.ts`, which runs on the **edge runtime**. Top-level imports in `auth.ts` must be edge-runtime compatible — no `node:*` modules, no Prisma client, no AWS SDK clients at module level.

## Why

`middleware.ts` runs on every request, on Vercel's / Next.js's edge runtime (V8 isolate, no Node.js stdlib). When the edge bundle is compiled, it pulls in `auth.ts`'s entire top-level import graph. If anything in there isn't edge-compatible:

- Build passes (TypeScript doesn't check runtime compat)
- Local `next start` passes (it falls back to Node)
- Production deploy fails on first edge-runtime invocation — middleware throws → all requests 500

## How to apply

In `auth.ts`:

```typescript
// ❌ BAD — top-level import of Prisma
import { prisma } from '@/lib/db';

// ❌ BAD — top-level import of AWS SDK
import { S3Client } from '@aws-sdk/client-s3';

// ✅ GOOD — dynamic import inside the function body
async function lookupUser(id: string) {
  const { prisma } = await import('@/lib/db');
  return prisma.user.findUnique({ where: { id } });
}
```

Same rule for any module that's part of `middleware.ts`'s import graph.

## Detection

There's no pre-merge CI gate for this (TODO: add one). Detection today is:

- `next build` doesn't catch it
- `tsc` doesn't catch it
- Local `next start` *sometimes* catches it depending on which routes hit middleware
- **Production `node .next/standalone/server.js`** is when it fails

Until we have a gate, the only safe way to know is to `node .next/standalone/server.js` locally + hit a route that triggers middleware.

## Cautionary tale

**PR #743 → #746 hotfix.** Added `import { prisma } from '@/lib/db'` to `auth.ts`. tsc passed, build passed, CI passed. Deploy to STAGING rolled the new ECS container. Container start: edge-bundle eval failed on missing `node:async_hooks`. Health check failed for 8 min until rollback. ~30 min lost.

## Related rule

Same class of bug as the Next.js slug runtime check ([`nextjs-slug-runtime-check.md`](nextjs-slug-runtime-check.md)) — runtime check that doesn't fire during build. Pattern: any code path that's only exercised on `node server.js` startup, not on `next build`.

Future gate proposal: a PR CI step that runs `node .next/standalone/server.js` + curls `/api/health` for 30s. Catches both auth.ts edge-runtime breakage AND the Next.js slug conflict before merge.
