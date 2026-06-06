# Architecture

> **Purpose:** A system-level map of eco-commander: source layout, runtime
> layout, data flow, LaunchAgents, integrations, and boundaries. Start here,
> then drill into [`subsystems/`](./subsystems/).

## 1. Overview

`eco-commander` is a local macOS operator layer for an AI toolchain. It
orchestrates command-line tools, watches local quota state, renders a SwiftBar
menu, and dispatches queued jobs. It does **not** host models, run MCP servers,
or expose a network API.

The runtime is easiest to understand as six cooperating parts:

1. **Entry points** in `src/bin/` — CLI router, SwiftBar widget, alerts.
2. **Recipes** in `src/recipes/` — standalone workflow scripts.
3. **Snapshots** under `$ECO_HOME/snapshots/` — point-in-time audit artifacts.
4. **Usage poller** in `src/poller/` — live quota collection and meter state.
5. **Scheduler** in `src/scheduler/` — quota-aware deferred job dispatch.
6. **Runtime state** under `$ECO_HOME` — installed symlinks, JSON, YAML, logs.

```text
┌──────────────────────────── User ─────────────────────────────┐
│                                                               │
│  Terminal                         SwiftBar menu bar            │
│     │                                  │                       │
│     ▼                                  ▼                       │
│  $ECO_HOME/bin/eco              eco-commander.15s.sh           │
│     │                                  │                       │
│     ├──────────────┬───────────────────┤                       │
│     ▼              ▼                   ▼                       │
│  recipes       scheduler CLI       eco-alerts.sh               │
│     │              │                   │                       │
└─────┼──────────────┼───────────────────┼───────────────────────┘
      │              │                   │
      ▼              ▼                   ▼
 $ECO_HOME/      $ECO_HOME/queue/    snapshot candidates
 snapshots/      jobs.yaml          plus live checks
 current/
 usage*.json
      ▲
      │
 src/poller/ via launchd ──► $ECO_HOME/state/notify.json
      │
      ▼
 Claude Code · Gemini CLI · Codex CLI · Ollama · Docker and local tools
```

## 2. Source Layout

| Path | Role |
|------|------|
| [`src/bin/`](../src/bin/) | Bash entry points: `eco`, SwiftBar plugin, alerts |
| [`src/recipes/`](../src/recipes/) | Workflow catalog invoked by `eco do NAME` |
| [`src/poller/`](../src/poller/) | Python usage monitor and meter-state writer |
| [`src/scheduler/`](../src/scheduler/) | Python queue, routing, dispatcher, provider adapters |
| [`src/common/`](../src/common/) | Shared `ECO_HOME` path resolution |
| [`src/tools/`](../src/tools/) | Repository maintenance tools |
| [`scripts/`](../scripts/) | Installers, LaunchAgent templates, health checks, release helpers |

`scripts/install.sh` creates real `$ECO_HOME/bin/` and `$ECO_HOME/recipes/`
directories, then symlinks individual `src/bin/*` and `src/recipes/*.sh` files
into them. The installed commands therefore run the source files directly.

## 3. Runtime Layout

`ECO_HOME` defaults to `~/.eco`.

```text
$ECO_HOME/
├── bin/                  # real dir; file symlinks to src/bin/*
├── recipes/              # real dir; file symlinks to src/recipes/*.sh
├── current -> snapshots/<latest>/
├── snapshots/
│   └── <timestamp>/
│       ├── layers/
│       ├── state.json
│       ├── map.md
│       └── dashboard.html
├── state/
│   ├── notify.json
│   └── active-accounts.json
├── queue/
│   ├── jobs.yaml
│   └── logs/
├── logs/
└── auth-snapshots/
```

`current` is published by the snapshot recipe as a symlink to the latest
snapshot directory. The poller writes live `usage-claude.json`,
`usage-gemini.json`, `usage-codex.json`, and `usage.json` through that path.
Treat the snapshot audit files as point-in-time evidence and the usage files
as live runtime overlay data.

## 4. Entry Points

### 4.1 CLI router: `src/bin/eco`

`eco` is a Bash dispatcher. It owns routing, not business logic.

| Command | Behavior |
|---------|----------|
| `eco` / `eco list` | List installed recipes from their metadata headers |
| `eco do NAME [args]` | Run `$ECO_HOME/recipes/NAME.sh` |
| `eco NAME [args]` | Shortcut when `NAME` matches an installed recipe |
| `eco status` | Run the SwiftBar plugin in CLI mode |
| `eco dashboard` | Open `$ECO_HOME/current/dashboard.html` |
| `eco map` | Open `$ECO_HOME/current/map.md` |
| `eco audit` | Open `ECO_AUDIT_DIR` or `$ECO_HOME/ecosystem-audit` |
| `eco scheduler SUB` / `eco sched SUB` | Run `python -m scheduler.cli SUB` |
| `eco hygiene SUB` / `eco hyg SUB` | Run the hygiene recipe |
| `eco account-swap SUB` / `eco account SUB` / `eco swap SUB` | Run account rotation |
| `eco doctor` | Check agents, symlinks, imports, usage freshness, and queue access |

