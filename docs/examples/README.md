# Examples

Scenario-based, copy-pasteable recipes for common eco-commander tasks.
All examples are verified against the actual source in `src/bin/eco`,
`src/recipes/`, and `src/scheduler/cli.py`.

## Documents in this directory

| File | What it covers |
|------|----------------|
| [cookbook.md](./cookbook.md) | 10 end-to-end how-to scenarios covering the full CLI surface |

## When to use the cookbook vs. other docs

| You want to… | Go to |
|---|---|
| Do something specific right now | **cookbook.md** (this directory) |
| Understand how a subsystem works | [docs/subsystems/](../subsystems/README.md) |
| Look up every flag for a command | [docs/getting-started/usage.md](../getting-started/usage.md) |
| Recover from a broken state | [docs/operations/runbook.md](../operations/runbook.md) |
| Add a new recipe | cookbook.md § Scenario 6, then [recipes.md](../subsystems/recipes.md) |

## Scenario index

| # | Scenario | Key commands |
|---|----------|-------------|
| 1 | Run a one-shot research query | `eco do research "<topic>"` |
| 2 | Queue a scheduler job from YAML | `eco scheduler add --file jobs.yaml` |
| 3 | Debug a stale usage meter | `eco status` · `eco doctor` · manual poller run |
| 4 | Rotate CLI accounts safely | `eco account-swap list` · `eco account-swap gemini <slug>` |
| 5 | Capture and share a usage snapshot | `eco do snapshot` · `eco dashboard` |
| 6 | Add a new recipe to the catalog | recipe contract + header requirements |
| 7 | Inspect widget output via `--cli` | `eco status` · `jq` on `usage.json` |
| 8 | Seed the scheduler from a missions directory | `eco scheduler seed --dir <path>` |
| 9 | Cancel a queued job and drain the rest | `eco scheduler cancel <id>` · `eco scheduler drain` |
| 10 | Monitor system health with the hygiene watcher | `eco hygiene snapshot` · `eco hygiene watch` |

## Prerequisites

Run `eco doctor` before attempting any scenario. It reports:
- Optional LaunchAgent status (`com.eco-commander.usage-poller`,
  `com.eco-commander.scheduler`, `com.eco-commander.swiftbar`)
- `eco` CLI on PATH
- Python imports OK (`poller`, `scheduler.dispatcher`)
- Optional `usage.json` freshness
- Queue directory status

If `eco doctor` reports required-check errors, follow the
[Operational Runbook](../operations/runbook.md) before proceeding.

## Related documentation

- [docs/getting-started/usage.md](../getting-started/usage.md) — complete CLI reference
- [docs/subsystems/recipes.md](../subsystems/recipes.md) — recipe authoring guide
- [docs/subsystems/scheduler.md](../subsystems/scheduler.md) — scheduler architecture and job schema
- [docs/operations/runbook.md](../operations/runbook.md) — operational recovery procedures
