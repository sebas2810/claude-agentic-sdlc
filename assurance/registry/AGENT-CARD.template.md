# Agent Card — <Name> (<role> seat)

- **Loop / line:** Build | Run | Assure · line 1 | 2 | 3
- **Trust tier (ops seats):** A observe | B investigate | C act — n/a for delivery seats
- **Sponsor (accountable human):** <name>
- **Model tier:** <opus | sonnet | haiku> (as configured in `sdlc.config` / `.env.local`)
- **KICKOFF:** <path> · version/commit: <sha>
- **Boot mode:** operator-driven `/check` | operator-driven `/ops-check` | scheduled bounded headless (cadence: <…>, budgets: <max tokens/run · max runs/hr>)

## Identity & credentials (effective, not intended)

| Credential | Scope | Lifetime | Where held |
|---|---|---|---|
| <e.g. GitHub token / App> | <repos + permissions> | <standing / short-lived> | <.env.local · env protection · …> |
| <e.g. AWS profile> | <IAM policy summary> | | |

## Tools & MCP servers reachable

| Tool / server | Pinned version | Auth | Vetted (date) |
|---|---|---|---|

## Authority boundaries

- **May:** <the seat's granted actions, incl. any Tier-0 runbooks by id>
- **May never:** <the KICKOFF's refusals, verbatim where load-bearing>

## History

| Date | Change (scope / tool / autonomy / model) | PR |
|---|---|---|
| <YYYY-MM-DD> | Card created | #<n> |
