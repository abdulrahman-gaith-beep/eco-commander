# ADR 0005 — Job Scheduler: Quota-Aware Multi-Provider Dispatch

| Field   | Value |
|---------|-------|
| Status  | Accepted |
| Date    | 2026-05-11 |
| Amends  | [ADR 0004 — Usage Monitor: Python Carve-out](./0004-usage-monitor-python-carveout.md) |

## Context

The user runs AI workloads across multiple providers (Claude Code, Codex/GPT,
Gemini Pro/Flash/Flash Lite, Ollama local models). Each provider has
independent quotas that reset at different times. Manually checking quota
availability before dispatching work is friction-heavy and error-prone.

The usage monitor (ADR 0004) already writes per-provider meter state to
`~/.eco/state/notify.json`. A scheduler can read these meters and automatically
dispatch queued jobs to whichever provider has available capacity.

> **Related Diagrams:**
> - [`docs/diagrams/scheduler-flow.md`](../diagrams/scheduler-flow.md) — dispatch loop
> - [`docs/diagrams/meter-state-machine.md`](../diagrams/meter-state-machine.md) — meter control of dispatch

## Decision

### 1. Add a scheduler module at `src/scheduler/`

```text
src/scheduler/
├── __init__.py
├── queue.py        # YAML-backed job queue at ~/.eco/queue/jobs.yaml
├── routing.py      # meter availability checks + model-preference ladder walk
├── dispatcher.py   # single-tick dispatch loop
├── cli.py          # CLI surface: status, add, run-once, drain, tail, seed
└── adapters/
    ├── base.py     # abstract adapter + AdapterResult type
    ├── claude.py   # Claude Code CLI adapter
    ├── codex.py    # Codex CLI adapter
    ├── gemini.py   # Gemini CLI adapter
    └── ollama.py   # Ollama local adapter
```

### 2. Run-once-then-exit semantics

The scheduler is **not** a long-running daemon. launchd invokes it every
2 minutes (`StartInterval: 120`) via
`scripts/launchagents/com.eco-commander.scheduler.plist`. Each invocation
loads state, fires up to `max_jobs_per_tick` jobs, persists results, and exits.

### 3. Model-preference ladder

Each job carries an ordered list of `{provider, model, meter}` preferences.
The scheduler walks the ladder top-to-bottom and fires via the first rung
whose meter reports as available.

### 4. Quota-wall awareness

When a provider returns `hard_wall` (quota exhausted), the attempt does **not**
count against the job's retry maximum. The job is marked `gated_by_quota` and
re-evaluated on the next tick once the meter clears.

### 5. Crash safety

- Queue writes use `tempfile + os.replace` for atomicity.
- POSIX `fcntl.flock` prevents concurrent ticks.
- Jobs stuck in `running` past `timeout_s + 60 s` are automatically reset to
  `pending` on the next tick.

### 6. Python + PyYAML dependency

The scheduler uses Python (≥ 3.10) plus **PyYAML** — the only non-stdlib
dependency in the project. This extends the ADR 0004 Python carve-out to
`src/scheduler/`. PyYAML is declared in `requirements.txt` and is available
via the project venv (`make venv`).

## Consequences

**Positive:**
- Jobs fire automatically when quota is available — no manual monitoring.
- Model-preference ladders enable graceful degradation across providers.
- Hard-wall awareness prevents wasting retries against quota exhaustion.
- Run-once semantics keep the process footprint minimal.
- YAML queue (`~/.eco/queue/jobs.yaml`) is human-readable and hand-editable.

**Negative:**
- Adds a third LaunchAgent (`com.eco-commander.scheduler`) under
  `~/Library/LaunchAgents/`.
- PyYAML is a non-stdlib dependency (available via the project venv or
  Homebrew Python).
- The scheduler depends on the poller's `notify.json`; if the poller is
  down, meter state goes stale and the scheduler operates optimistically.

## Alternatives Considered

| Alternative | Reason rejected |
|-------------|-----------------|
| **Cron-based bash script** | YAML parsing, ladder walking, and atomic queue management in bash would be fragile and slow. |
| **Long-running Python daemon** | Higher resource usage, more failure modes, harder to debug. launchd handles scheduling and restart better. |
| **Integrating into the poller** | Separation of concerns: the poller is read-only (observes quota); the scheduler is write-active (fires jobs, mutates queue). Coupling them would make both harder to test. |
