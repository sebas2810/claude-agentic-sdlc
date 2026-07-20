---
title: Prioritization — WSJF ordering of the Ready backlog
status: active
scope: all-seats
---

# Prioritization

> **Order the backlog by WSJF, not gut feel.** The runner pulls the
> **highest-WSJF Ready item** next — sequencing is a computed property of the
> board, not a per-tick negotiation.

Once an item passes the [Definition of Ready](definition-of-ready-done.md) it
enters the Ready queue. **Weighted Shortest Job First (WSJF)** decides which Ready
item a producer pulls next (`Scoped → In Progress`, claimed via `/check`). Ordering is
recomputed from board fields, so it is legible to human and machine alike — the
same property the [state machine](state-machine.md) gets from statelessness.

## WSJF = Cost of Delay ÷ Job Size

Maximise value delivered per unit of time by doing the **shortest, most-costly-to-delay** job first.

```
WSJF = Cost of Delay / Job Size
Cost of Delay = User/Business value + Time criticality + Risk-reduction / Opportunity-enablement
```

| Term | Asks | Higher when |
|---|---|---|
| **User/Business value** | What is the value of delivering this at all? | bigger outcome, more users, more revenue/cost saved |
| **Time criticality** | Does the value decay if we wait? Is there a deadline or window? | a fixed date, a closing window, a degrading user |
| **Risk-reduction / Opportunity-enablement** | Does it cut future risk or unblock later work? | de-risks a fragile path, enables several downstream items |
| **Job Size** | How big is the job? (relative, not hours) | larger relative size — the divisor that favours small jobs |

Score each term on a relative scale (e.g. modified-Fibonacci 1·2·3·5·8). The
ratio — not raw value — drives the order.

### Worked example (the ranking flips vs raw value)

| Item | Value | Time crit. | Risk/Opp. | CoD (sum) | Size | **WSJF** | Rank |
|---|---|---|---|---|---|---|---|
| A — big platform refactor | 8 | 2 | 5 | 15 | 13 | **1.2** | 3 |
| B — expiring-window integration | 5 | 8 | 3 | 16 | 5 | **3.2** | 1 |
| C — small high-leverage fix | 3 | 3 | 8 | 14 | 3 | **4.7** | 2 |

By **raw value** the order is A > B > C. By **WSJF** it is **C > B > A**: A's high
value is swamped by its size, while C's small size and B's closing window pull
them ahead. WSJF buys down Cost of Delay faster.

## Mapping to the board

Two fields on the GitHub Project drive ordering within a state:

| Field | Type | Use |
|---|---|---|
| **WSJF** | number | the computed score; **sort Ready desc** to pick the next pull |
| **Priority** | single-select `P0`–`P3` | class override; `P0` is the **interrupt class** |

- **`P0` preempts WSJF.** P0 is incidents / hotfixes — it interrupts the normal
  flow and is pulled before any WSJF ordering. (The runner finishes-before-starting
  for ordinary work; a P0 is the sanctioned exception.)
- **Otherwise sort Ready by `WSJF` desc.** `P1`–`P3` are ordinary; ties broken by
  WSJF, then `Area` for locality.

## RICE — the alternative, and when to use which

`RICE = (Reach · Impact · Confidence) / Effort`. It adds a **Confidence** factor
and frames value as Reach × Impact — built for *discovery*, where the bet's payoff
and likelihood are themselves uncertain.

| Use | When |
|---|---|
| **WSJF** | flow / delivery — Cost-of-Delay-sensitive sequencing of Ready work; deadlines and windows matter. |
| **RICE** | product discovery — comparing uncertain bets where confidence and reach dominate. |

Pick one scheme per board and keep it consistent; mixing the two on one queue
makes the ordering unreadable.

## Estimation is sizing, not hours

`Job Size` (and RICE's `Effort`) is a **relative** estimate, not a clock estimate
— relative sizing is faster, more stable, and avoids false precision. It ties
directly to the [DoR](definition-of-ready-done.md) **"sized"** check: an item that
won't fit one branch / one PR is too large to size honestly and must be split
before it is Ready.

## See also

- [`state-machine.md`](state-machine.md) — the runner that pulls the top-WSJF Ready item.
- [`definition-of-ready-done.md`](definition-of-ready-done.md) — the Ready gate; the "sized" check.
- [`flow-metrics.md`](flow-metrics.md) — throughput / cycle-time the ordering optimises.
- [`hierarchy.md`](hierarchy.md) — Initiative → Epic → Story → Task; what gets scored.
