# Data Flow

End-to-end data flow from the 60-second poller collectors through the merged
`usage.json`, into the scheduler's meter-gated dispatch loop, and up to the
SwiftBar widget.

```mermaid
flowchart TB
    subgraph Pollers["Poller (launchd, 60s)"]
        ClaudeP["claude.py\n(JSONL parsing)"]
        GeminiP["gemini.py\n(OAuth API replay)"]
        CodexP["codex.py\n(JSONL parsing)"]
        NotifyP["notify.py\n(meter computation)"]
    end

    subgraph UsageFiles["~/.eco/current/"]
        UClaude["usage-claude.json"]
        UGemini["usage-gemini.json"]
        UCodex["usage-codex.json"]
        UMerged["usage.json"]
    end

    subgraph MeterState["~/.eco/state/"]
        Notify["notify.json\n(meter availability)"]
    end

    subgraph Scheduler["Scheduler (launchd, 120s)"]
        Routing["routing.py\n(ladder walk)"]
        Dispatcher["dispatcher.py\n(fire jobs)"]
    end

    subgraph Queue["~/.eco/queue/"]
        Jobs["jobs.yaml"]
        Logs["logs/&lt;job-id&gt;/"]
    end

    subgraph Widget["SwiftBar (15s)"]
        Commander["eco-commander.15s.sh"]
    end

    subgraph Recipes["Recipes"]
        SnapshotR["snapshot.sh"]
        Others["other recipes"]
    end

    subgraph Snapshots["Snapshot outputs"]
        SnapshotDir["~/.eco/snapshots/&lt;ts&gt;/"]
        Current["~/.eco/current → latest snapshot"]
        StateJSON["state.json"]
    end

    ClaudeP --> UClaude
    GeminiP --> UGemini
    CodexP --> UCodex
    UClaude --> UMerged
    UGemini --> UMerged
    UCodex --> UMerged

    NotifyP --> Notify

    Notify --> Routing
    Jobs --> Routing
    Routing --> Dispatcher
    Dispatcher --> Logs
    Dispatcher --> Jobs

    UMerged --> Commander
    Current --> Commander
    SnapshotR --> SnapshotDir
    SnapshotDir --> Current
    Others --> Current
```

## Source References

| Component | Source |
|-----------|--------|
| Poller | [`src/poller/main.py`](../../src/poller/main.py) |
| Scheduler | [`src/scheduler/dispatcher.py`](../../src/scheduler/dispatcher.py) |
| Widget | [`src/bin/eco-commander.15s.sh`](../../src/bin/eco-commander.15s.sh) |
| Snapshot | [`src/recipes/snapshot.sh`](../../src/recipes/snapshot.sh) |

**Related docs:** [Architecture](../architecture.md) · [Data Model](../reference/data-model.md) · [Filesystem Layout](filesystem-layout.md) · [Usage Monitor](../subsystems/usage-monitor.md)
