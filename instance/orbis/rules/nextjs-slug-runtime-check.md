---
title: Next.js slug conflict only fires at server start, not next build
status: active
scope: engineer
added: 2026-05-13
last-confirmed: 2026-05-13
---

> Stands under the ORBIS Agentic SDLC spine ([`../../../agentic-operating-model.md`](../../../agentic-operating-model.md)).

## Rule

When adding any new `app/api/.../[slug]/**/route.ts` directory, **use the same slug name as the sibling directory at the same parent path**. Next.js 16 refuses to start the production server when two dynamic segments at the same parent path have different slug names.

## The failure mode

```
apps/internal/src/app/api/workspace/
├── [threadId]/route.ts                                    ← existing
└── [sessionId]/intake-citations/route.ts                  ← NEW route added
```

`next build` passes. Local dev with `next dev` passes. Production server (`node .next/standalone/server.js`) **crashes on startup** with:

```
⨯ Error: You cannot use different slug names for the same dynamic path 
  ('sessionId' !== 'threadId').
```

ECS health check fails → circuit breaker triggered → auto-rollback.

## How to apply

When adding a new `[slug]/...` directory:

1. Check the sibling directories at the same parent:
   ```bash
   ls apps/internal/src/app/api/workspace/   # what siblings exist?
   ```
2. If a sibling already uses a `[slug]` name, **reuse that exact name**:
   ```
   apps/internal/src/app/api/workspace/[threadId]/intake-citations/route.ts  ✅
   ```
3. If you semantically need a different name, **rename the variable inside the route handler** instead of the URL slug:
   ```typescript
   export async function POST(
     request: NextRequest,
     { params }: { params: Promise<{ threadId: string }> },
   ) {
     const { threadId: sessionId } = await params;  // use as sessionId internally
     // ...
   }
   ```

## Verify before merge

Run the production server locally before opening the PR:

```bash
# In apps/internal:
npm run build
node .next/standalone/server.js
# In another shell:
curl http://localhost:3000/api/health
# Expect: 200 with body containing "healthy"
```

If the server doesn't bind port 3000 or `/api/health` returns 500 — you've hit a runtime check that build missed. **Don't push without diagnosing.**

## Cautionary tale

**#820 (2026-05-13).** PR #807 added `/api/workspace/[sessionId]/intake-citations/route.ts` as a sibling to the existing `/api/workspace/[threadId]/route.ts`. `next build` accepted it; production deploy `server.js` crashed on startup; ECS ran the deploy-rollout for 8 minutes failing health checks; circuit breaker auto-rolled-back to v1.1.0.

Fix in PR #821 was a simple rename of the directory + internal variable destructuring. ~10 minutes to write, ~60 minutes lost to diagnostic + redeploy.

## Why local `next build` doesn't catch it

The slug-conflict check fires when Next.js's runtime router initialises at server boot, NOT when the build emits the route manifest. `next build` just compiles routes; it doesn't load the router.

## Future gate

Track in a chore issue: add `node .next/standalone/server.js` + a smoke curl to PR CI. Catches this class of bug + the auth.ts edge-runtime constraint ([related rule](auth-ts-edge-runtime-constraint.md)).
