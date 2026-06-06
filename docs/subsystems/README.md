# Subsystems

Deep-dive documentation for each of eco-commander's major subsystems. Start
with [`../architecture.md`](../architecture.md) for the system-wide view,
then pick the subsystem you need below.

## Subsystem catalog

| Doc | Subsystem | Primary source |
|-----|-----------|---------------|
| [scheduler.md](./scheduler.md) | **Job Scheduler** — quota-aware multi-provider AI job dispatcher. Fires jobs via launchd every 120s. | `src/scheduler/` |
| [usage-monitor.md](./usage-monitor.md) | **Usage Monitor** — live plan-quota mirror for Claude, Gemini, and Codex in the macOS menu bar. | `src/poller/` + `src/bin/eco-commander.15s.sh` |
| [alerts.md](./alerts.md) | **Alert System** — evidence-backed finding triage, live verification, and fix routing. | `src/bin/eco-alerts.sh` |
| [widget-health.md](./widget-health.md) | **Widget Health Playbook** — health contract, icon logic, fix tiers, and 24/7 manager design. | `src/bin/eco-commander.15s.sh` |
| [recipes.md](./recipes.md) | **Recipes** — standalone bash workflow scripts for Q&A, research, snapshots, account swaps, and more. | `src/recipes/*.sh` |
| [snapshots.md](./snapshots.md) | **Snapshots** — immutable ecosystem state captures: prompt-layer Gemini scan → assembled `state.json`. | `src/recipes/snapshot.sh` |
| [launchd-best-practices.md](./launchd-best-practices.md) | **LaunchAgent Best Practices** — how supported LaunchAgent templates are configured for energy efficiency and survivability. | `scripts/launchagents/*.plist` |
| [usage-monitor-integration.md](./usage-monitor-integration.md) | *(Historical)* Original integration plan written before implementation. | — |

## Subsystem dependency map

```text
Recipes ──► Snapshots ──► state.json ──► Alert System ──► Widget
                                                              │
Usage Poller ──► usage.json ──────────────────────────────► Widget
                    │
            notify.json (meter state)
                    │
                    ▼
              Scheduler ──► Adapters ──► claude / codex / gemini / ollama CLIs
```

Key data flows:
- `src/poller/main.py` writes `~/.eco/current/usage.json` and `~/.eco/state/notify.json`
- `src/recipes/snapshot.sh` writes `~/.eco/current/state.json`
- `src/bin/eco-commander.15s.sh` (SwiftBar widget) reads both JSON files at render time
- `src/bin/eco-alerts.sh` reads `state.json` and runs live verifiers
- `src/scheduler/dispatcher.py` reads `notify.json` to check meter availability

## Reading order

Pick the path that matches your task:

**Setting up or debugging the widget:**
1. [`usage-monitor.md`](./usage-monitor.md) — install, how it works, calibration
2. [`widget-health.md`](./widget-health.md) — health contract, icon logic
3. [`alerts.md`](./alerts.md) — alert classification and fix tiers
4. [`launchd-best-practices.md`](./launchd-best-practices.md) — LaunchAgent config

**Working on job dispatch:**
1. [`scheduler.md`](./scheduler.md) — CLI, job YAML schema, adapters, meter system
2. [`../reference/data-model.md`](../reference/data-model.md) — `jobs.yaml` and `notify.json` schemas
3. [`launchd-best-practices.md`](./launchd-best-practices.md) — scheduler plist details

**Adding a recipe:**
1. [`recipes.md`](./recipes.md) — recipe contract and catalog
2. [`snapshots.md`](./snapshots.md) — `snapshot.sh` internals if needed
3. [`../reference/environment-variables.md`](../reference/environment-variables.md)

**Ecosystem audit / snapshot work:**
1. [`snapshots.md`](./snapshots.md) — layout, `state.json` schema, classifier
2. [`alerts.md`](./alerts.md) — how findings flow from snapshot to widget
3. [`widget-health.md`](./widget-health.md) — snapshot age thresholds

**Understanding the poller internals:**
1. [`usage-monitor.md`](./usage-monitor.md) — per-tool sources, calibration
2. [`usage-monitor-integration.md`](./usage-monitor-integration.md) — historical design decisions
3. [`../adr/0004-usage-monitor-python-carveout.md`](../adr/0004-usage-monitor-python-carveout.md)
