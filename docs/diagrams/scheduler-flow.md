# Scheduler Dispatch Flow

Single-pass dispatch loop executed by `src/scheduler/dispatcher.py` every
120 seconds under launchd — reads the job queue, walks each job's
model-preference ladder, fires via the first available meter, and persists
state atomically before exiting.

```mermaid
flowchart TD
    Start["launchd fires scheduler (every 120s)"] --> LoadState["Load ~/.eco/state/notify.json"]
    LoadState --> LoadQueue["Load ~/.eco/queue/jobs.yaml"]
    LoadQueue --> ResetStale["Reset stale 'running' jobs (timeout + 60s grace)"]
    ResetStale --> FilterReady["Filter to ready jobs\n(pending/gated + earliest_iso <= now + deps met)"]
    FilterReady --> SortPriority["Sort by priority (P0→P3), earliest_iso, created_iso"]

    SortPriority --> NextJob{"Next job?"}
    NextJob -->|No more jobs| Done["Exit 0 — persist queue"]
    NextJob -->|Max jobs fired| Done

    NextJob -->|Yes| CheckConfirm{"requires_confirm?"}
    CheckConfirm -->|Yes| SkipConfirm["Skip — add to 'gated' summary"]
    SkipConfirm --> NextJob

    CheckConfirm -->|No| WalkLadder["Walk model_preference ladder"]
    WalkLadder --> CheckMeter{"Meter available?"}

    CheckMeter -->|All blocked| GateQuota["Mark job 'gated_by_quota'\nPersist queue"]
    GateQuota --> NextJob

    CheckMeter -->|Found open rung| MarkRunning["Mark job 'running'\nPersist queue (crash safety)"]
    MarkRunning --> GetAdapter["Get adapter for provider"]
    GetAdapter --> Fire["adapter.fire(job, candidate, log_dir)"]

    Fire --> CheckResult{"Result OK?"}
    CheckResult -->|Success| Complete["Mark 'completed'\nPersist queue"]
    Complete --> NextJob

    CheckResult -->|hard_wall| HardWall["Mark 'pending'\n(does NOT count against retry max)"]
    HardWall --> NextJob

    CheckResult -->|Other failure| CheckRetry{"Retries exhausted?"}
    CheckRetry -->|Yes| Failed["Mark 'failed'\nPersist queue"]
    CheckRetry -->|No| Retry["Mark 'pending'\nIncrement attempt counter"]
    Failed --> NextJob
    Retry --> NextJob
```

## Source References

| Component | Source |
|-----------|--------|
| CLI surface | [`src/scheduler/cli.py`](../../src/scheduler/cli.py) |
| Dispatch loop | [`src/scheduler/dispatcher.py`](../../src/scheduler/dispatcher.py) |
| Job queue | [`src/scheduler/queue.py`](../../src/scheduler/queue.py) |
| Routing / meter check | [`src/scheduler/routing.py`](../../src/scheduler/routing.py) |
| Adapters | [`src/scheduler/adapters/`](../../src/scheduler/adapters/) |
| LaunchAgent plist | [`scripts/launchagents/`](../../scripts/launchagents/) |

**Related docs:** [Architecture](../architecture.md) · [Scheduler](../subsystems/scheduler.md) · [ADR 0005](../adr/0005-job-scheduler.md) · [Runbook §3](../operations/runbook.md) · [Runbook §8](../operations/runbook.md)
