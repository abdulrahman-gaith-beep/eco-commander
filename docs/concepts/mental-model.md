# Mental Model: How to Think About eco-commander

> **Type:** Explanation — understanding-oriented.
> This page is not a tutorial or a reference. It answers the question:
> *"What kind of thing is this, and why is it built the way it is?"*

---

## The Core Idea

`eco-commander` is a local macOS operator console for AI command-line tools.
It does not host a model, proxy requests, or run an MCP server. It gives the
operator one place to inspect state, launch known workflows, and defer work to
the first provider whose quota is currently usable.

The important boundary is:

- **The AI tools do the AI work.** Claude Code, Gemini CLI, Codex CLI, and
  Ollama remain separate tools with their own auth, logs, and behavior.
- **eco-commander coordinates those tools.** It reads local state, writes local
  runtime files, invokes shell/Python workflows, and renders a CLI/menu-bar
  control surface.
- **macOS is part of the design.** SwiftBar, launchd, local credential stores,
  and filesystem state are first-class assumptions rather than portability
  details hidden behind an abstraction layer.

## The Map

```text
Repository source                         Runtime home
-----------------                         ------------
src/bin/eco              ──install────►   $ECO_HOME/bin/eco
src/bin/*.sh             ──symlinks───►   $ECO_HOME/bin/*.sh
src/recipes/*.sh         ──symlinks───►   $ECO_HOME/recipes/*.sh

src/poller/              ──launchd────►   $ECO_HOME/current/usage*.json
src/poller/notify.py     ─────────────►   $ECO_HOME/state/notify.json

src/recipes/snapshot.sh  ─────────────►   $ECO_HOME/snapshots/<timestamp>/
                                           $ECO_HOME/current -> latest snapshot

src/scheduler/           ──launchd────►   $ECO_HOME/queue/jobs.yaml
                                           $ECO_HOME/queue/logs/
```

`ECO_HOME` defaults to `~/.eco`. The source tree is the product; the runtime
home is the operator's local state directory. `make install` does not copy or
symlink the whole source tree; it creates per-file symlinks from
`$ECO_HOME/bin/` to `src/bin/*` and from `$ECO_HOME/recipes/` to
`src/recipes/*.sh`.

That split explains how to reason about changes:

- Edit source in `src/` and `scripts/`.
- Expect installed commands to resolve through symlinks into that source.
- Expect generated state, logs, snapshots, queues, and credential snapshots to
  live under `$ECO_HOME`, outside the repository.

## The Five Runtime Ideas

### 1. Surfaces: CLI and SwiftBar

There are two primary user-facing surfaces, both under `src/bin/`:

- `eco` is a Bash router. It lists recipes, runs recipes, opens the dashboard
  or map, calls the scheduler CLI, calls hygiene/account-swap recipes, and runs
  a small `doctor` self-check. It is deliberately thin.
- `eco-commander.15s.sh` is the SwiftBar plugin. It refreshes every 15 seconds,
  reads the latest runtime JSON files, performs a few live process probes, and
  renders the menu-bar panel.

`eco-alerts.sh` sits beside them as the alert/diagnostic action script. The
widget invokes it for verified issue state and quick actions; it can also be
run directly from the terminal.

The key rule: the surfaces display or dispatch. They do not own the quota
math, snapshot assembly, or scheduler logic.

### 2. Snapshots: Point-in-Time Audit Artifacts

The snapshot recipe (`src/recipes/snapshot.sh`) captures a timestamped audit
of the broader AI environment. It creates:

```text
$ECO_HOME/snapshots/<YYYY-MM-DDTHH-MMZ>/
├── layers/
│   ├── GA-hardware-llm.md
│   ├── GB-ai-clients.md
│   └── ... five more layer reports
├── state.json
├── map.md
└── dashboard.html
```

When the selected prompt library contains the canonical layer names, the recipe
runs those seven layers in order; otherwise it runs every non-README layer
prompt in that library. Gemini execution prefers `gem-smart 3.5f` when the
wrapper is available and falls back to plain `gemini -p`; prompt libraries are
read from `$ECO_AUDIT_ROOT/prompts`, `$ECO_HOME/ecosystem-audit/prompts`, or
the public `examples/snapshot-prompts/` library shipped with the repo.

Publication is pointer-based: the recipe builds a new timestamped directory,
then moves a temporary symlink into place so `$ECO_HOME/current` points to the
new snapshot.

One subtle but important detail: the **snapshot audit artifacts** (`state.json`,
`map.md`, `dashboard.html`, and `layers/`) are the point-in-time record. The
usage poller writes live `usage*.json` files through `$ECO_HOME/current`, so
those files are runtime overlay data associated with the current target, not
historical snapshot evidence.

See [Snapshots](../subsystems/snapshots.md) and
[Snapshot Lifecycle](../diagrams/snapshot-lifecycle.md).

### 3. Usage Monitor: Live Quota State

The usage monitor is the Python poller in `src/poller/`. launchd normally runs
it every 60 seconds.

