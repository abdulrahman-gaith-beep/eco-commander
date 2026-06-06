# Data Flow

End-to-end data flow from the 60-second poller collectors through the merged `usage.json`, into the scheduler's meter-gated dispatch loop, and up to the SwiftBar widget, highlighting the on-demand snapshot recipe that rotates the base state directory.

```mermaid
flowchart TB
    subgraph Poller["Poller (launchd, 60s)"]
        direction TB
        P_C["collectors"] --> P_AW["per-tool atomic writes"]
        P_AW --> P_Alt["alternatives"]
        P_Alt --> P_M["merge"]
        P_M --> P_V["value"]
        P_V --> P_Com["comments"]
        P_Com --> P_U["usage.json"]
        P_U --> P_N["notify"]
    end

    subgraph Recipes["Recipes (On-demand)"]
        Snap["snapshot.sh"]
    end

    subgraph Scheduler["Scheduler (launchd, 120s)"]
        direction TB
        S_R["Reads notify.json &amp; jobs.yaml"] --> S_F["Fires adapters"]
        S_F --> S_W["Writes last_fired_ts"]
    end

    subgraph Widget["SwiftBar (15s)"]
        Cmd["eco-commander.15s.sh"]
    end

    subgraph Filesystem["~/.eco/ Filesystem"]
        subgraph Snapshots["snapshots/&lt;ts&gt;/"]
            S_State["state.json"]
            S_Map["map.md, dashboard.html"]
            S_Usage["usage*.json"]
        end

        Current["current/<br>(symlink to latest snapshots/&lt;ts&gt;/)"]

        NotifyJSON["state/notify.json"]
        JobsYAML["queue/jobs.yaml"]
    end

    %% Poller writes
    P_AW -- "usage-&lt;tool&gt;.json" --> Current
    P_U -- "usage.json" --> Current
    Current -. "Written through symlink" .-> S_Usage
    P_N -- "Writes" --> NotifyJSON

    %% Snapshot writes
    Snap -- "Writes" --> S_State
    Snap -- "Writes" --> S_Map
    Snap -- "Flips symlink to new &lt;ts&gt;" --> Current

    %% Scheduler interactions
    NotifyJSON -- "Reads" --> S_R
    JobsYAML -- "Reads" --> S_R
    S_W -- "Updates" --> NotifyJSON

    %% Widget interactions
    Current -- "Reads current/usage.json<br>&amp; current/state.json" --> Cmd
```

## Source References

| Component | Source |
|-----------|--------|
| Poller | [`src/poller/main.py`](../../src/poller/main.py) |
| Scheduler | [`src/scheduler/dispatcher.py`](../../src/scheduler/dispatcher.py) |
| Widget | [`src/bin/eco-commander.15s.sh`](../../src/bin/eco-commander.15s.sh) |
| Snapshot | [`src/recipes/snapshot.sh`](../../src/recipes/snapshot.sh) |

**Related docs:** [Architecture](../architecture.md) · [Data Model](../reference/data-model.md) · [Filesystem Layout](filesystem-layout.md) · [Usage Monitor](../subsystems/usage-monitor.md)
