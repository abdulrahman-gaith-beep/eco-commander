# Scheduler Package Manifest

> **Package**: `src/scheduler/` · **Language**: Python 3.10+ · **Version**: `0.2.0`
> **Entry point**: `python -m scheduler.cli <subcmd>` or `python -m scheduler.dispatcher`

## Module Dependency DAG

```
routing.py           ← leaf (no package imports)
adapters/base.py     ← leaf (stdlib only)
queue.py             ← leaf (yaml, stdlib)
adapters/claude.py   ← base.py, queue.py
adapters/codex.py    ← base.py, queue.py
adapters/gemini.py   ← base.py, queue.py
adapters/ollama.py   ← base.py, queue.py
adapters/__init__.py ← base, claude, codex, gemini, ollama (lazy)
dispatcher.py        ← queue, routing, adapters
cli.py               ← dispatcher, queue, routing
```

## Public API

| Module | Symbol | Type | Purpose |
|---|---|---|---|
| `cli.py` | `main(argv)` | `→ int` | CLI entrypoint |
| `dispatcher.py` | `tick(queue_path, log_dir, max_jobs_per_tick, state)` | `→ dict` | One locked scheduler pass |
| `queue.py` | `Job` | dataclass | Job data model |
| `queue.py` | `Attempt` | dataclass | Attempt record |
| `queue.py` | `load_queue(path)` | `→ list[Job]` | Read jobs.yaml |
| `queue.py` | `save_queue(jobs, path)` | `→ None` | Atomic write jobs.yaml |
| `queue.py` | `add_jobs(new, path)` | `→ int` | Append, skip id collisions |
| `queue.py` | `pending_ready_jobs(jobs, now)` | `→ list[Job]` | Filter + sort ready jobs |
| `queue.py` | `validate_workdir(value)` | `→ Path` | Privacy-surface-safe workdir |
| `routing.py` | `meter_status(state, key, now)` | `→ MeterStatus` | Single meter snapshot |
| `routing.py` | `pick_candidate(ladder, state, now)` | `→ LadderChoice` | Walk model-preference ladder |
| `adapters/__init__` | `get_adapter(provider)` | `→ Adapter` | Lazy adapter factory |
| `adapters/base.py` | `Adapter` | Protocol | fire(job, candidate, log_dir) → AdapterResult |
| `adapters/base.py` | `AdapterResult` | dataclass | ok, error_kind, paths, duration |

## Adapter Contract

Every adapter must implement:
```python
class MyAdapter:
    provider_name: str = "my_provider"

    def fire(self, job: Job, candidate: dict, log_dir: str) -> AdapterResult:
        ...
```

**Error kinds** map to meter state transitions:
| Kind | Meaning | Meter Effect |
|---|---|---|
| `""` | Success | — |
| `hard_wall` | Quota exhausted | Block meter, skip ladder rung |
| `throttle` | Rate limit | 60s cooldown, retry same rung |
| `timeout` | Wall clock exceeded | Bump attempt count, try next rung |
| `io_error` | CLI not found / config bug | Mark job failed |
| `nonzero_exit` | CLI ran, non-zero exit | Transient failure |
| `unknown` | Catch-all | Transient failure |

## Queue Schema (jobs.yaml)

```yaml
version: 1
jobs:
  - id: "audit-repo-health"           # starts alnum; 1..128 chars from [A-Za-z0-9._-], no '..'
    project: "eco-commander"
    workdir: "."
    template: "raw_prompt"             # raw_prompt | codegen-swift | research | audit
    template_vars:
      prompt: "Audit this repo..."
    model_preference:
      - { provider: gemini, model: gemini-3.1-flash-lite-preview, meter: gemini.tiers.flash_lite }
      - { provider: codex, model: gpt-5.5, meter: codex.session }
    earliest_iso: ""                   # ISO 8601, or empty = now
    priority: P2                       # P0 > P1 > P2 > P3
    timeout_s: 600                     # 1..21600
    retry: { max: 3, backoff_s: [60, 300, 1800] }
    requires_confirm: false
    depends_on_jobs: []
    status: pending                    # pending | running | completed | failed | gated_by_quota | cancelled
```

## CLI Subcommands

| Subcommand | Status | Description |
|---|---|---|
| `status` | ✅ Implemented | Pretty-print queue + meter state |
| `status --json` | ✅ Implemented | Machine-readable status |
| `add --file <yaml>` | ✅ Implemented | Append jobs from YAML |
| `run-once` | ✅ Implemented | One tick, print summary |
| `drain` | ✅ Implemented | Run ticks until idle |
| `tail [--id <id>]` | ✅ Implemented | Print latest attempt log |
| `seed --dir <path>` | ✅ Implemented | Import mission YAML files from directory |
| `cancel <id> [--force]` | ✅ Implemented | Cancel a pending/gated job |

## Registered Adapters

| Provider | Adapter Class | CLI Binary | Status |
|---|---|---|---|
| `codex` | `CodexAdapter` | `codex exec` | ✅ |
| `gemini` | `GeminiAdapter` | `gemini -p` | ✅ |
| `ollama` | `OllamaAdapter` | `ollama run` | ✅ |
| `claude` | `ClaudeAdapter` | `claude -p` | ✅ |

## Test Coverage

| Module | Test File | Status |
|---|---|---|
| `queue.py` | `tests/python/test_queue.py` | ✅ |
| `adapters/*` | `tests/python/test_adapters.py` | ✅ |
| `routing.py` | `tests/python/test_routing.py`, `tests/python/test_scheduler_routing.py` | ✅ |
| `dispatcher.py` | `tests/python/test_dispatcher.py` | ✅ |
| `cli.py` | `tests/python/test_scheduler_cli.py` | ✅ |
