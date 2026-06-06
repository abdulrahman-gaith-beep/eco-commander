# Meter State Machine

Quota meters bridge the poller (`src/poller/notify.py` + `pace.py`) and the
scheduler (`src/scheduler/routing.py`). Each meter tracks one quota bucket
(e.g., `gemini.tiers.flash`, `codex.session`, `claude.weekly`).

## State Transitions

```mermaid
stateDiagram-v2
    [*] --> unknown : First poller cycle\n(no data yet)

    unknown --> hard_wall : pct &gt;= 95
    unknown --> throttle : pct &gt;= 80 AND target &lt;= 60 AND delta &gt;= +25
    unknown --> use_it_or_lose_it : target &gt;= 80 AND delta &lt;= -15 AND (100 - pct) &gt;= 15
    unknown --> healthy : else -&gt; None -&gt; written as "healthy"

    healthy --> hard_wall : pct &gt;= 95
    healthy --> throttle : pct &gt;= 80 AND target &lt;= 60 AND delta &gt;= +25
    healthy --> use_it_or_lose_it : target &gt;= 80 AND delta &lt;= -15 AND (100 - pct) &gt;= 15

    use_it_or_lose_it --> hard_wall : pct &gt;= 95
    use_it_or_lose_it --> throttle : pct &gt;= 80 AND target &lt;= 60 AND delta &gt;= +25
    use_it_or_lose_it --> healthy : else -&gt; None -&gt; written as "healthy"

    throttle --> hard_wall : pct &gt;= 95
    throttle --> use_it_or_lose_it : target &gt;= 80 AND delta &lt;= -15 AND (100 - pct) &gt;= 15
    throttle --> healthy : else -&gt; None -&gt; written as "healthy"

    hard_wall --> throttle : pct &gt;= 80 AND target &lt;= 60 AND delta &gt;= +25
    hard_wall --> use_it_or_lose_it : target &gt;= 80 AND delta &lt;= -15 AND (100 - pct) &gt;= 15
    hard_wall --> healthy : else -&gt; None -&gt; written as "healthy"
```

## Scheduler Availability Rules

```mermaid
flowchart LR
    subgraph Check["Meter Availability Check (routing.py)"]
        Read["Read meter from\nnotify.json"] --> Kind{"last_kind?"}

        Kind -->|hard_wall| HWCheck{"last_reset_epoch\n&gt; now?"}
        HWCheck -->|Yes| Blocked["🔒 BLOCKED\n(seconds_until = last_reset_epoch - now)"]
        HWCheck -->|No| Available

        Kind -->|throttle| ThCheck{"now - last_fired_ts\n&lt; 60s?"}
        ThCheck -->|Yes| Cooldown["🔒 COOLDOWN\n(seconds_until = 60 - elapsed)"]
        ThCheck -->|No| Available

        Kind -->|use_it_or_lose_it| Available["✅ AVAILABLE\n(burn it before reset)"]

        Kind -->|unknown| Available
    end
```

## Threshold Constants (from `pace.py`)

```mermaid
flowchart TB
    subgraph Thresholds["Notification Thresholds"]
        UIOLI["🟢 use_it_or_lose_it\ntarget_pct_min: 80%\ndelta_pp_max: -15pp\nremaining_min: 15%\ndebounce: 12h"]

        Throttle["🟡 throttle\npct_min: 80%\ntarget_pct_max: 60%\ndelta_pp_min: +25pp\ndebounce: 4h"]

        HardWall["🔴 hard_wall\npct_min: 95%\ndebounce: 1h"]
    end

    subgraph Pace["Pace Classification (display only)"]
        Idle["💤 idle\nactual &lt; 1% AND\nexpected &lt; 5%"]
        Ahead["🐎 ahead\nactual - expected &gt; +10pp"]
        OnPace["🟢 on-pace\nwithin ±10pp"]
        Behind["🐢 behind\nactual - expected &lt; -10pp"]
    end

    subgraph Guards["Safety Guards"]
        Wake["WAKE_DEBOUNCE_S: 300s\nSkip evaluation if previous\npoll &gt; 5 min ago\n(laptop wake guard)"]
    end
```

## Interaction with Scheduler Dispatch

```mermaid
sequenceDiagram
    participant P as Poller (60s)
    participant N as notify.json
    participant S as Scheduler (120s)
    participant A as Adapter

    P->>P: Collect usage for claude/gemini/codex
    P->>P: pace.classify_pace(actual, target)
    P->>P: notify.evaluate(merged) — check thresholds
    P->>N: Write meter state (kind + reset_epoch)

    Note over P,N: 60s later...

    S->>N: Read meter state
    S->>S: routing.pick_candidate(ladder, state)
    S->>S: For each rung: meter_status(state, key)

    alt Meter available
        S->>A: adapter.fire(job, candidate, log_dir)
        A-->>S: AdapterResult
        S->>N: Stamp last_fired_ts (throttle cooldown)
    else All meters blocked
        S->>S: Mark job gated_by_quota
    end
```

## Source References

| Component | Source |
|-----------|--------|
| Threshold constants | [`src/poller/pace.py`](../../src/poller/pace.py) — `THRESHOLDS`, `DEBOUNCE_HOURS`, `WAKE_DEBOUNCE_S` |
| Classification logic | [`src/poller/notify.py`](../../src/poller/notify.py) — `_classify()` |
| Meter definitions | [`src/poller/notify.py`](../../src/poller/notify.py) — `METERS` list |
| Scheduler routing | [`src/scheduler/routing.py`](../../src/scheduler/routing.py) — `meter_status()`, `pick_candidate()` |
| Adapter dispatch | [`src/scheduler/dispatcher.py`](../../src/scheduler/dispatcher.py) |

**Related docs:** [Architecture](../architecture.md) · [Scheduler](../subsystems/scheduler.md) · [Usage Monitor](../subsystems/usage-monitor.md) · [ADR 0005](../adr/0005-job-scheduler.md)