### 4.2 SwiftBar widget: `src/bin/eco-commander.15s.sh`

The SwiftBar plugin is a read-heavy display surface. It reads:

- `$ECO_HOME/current/state.json`
- `$ECO_HOME/current/usage.json`
- `$ECO_HOME/state/active-accounts.json`
- the active AI profile file when present
- live probes such as `ollama`, local HTTP health checks, RAM, and processes
- normalized alert output from `eco-alerts.sh`

With `--cli`, the same script prints terminal-friendly status for `eco status`.

### 4.3 Alerts: `src/bin/eco-alerts.sh`

`eco-alerts.sh` verifies and normalizes snapshot-derived issue candidates. It
also exposes diagnostic and action subcommands used by the widget, including
doctor-style checks, logged command execution, recipe dispatch, and targeted
debug helpers.

## 5. Recipes

Recipes are standalone Bash workflows in `src/recipes/`.

Current catalog:

| Recipe | Purpose |
|--------|---------|
| `account-swap` | Register and rotate Claude, Gemini, or Codex credential snapshots |
| `arabic-proof` | Proofread Arabic text locally with Ollama |
| `ask` | One-shot Q&A, routing private prompts to local Ollama |
| `dashboard` | Open the current dashboard |
| `dashboard-refresh` | Rewrite dashboard metric placeholders from live state |
| `hygiene` | RAM/swap/MCP/process hygiene watcher |
| `n8n-start` | Start local n8n through Docker or `npx` |
| `note` | Capture a note through the configured memory router |
| `research` | Run a Gemini-backed research prompt |
| `scheduler-seed` | Import mission YAML files into the scheduler queue |
| `snapshot` | Build and publish a timestamped ecosystem snapshot |
| `swarm` | Dispatch parallel Gemini agents and synthesize results |

Each recipe should advertise its interface with `# DESC:`, `# INPUTS:`,
`# OUTPUT:`, and `# USES:` headers. `eco list` reads those headers at runtime.

See [Recipes](./subsystems/recipes.md).

## 6. Snapshots

The snapshot recipe creates `$ECO_HOME/snapshots/<timestamp>/`, runs prompt
layers from the selected prompt library, assembles `state.json`, `map.md`, and
`dashboard.html`, then publishes `$ECO_HOME/current` with a temporary symlink
and `mv`. It uses `gem-smart 3.5f` when available, falls back to plain `gemini`
when allowed, and ships a public example prompt library. The fixed seven layer
IDs are used only when a canonical prompt set is present.

Canonical layer IDs:

| Layer | Domain |
|-------|--------|
| `GA-hardware-llm` | Local hardware and LLMs |
| `GB-ai-clients` | AI client applications |
| `GC-mcp` | MCP server wiring |
| `GD-hooks-plugins` | Hooks and plugins |
| `GE-agents-memory` | Agents and memory |
| `GF-toolkit-projects-external` | Toolkit, projects, and external services |
| `GG-wiring-behavior` | Cross-system wiring and behavior |

The assembler is embedded in `snapshot.sh` and writes schema version `0.2`.
Candidate issues are regex-derived; `eco-alerts.sh` performs live verification
when the widget or operator asks for alert state.

See [Snapshots](./subsystems/snapshots.md).

## 7. Usage Poller

`src/poller/main.py` is a stdlib-only Python entry point. It is normally run
every 60 seconds by `com.eco-commander.usage-poller`.

| Module | Role | Primary output |
|--------|------|----------------|
| `claude.py` / `claude_oauth.py` | Claude JSONL or OAuth usage | `usage-claude.json` |
| `gemini.py` | Gemini quota from the CLI's quota API flow | `usage-gemini.json` |
| `codex.py` / `codex_oauth.py` | Codex JSONL or OAuth usage | `usage-codex.json` |
| `accounts.py` | Plan/account context stamping | fields inside each tool payload |
| `alternatives.py` | Local and alternative provider availability | `alternatives` block |
| `value.py` | Optional value/credit estimate from configured canonical data | `value` block |
| `comments.py` | Optional burn-rate comments when `ECO_COMMENTS=1` | `comment` block |
| `notify.py` | Meter classification and notification debounce state | `state/notify.json` |
| `main.py` | Per-tool writes, merge, safe error isolation | `usage.json` |

All JSON writes are atomic. Public error fields are sanitized; detailed
tracebacks go to private logs under `$ECO_HOME/logs/`.

See [Usage Monitor](./subsystems/usage-monitor.md) and
[ADR 0004](./adr/0004-usage-monitor-python-carveout.md).

## 8. Scheduler

`src/scheduler/` is a quota-aware job dispatcher. It uses Python plus PyYAML.
The dispatcher has run-once-then-exit semantics: one tick loads state, evaluates
ready jobs, optionally fires work, persists queue state, and exits.