On each cycle, `main.py` collects per-tool usage, writes per-tool JSON files,
merges them into `usage.json`, and calls `notify.py` to update meter state:

```text
Claude collector ─┐
Gemini collector ├─► $ECO_HOME/current/usage.json
Codex collector  ┘
                         │
                         ▼
                  $ECO_HOME/state/notify.json
```

The collectors are isolated: a failure in one tool becomes an `ok: false`
payload for that tool, not a failed poll cycle. Exception details go to private
logs; public JSON carries only sanitized error classes.

`notify.json` is the bridge from observation to scheduling. It records meter
state such as `hard_wall`, `throttle`, or `use_it_or_lose_it`; the scheduler
reads that state instead of re-querying providers.

See [Usage Monitor](../subsystems/usage-monitor.md) and
[Meter State Machine](../diagrams/meter-state-machine.md).

### 4. Recipes: Workflow Boundaries

A recipe is a standalone Bash workflow in `src/recipes/`. Recipes are the
system's command catalog: `ask`, `research`, `swarm`, `snapshot`,
`account-swap`, `hygiene`, `n8n-start`, `scheduler-seed`, and the dashboard
helpers all live there.

The contract is intentionally simple:

- A recipe has a structured header (`# DESC:`, `# INPUTS:`, `# OUTPUT:`,
  `# USES:`) so `eco list`, docs, and menu actions can describe it without
  parsing the whole script.
- A recipe is executable on its own and through `eco do <name>`.
- A recipe owns its side effects and states its output location up front.

Not every recipe writes to the same directory. Some print to stdout, some open
files, some update `$ECO_HOME`, and some write user-facing artifacts. The header
is the source of truth for each recipe's behavior.

See [Recipes](../subsystems/recipes.md).

### 5. Scheduler: Deferred Work Against Meter State

The scheduler is the Python package in `src/scheduler/`. It is quota-aware but
not a daemon: when the scheduler LaunchAgent is enabled, launchd runs one
dispatcher tick, the tick inspects the queue, fires at most the configured
number of jobs, persists state, and exits.

Each job has a `model_preference` ladder:

```yaml
model_preference:
  - provider: claude
    model: claude-sonnet
    meter: claude.session
  - provider: codex
    model: gpt-5.5
    meter: codex.session
  - provider: gemini
    model: gemini-3.1-flash-lite-preview
    meter: gemini.tiers.flash_lite
  - provider: ollama
    model: qwen3:4b
    meter: ollama.local
```

On each tick, the scheduler:

1. Loads `$ECO_HOME/state/notify.json`.
2. Loads `$ECO_HOME/queue/jobs.yaml`.
3. Finds ready jobs.
4. Walks each job's model-preference ladder.
5. Fires the first adapter whose meter is available.
6. Writes the attempt and updated job status back to the queue.

If every meter is blocked, the job becomes `gated_by_quota`; it is not dropped.
The next tick re-evaluates it against the latest meter state.

See [Scheduler](../subsystems/scheduler.md) and
[Scheduler Flow](../diagrams/scheduler-flow.md).

## The Main Invariant

Hold this model in your head:

```text
Background writers
  snapshot recipe  -> state.json, map.md, dashboard.html
  usage poller     -> usage.json and notify.json
  scheduler        -> jobs.yaml and queue logs

Foreground readers
  SwiftBar widget  -> current state, current usage, live process probes
  eco CLI          -> installed recipes and runtime files
  alerts script    -> snapshot candidates plus live verification
```

The system stays simple because these pieces communicate through local files
and process boundaries. There is no central resident server that every feature
has to call.

## What eco-commander Deliberately Is Not

- **Not cross-platform.** SwiftBar, launchd, and macOS filesystem conventions
  are part of the product.
- **Not a model host.** It invokes provider CLIs and local model tools; it does
  not serve models itself.
- **Not a network service.** There is no eco-commander daemon, listener, or RPC
  API in the source tree.
- **Not a replacement for the AI tools.** It routes work to them and observes
  their local state; it does not implement their reasoning, auth, or quota
  systems.

## See Also

| Document | Why |
|---|---|
| [Architecture](../architecture.md) | Component map and source/runtime layout |
| [Data Model](../reference/data-model.md) | JSON and YAML schemas for runtime files |
| [Recipes](../subsystems/recipes.md) | Full recipe catalog and contract |
| [Snapshots](../subsystems/snapshots.md) | Snapshot directory layout and lifecycle |
| [Usage Monitor](../subsystems/usage-monitor.md) | Poller sources, outputs, and calibration |
| [Scheduler](../subsystems/scheduler.md) | Queue schema, adapter protocol, meter rules |
| [Widget Rendering](../diagrams/widget-rendering.md) | What the SwiftBar plugin reads |
| [ADR 0003](../adr/0003-snapshot-immutability.md) | Snapshot publication rationale |
| [ADR 0004](../adr/0004-usage-monitor-python-carveout.md) | Why the poller is Python |
| [ADR 0005](../adr/0005-job-scheduler.md) | Why the scheduler is run-once-then-exit |
