# Reference

Technical reference for eco-commander — schemas, configuration, environment
variables, and terminology. Use these documents when you need precise, authoritative
answers about what the system reads, writes, or expects.

## Documents in this cluster

| Doc | What it answers |
|-----|----------------|
| [environment-variables.md](./environment-variables.md) | What is every `ECO_*` variable, what is its default, and which component reads it? |
| [data-model.md](./data-model.md) | What are the exact JSON/YAML schemas for `usage.json`, `notify.json`, `state.json`, and `jobs.yaml`? |
| [configuration.md](./configuration.md) | Where do config files live, what do the LaunchAgent plists do, and how do I calibrate caps? |
| [glossary.md](./glossary.md) | What does a domain term mean — adapter, ladder, meter, rung, tick, pace, server truth, verdict? |

## Reading order

For a first read, follow this sequence:

1. **[environment-variables.md](./environment-variables.md)** — understand the control surface before
   diving into schemas. Every behavior can be adjusted without touching code.

2. **[data-model.md](./data-model.md)** — learn what the poller writes and what the scheduler and
   widget consume. The `usage.json` and `notify.json` schemas are the system's internal contracts.

3. **[configuration.md](./configuration.md)** — understand how LaunchAgents are installed, how
   `~/.eco/config.json` enables OAuth mode, and how token caps are calibrated.

4. **[glossary.md](./glossary.md)** — look up unfamiliar terms as you encounter them in docs or source.

## When to use each document

- **Building an adapter?** Read `data-model.md` (job schema, meter keys) then
  `glossary.md` (adapter, rung, ladder, hard wall).
- **Adding a recipe?** Read `environment-variables.md` (ECO_GEM_SMART_BIN, ECO_DRY_RUN)
  and `configuration.md` (recipe contract).
- **Debugging a missed notification?** Read `data-model.md` (notify.json schema, meter kind fields)
  and `environment-variables.md` (ECO_NOTIFY_LOG_ONLY, ECO_NOTIFICATIONS).
- **Calibrating quota caps?** Read `configuration.md` (caps.py constants and calibration log).
- **Enabling OAuth / server-truth?** Read `configuration.md` (config.json) and
  `environment-variables.md` (ECO_ALLOW_LIVE_CREDENTIAL_PROBE).

## Subsystem consumers

Documents in this cluster are consumed by the following subsystem docs under
[`../subsystems/`](../subsystems/):

| Subsystem doc | Uses |
|--------------|------|
| [alerts.md](../subsystems/alerts.md) | notify.json meter state, ECO_ALERT_* variables |
| [scheduler.md](../subsystems/scheduler.md) | jobs.yaml schema, adapter binary variables, ECO_DRY_RUN |
| [usage-monitor.md](../subsystems/usage-monitor.md) | usage.json schema, server_truth config, ECO_COMMENTS |
| [widget-health.md](../subsystems/widget-health.md) | Fix tier glossary term, ECO_HOME, ECO_COMMANDER_REPO |
| [snapshots.md](../subsystems/snapshots.md) | state.json schema, snapshot directory layout |

## Architecture context

For the system-level view — how these components connect — see
[`../architecture.md`](../architecture.md).