| Module | Purpose |
|--------|---------|
| `cli.py` | `status`, `add`, `run-once`, `drain`, `tail`, `seed`, `cancel` |
| `dispatcher.py` | One-tick dispatch loop, stale-running recovery, job attempt persistence |
| `queue.py` | YAML queue schema, validation, POSIX locks, atomic writes |
| `routing.py` | Meter availability and model-preference ladder selection |
| `adapters/base.py` | Adapter protocol, result type, log redaction helpers |
| `adapters/claude.py` | Fires jobs through Claude Code |
| `adapters/codex.py` | Fires jobs through Codex CLI |
| `adapters/gemini.py` | Fires jobs through Gemini CLI |
| `adapters/ollama.py` | Fires jobs through local Ollama |

The scheduler reads `$ECO_HOME/state/notify.json`, not provider APIs. A meter
at `hard_wall` blocks until its reset epoch. A meter at `throttle` gets a
short cooldown. Unknown meters are treated optimistically so new queues do not
deadlock on missing state.

See [Scheduler](./subsystems/scheduler.md) and
[ADR 0005](./adr/0005-job-scheduler.md).

## 9. Data Flow

```text
Install:
  scripts/install.sh
    -> real $ECO_HOME/bin/ with per-file symlinks
    -> real $ECO_HOME/recipes/ with per-file symlinks
    -> SwiftBar plugin symlink

Snapshot:
  eco do snapshot
    -> $ECO_HOME/snapshots/<timestamp>/
    -> $ECO_HOME/current symlink

Usage:
  launchd -> src/poller/main.py
    -> $ECO_HOME/current/usage-claude.json
    -> $ECO_HOME/current/usage-gemini.json
    -> $ECO_HOME/current/usage-codex.json
    -> $ECO_HOME/current/usage.json
    -> $ECO_HOME/state/notify.json

Scheduler:
  launchd or eco scheduler run-once
    -> read $ECO_HOME/state/notify.json
    -> read/write $ECO_HOME/queue/jobs.yaml
    -> write $ECO_HOME/queue/logs/

Display:
  SwiftBar -> read current state and usage
  eco status -> run widget in CLI mode
  eco-alerts.sh -> verify snapshot candidates with live checks
```

## 10. LaunchAgents

LaunchAgent templates live under [`scripts/launchagents/`](../scripts/launchagents/)
and are rendered by [`scripts/install-launchagents.sh`](../scripts/install-launchagents.sh).

| Agent | Label | Cadence | Install behavior |
|-------|-------|---------|------------------|
| Usage poller | `com.eco-commander.usage-poller` | Load + 60s | Installed and loaded |
| Scheduler | `com.eco-commander.scheduler` | Load + 120s | Opt-in through scheduler env vars |
| SwiftBar autostart | `com.eco-commander.swiftbar` | Login | Installed only when SwiftBar exists |

Set `ECO_SCHEDULER_PERSIST=1` to render the scheduler plist without loading it,
or `ECO_SCHEDULER_AUTO_LOAD=1` to render and load it.

The poller and scheduler plists set `ProcessType: Background`, `Nice: 5`, and
low-priority I/O flags. Scheduler ticks are serialized with a queue-adjacent
lock, so overlapping launchd invocations cannot claim the same job.

See [Launchd Best Practices](./subsystems/launchd-best-practices.md).

## 11. External Integrations

| Integration | How eco-commander uses it |
|-------------|---------------------------|
| Claude Code | Recipes/scheduler can invoke `claude`; poller reads JSONL or OAuth usage |
| Gemini CLI | Recipes/scheduler invoke `gemini` or wrapper; poller reads quota state |
| Codex CLI | Scheduler invokes `codex exec`; poller reads JSONL or OAuth usage |
| Ollama | Widget probes local server state; recipes and scheduler can run local models |
| Docker | Widget and recipes use Docker checks for local services such as n8n |
| n8n | Optional local automation target started by `n8n-start` |
| MCP configuration | Snapshot has an MCP layer; eco does not run MCP servers itself |

## 12. Security Boundaries

- All commands run as the invoking macOS user. There is no setuid helper and
  no eco-commander network listener.
- Runtime files are local under `$ECO_HOME`; queue and log writers use private
  modes where the code creates sensitive files.
- The scheduler validates job IDs, timeouts, work directories, and log paths
  before launching provider CLIs.
- Provider adapter logs are written under `$ECO_HOME/queue/logs/` and obvious
  bearer tokens/API keys are redacted before persistence.
- Poller public JSON contains sanitized error classes. Detailed tracebacks are
  restricted to private logs.
- Recipes that touch credentials or external services must make side effects
  explicit in their headers and docs.

See [Security Model](./operations/security-model.md).

## 13. Non-goals

- Cross-platform support.
- Hosting, proxying, or serving models.
- Running MCP servers.
- Exposing an HTTP/RPC API.
- Replacing provider CLIs or their authentication systems.

## See Also

- [Mental Model](./concepts/mental-model.md) — conceptual explanation of the runtime model
- [Data Model](./reference/data-model.md) — schemas for JSON/YAML files
- [CLI Reference](./api/cli-reference.md) — command surface
- [Subsystems](./subsystems/README.md) — deep dives by component
- [Architecture Diagram](./diagrams/architecture.md) — Mermaid topology
- [Security Model](./operations/security-model.md) — expanded trust boundaries
