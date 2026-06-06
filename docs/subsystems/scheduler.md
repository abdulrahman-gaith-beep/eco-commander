# Job Scheduler

Quota-aware, multi-provider AI job dispatcher. Reads meter state from the
usage poller and a federated job queue, then fires jobs via the first
provider whose quota is available.

Status: **experimental**. The scheduler is suitable for controlled local use,
but failed adapter attempts are intentionally surfaced: `run-once` returns
non-zero when any fired attempt fails, and `drain` stops with a non-zero exit on
the first failed attempt.

## Overview

The scheduler is a Python module at `src/scheduler/` with run-once-then-exit
semantics. launchd invokes `scheduler.dispatcher` every 2 minutes — it is
**not** a long-running daemon.

```text
┌─ launchd (every 120s) ──────────────────────────────────────┐
│  python3 -m scheduler.dispatcher                            │
│                                                             │
│  1. Load ~/.eco/state/notify.json (meter state from poller) │
│  2. Load ~/.eco/queue/jobs.yaml (job queue)                 │
│  3. Reset any jobs stuck in 'running' past timeout + 60s    │
│  4. Filter to ready jobs (pending/gated_by_quota,           │
│     earliest_iso <= now, depends_on_jobs satisfied)         │
│  5. Walk each job's model_preference ladder                 │
│  6. Fire via first adapter whose meter is open              │
│  7. Record attempt, update job status, persist queue        │
└─────────────────────────────────────────────────────────────┘
```

**Related docs:**
- [Scheduler Flow diagram](../diagrams/scheduler-flow.md)
- [Meter State Machine diagram](../diagrams/meter-state-machine.md)
- [ADR 0005 — Job scheduler architecture](../adr/0005-job-scheduler.md)
- [Module Dependencies diagram](../diagrams/module-deps.md)

## CLI

All scheduler commands are accessed via `python -m scheduler.cli <subcommand>`
or through the `eco` wrapper alias where installed.

| Subcommand | Description |
|---|---|
| `status` | Pretty-print queue depth + meter availability. Add `--json` for machine-readable output. |
| `add --file <path>` | Append jobs from a YAML file into the queue. Skips jobs whose `id` already exists. |
| `run-once [--max-jobs N]` | Execute one scheduler tick (for debugging). Prints summary JSON and exits non-zero if any fired attempt failed. |
| `drain [--max-ticks N] [--interval-s S]` | Run ticks until the queue is idle or N ticks have elapsed. Stops and exits non-zero on the first failed attempt. |
| `tail [--id <job-id>]` | Print stdout log of the most recent job attempt. Defaults to the latest; specify `--id` for a specific job. |
| `seed --dir <path>` | Import all `*.yaml`/`*.yml` mission files from a directory into the queue. |
| `cancel <job-id> [--force]` | Cancel a pending or gated job by id. Use `--force` to cancel a job in any state. |

### Examples

```bash
# Show queue depth and meter availability
python -m scheduler.cli status
python -m scheduler.cli status --json

# Add jobs from a YAML file
python -m scheduler.cli add --file examples/missions/seed-jobs.example.yaml

# Import all YAML files from a directory
python -m scheduler.cli seed --dir examples/missions/

# One dispatch tick (debug)
python -m scheduler.cli run-once

# Drain until idle (up to 20 ticks)
python -m scheduler.cli drain --max-ticks 20

# Inspect the most recent attempt log
python -m scheduler.cli tail
python -m scheduler.cli tail --id my-job-id

# Cancel a job
python -m scheduler.cli cancel my-job-id
python -m scheduler.cli cancel my-job-id --force
```

Scheduler logs can contain prompts and model output. Treat `tail` as a
local operator debugging command; for agent review, provide redacted
excerpts or synthetic fixtures.

## Job YAML schema

Jobs are defined in YAML files and imported via `python -m scheduler.cli add`
or `seed`. The queue file lives at `~/.eco/queue/jobs.yaml`.

```yaml
version: 1
jobs:
  - id: "unique-job-identifier"          # [A-Za-z0-9._-], max 128 chars
    project: "eco-commander"             # which project this job relates to
    workdir: "~/projects/eco-commander"  # working directory for the adapter
    template: "raw_prompt"               # raw_prompt | codegen-swift | research | audit
    template_vars:                       # passed to the adapter's prompt renderer
      prompt: "Audit the snapshot module for edge cases"
    model_preference:                    # ladder — walked top to bottom
      - provider: claude
        model: claude-sonnet-4-20250514
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
    priority: P2                         # P0 (critical) → P3 (backlog)
    earliest_iso: "2026-05-11T08:00:00+03:00"  # don't run before this time
    timeout_s: 600                       # wall-clock timeout per attempt (1–21600s)
    retry:
      max: 3                             # max non-wall attempts before failing
      backoff_s: [60, 300, 1800]         # retry delays; nth entry is reused after the list ends
    requires_confirm: false              # if true, job is gated until manually approved
    depends_on_jobs:                     # won't run until these ids are 'completed'
      - "prerequisite-job-id"
    notes: "Free-form notes for humans"
```

