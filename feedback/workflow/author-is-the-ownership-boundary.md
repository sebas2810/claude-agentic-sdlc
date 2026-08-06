---
title: Squad ownership lives in the issue author — put it in every discovery query
status: active
scope: all-seats
added: 2026-08-03
last-confirmed: 2026-08-03
---

## Rule
A repo can host more than one squad. The only signal that reliably encodes which
squad an issue belongs to is its **author** (`author.login`): labels, assignees,
and titles are shared namespace and carry no ownership. Every discovery query
loads `author` and drops foreign-authored rows **before** evaluating anything
else. Never scope, build, verify, gate, or merge a foreign-authored item.

## Why
- The prescribed ownership check ("look at assignees, labels, title") ran,
  passed, and the boundary was crossed anyway — those signals don't carry the fact.
- Foreign `seat:*` labels sit in the same namespace and pre-load the same trap
  for any label-only filter.
- QA/SM discovery (`label:status:delivered` / `label:status:tested`) is
  otherwise repo-global — it happily pulls another squad's gates.

## How to apply
- `SQUAD_AUTHORS` = the account(s) that author this squad's work (seats share
  one GitHub account by design; the human owner may author too). Resolve it in
  the same block as `SEAT_ROLE` (see `commands/check.md`).
- **Provision it explicitly — `sdlc.config` → `bootstrap.sh` → each `.env.local`.**
  It is a comma-separated list, not a single login.
- **The old default — "the repo owner" — was wrong and is retired.** Seats
  routinely authenticate as an account that is *not* the repo owner; an
  owner-only value then makes every seat drop **its own squad's** work. Where
  unset, the fallback is now the owner **unioned with the logged-in `gh`
  account**, and it announces what it inferred.
- **A too-narrow `SQUAD_AUTHORS` is a silent-degradation defect, not a
  misconfiguration.** It raises no error; it returns a *shorter queue*, which is
  indistinguishable from "nothing to do". A seat then reports `queue clear —
  idle` while its work sits unpulled. That is the exact shape the no-false-green
  invariant forbids, which is why the resolution must be loud and the value
  explicit. **Observed 2026-08-06:** with the owner-only default, a PM seat's
  blocked queue returned **1 of 3** items — the two dropped were its own squad's,
  authored by the seat account.
- Add `author` to the `--json` list of every `gh issue list` discovery call and
  filter first; a single-account squad pushes it server-side
  (`author:$SQUAD_AUTHORS` in the `--search` string) so the foreign row never returns.
- `onboarding/doctor.sh` flags `seat:*` labels that map to no configured seat —
  a foreign lane surfaces loudly instead of masquerading as a queue.

## Cautionary tale
2026-08-03: during a backlog sweep a PM scoped another squad's issue — five
labels, a priority, a seat routing, and a board item — with the guard rule in
place and followed. The issue had no assignee and no ownership label; its only
ownership signal was `author`, which nothing loaded.