### Job statuses

| Status | Meaning |
|--------|---------|
| `pending` | Ready to be scheduled (subject to `earliest_iso` and `depends_on_jobs`) |
| `gated_by_quota` | All meters in the preference ladder are blocked; re-evaluated next tick |
| `running` | Currently being executed by an adapter |
| `completed` | Adapter returned success |
| `failed` | Max retries exhausted or unrecoverable error |
| `cancelled` | Manually cancelled via `cli cancel` |

### Priority levels

| Priority | Use case |
|----------|----------|
| P0 | Critical — fires before all others |
| P1 | High — time-sensitive work |
| P2 | Normal (default) |
| P3 | Backlog — runs only when capacity is idle |

Priority sort order: P0 first, then by `earliest_iso` ascending, then
by `created_iso`. `gated_by_quota` jobs are re-evaluated each tick and
compete alongside `pending` jobs at their stated priority.

`retry.backoff_s` is active scheduler behavior. For hard-wall and transient
adapter failures, the dispatcher sets `earliest_iso` to now plus the selected
backoff delay. The selected delay is based on the current failed-attempt number;
the last configured value is reused when attempts outnumber the list. Hard-wall
attempts still do not count against `retry.max`, but they do receive a backoff
and can stamp a fallback `last_reset_epoch` into `notify.json` when the meter
state has no future reset time.

## Meter system

The scheduler reads meter state from `~/.eco/state/notify.json`, written by
the usage poller's `notify.py` module. Each meter entry contains:

| Field | Description |
|-------|-------------|
| `last_kind` | `use_it_or_lose_it` \| `throttle` \| `hard_wall` \| `unknown` |
| `last_reset_epoch` | Unix timestamp when the quota resets |
| `last_fired_ts` | Unix timestamp when the scheduler last fired on this meter |

### Meter availability rules

| Kind | Blocked when | Scheduler behavior |
|------|-------------|-------------------|
| `hard_wall` | `last_reset_epoch > now` | Fully blocked until reset. Job becomes `gated_by_quota`. Hard-wall failures do not count against `retry.max`. |
| `throttle` | `now - last_fired_ts < 60` | 60-second cooldown between fires on this meter. |
| `use_it_or_lose_it` | Never | Always available — burn it before it resets. |
| `unknown` | Never | Optimistic — attempt the job rather than over-block. |

The dispatcher stamps `last_fired_ts` into `notify.json` at dispatch time
(not notification delivery time) so the 60-second throttle cooldown is
anchored to actual execution.

Gemini Flash Lite uses the underscore key `gemini.tiers.flash_lite` in
`notify.json` and in scheduler job ladders.

## Adapters

Each provider has an adapter implementing the `Adapter` protocol from
`src/scheduler/adapters/base.py`:

```python
class Adapter(Protocol):
    provider_name: str

    def fire(self, job, candidate: dict[str, str], log_dir: str) -> AdapterResult: ...
```

### Available adapters

| Adapter | Provider | CLI invocation | Env override |
|---------|----------|---------------|--------------|
| `ClaudeAdapter` | `claude` | `claude -p <prompt> --output-format text` | `ECO_CLAUDE_BIN` |
| `CodexAdapter` | `codex` | `codex exec --skip-git-repo-check --cd <workdir> -m <model>` (prompt via stdin) | `ECO_CODEX_BIN` |
| `GeminiAdapter` | `gemini` | `gemini -p "" -m <model> --approval-mode <mode> --allowed-mcp-server-names none --output-format text` (prompt via stdin; optional `--include-directories <dir>`) | `ECO_GEMINI_BIN` |
| `OllamaAdapter` | `ollama` | `ollama run <model>` (prompt via stdin) | `ECO_OLLAMA_BIN` |

All adapters are registered in `src/scheduler/adapters/__init__.py`'s
`get_adapter()` function. `ClaudeAdapter` and the others are lazy-imported
at dispatch time to keep cold-start fast.

All adapters:
- Start the subprocess with `start_new_session=True` (own process group) so
  `SIGKILL` on timeout kills the entire process tree, including forked MCP
  servers or Node workers.
- Redact bearer tokens and `sk-*` secrets from captured logs before writing
  them to disk.
- Support `ECO_DRY_RUN=1` for test/CI runs that echo the command and exit 0.

### Supported templates

| Template | Supported by |
|----------|-------------|
| `raw_prompt` | All adapters (reads `template_vars.prompt`) |
| `codegen-swift` | Claude, Codex |
| `audit` | Claude |
| `research` | Gemini |

### Error kinds

Adapter results carry an `error_kind` that maps to scheduling behavior:

| Error kind | Meaning | Scheduler response |
|------------|---------|-------------------|
| `hard_wall` | Quota exhausted | Leave job `pending`, set `earliest_iso` from `retry.backoff_s`, and do **not** increment non-wall retry count |
| `throttle` | Rate limited | Stamp the meter as throttled and set `earliest_iso` from `retry.backoff_s` |
| `timeout` | Wall clock exceeded | Bump non-wall attempt count and set `earliest_iso` from `retry.backoff_s` |
| `io_error` | CLI not found / file missing | Mark job `failed` (configuration bug) |
| `nonzero_exit` | CLI ran but returned non-zero | Treat as transient failure |
| `unknown` | Catch-all | Treat as transient failure |

### Adding a new adapter

1. Create `src/scheduler/adapters/<provider>.py`.
2. Implement a class with `provider_name: str` and
   `fire(job, candidate, log_dir) -> AdapterResult`.
   Follow `base.py`'s `Adapter` protocol.
3. Register it in `src/scheduler/adapters/__init__.py`'s `get_adapter()`
   function by adding a new `if provider == "<name>":` branch.

## Crash safety

- Before firing a job, the dispatcher marks it `running` and persists the
  queue. If the process is killed mid-fire, `_reset_stale_running()` resets
  jobs stuck in `running` past `timeout_s + 60s` back to `pending` on the
  next tick.
- Queue writes use `tempfile.mkstemp` + `os.replace` for atomicity.
- A per-queue `fcntl.LOCK_EX` tick lock prevents two concurrent launchd
  invocations from claiming the same job.
- Log directories are created with `0700` permissions; log files are `0600`.

### Known limitations (v0.x, experimental)

- `notify.json` assumes a single writer for meter-state updates. The
  scheduler dispatcher and usage poller can both read-modify-write
  `~/.eco/state/notify.json`, and those concurrent writes are not yet
  protected by a shared cross-process lock. Queue writes remain separately
  lock-protected.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO_HOME` | `~/.eco` | Runtime data root |
| `ECO_MAX_JOBS_PER_TICK` | `1` | Jobs to fire per `scheduler.dispatcher` invocation |
| `ECO_DRY_RUN` | (unset) | Set to `1` to echo commands without executing |
| `ECO_CLAUDE_BIN` | `claude` | Path to Claude Code CLI |
| `ECO_CODEX_BIN` | `codex` | Path to Codex CLI |
| `ECO_GEMINI_BIN` | `gemini` | Path to Gemini CLI |
| `ECO_OLLAMA_BIN` | `ollama` | Path to Ollama CLI |
| `ECO_GEMINI_APPROVAL_MODE` | `plan` | Gemini approval mode (`default`, `auto_edit`, `yolo`, `plan`) |
| `ECO_GEMINI_ALLOW_EXTERNAL_INCLUDE_DIRS` | (unset) | Set to `1` to allow `include_directories` outside the job workdir |

## Files

| Path | Purpose |
|------|---------|
| `~/.eco/queue/jobs.yaml` | Persistent job queue (atomic writes, POSIX flock) |
| `~/.eco/queue/logs/` | Private per-attempt stdout/stderr logs (`0700` dir, `0600` files) |
| `~/.eco/state/notify.json` | Meter state (written by poller; also updated by dispatcher at fire time) |
| `scripts/launchagents/com.eco-commander.scheduler.plist` | LaunchAgent template |

## LaunchAgent

The LaunchAgent plist (`com.eco-commander.scheduler.plist`) invokes
`python3 -m scheduler.dispatcher` every 120 seconds with:

- `ProcessType: Background` and `Nice: 5` (background CPU priority)
- `LowPriorityIO: true` (low-priority disk I/O)
- `ThrottleInterval: 60` (minimum 60s between crash-restart loops)
- `ExitTimeOut: 900` (allow long jobs up to 15 minutes before SIGKILL)
- `KeepAlive: false` (no restart after normal exit — `StartInterval` handles cadence)

```bash
# Install and load the scheduler LaunchAgent:
ECO_SCHEDULER_AUTO_LOAD=1 bash scripts/install-launchagents.sh

# Check scheduler status:
launchctl list com.eco-commander.scheduler

# Manually trigger a tick:
python -m scheduler.cli run-once
```

## Related

- [Usage Monitor](./usage-monitor.md) — writes the meter state the scheduler reads
- [Recipes](./recipes.md) — `scheduler-seed` recipe automates queue population
- [Architecture overview](../architecture.md)
- [Environment variables reference](../reference/environment-variables.md)
- [Data model reference](../reference/data-model.md)
- [LaunchAgent best practices](./launchd-best-practices.md)
