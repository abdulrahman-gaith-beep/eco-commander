# Widget Rendering — Data Sources

How `eco-commander.15s.sh` (35KB) assembles the SwiftBar menu bar widget.

## Data Source Map

```mermaid
flowchart TB
    subgraph Sources["Data Sources"]
        UsageJSON["~/.eco/current/usage.json\n(poller, 60s refresh)"]
        StateJSON["~/.eco/current/state.json\n(snapshot recipe)"]
        Profile["~/.ai-ecosystem/.current-profile\n(MCP profile name)"]
        DockerPS["docker ps\n(live process check)"]
        OllamaPS["pgrep ollama +\nollama ps / ollama list\n(live process check)"]
        AlertIssues["eco-alerts.sh widget-issues\n(alert normalization)"]
        QueueState["~/.eco/queue/jobs.yaml\n(scheduler queue depth)"]
    end

    subgraph Widget["eco-commander.15s.sh"]
        direction TB
        Title["Menu Bar Title\n🟢/🟡/🔴 + profile + llama count + RAM"]
        Sep1["---"]
        UsageSection["Usage Section\nC 3/53w · X 99/68w · G 13\nPer-tool progress bars + reset times"]
        Sep2["---"]
        AlertSection["Alert Section\n⚠ N Alerts\nlive · evidence · triage · cleared"]
        Sep3["---"]
        ToolStatus["Tool Status\nDocker containers\nOllama models loaded/installed\nMCP profile"]
        Sep4["---"]
        Actions["Actions\nRefresh · Snapshot · Dashboard\nAlert Doctor · Repo Health\nOpen docs/logs"]
    end

    subgraph Fallbacks["Missing/Stale Handling"]
        NoUsage["usage.json missing → 'usage:—'"]
        StaleUsage["usage.json &gt; 180s → ⚠ stale marker"]
        NoState["state.json missing → skip snapshot section"]
        NoDocker["docker not found → skip containers"]
        NoOllama["ollama not found → 0/0 count"]
    end

    UsageJSON --> UsageSection
    UsageJSON --> Title
    StateJSON --> ToolStatus
    Profile --> Title
    DockerPS --> ToolStatus
    OllamaPS --> Title
    OllamaPS --> ToolStatus
    AlertIssues --> AlertSection
    QueueState --> AlertSection

    UsageJSON -.-> Fallbacks
    StateJSON -.-> Fallbacks
```

## Menu Bar Title Composition

```mermaid
flowchart LR
    subgraph Inputs["Inputs"]
        WorstMeter["Worst meter across\nclaude/gemini/codex"]
        ProfileName["MCP profile name"]
        LlamaCount["Ollama loaded/installed"]
        FreeRAM["Available memory (GB)"]
        SnapshotAge["current → snapshot age"]
    end

    subgraph Title["Title Line"]
        Icon["Quota contribution:\n🟢 green: &lt; 80%\n🟡 amber: 80-94%\n🔴 red: ≥ 95%"]
        Text["profile · 🦙 L/I · RAM"]
    end

    WorstMeter --> Icon
    ProfileName --> Text
    LlamaCount --> Text
    FreeRAM --> Text
```

## Rendering Sequence

```mermaid
sequenceDiagram
    participant SB as SwiftBar (15s trigger)
    participant W as eco-commander.15s.sh
    participant FS as Filesystem
    participant Live as Live Probes

    SB->>W: Execute plugin
    W->>FS: Read usage.json
    W->>FS: Read state.json
    W->>FS: Read .current-profile
    W->>Live: docker ps (if available)
    W->>Live: pgrep ollama + ollama ps
    W->>W: eco-alerts.sh widget-issues
    W->>W: Compute worst meter → icon color
    W->>W: Format title line
    W->>W: Render dropdown sections
    W-->>SB: Emit stdout (SwiftBar protocol)
```

## Source References

| Component | Source |
|-----------|--------|
| Widget script | [`src/bin/eco-commander.15s.sh`](../../src/bin/eco-commander.15s.sh) |
| Alert normalization | [`src/bin/eco-alerts.sh`](../../src/bin/eco-alerts.sh) |
| Usage data producer | [`src/poller/main.py`](../../src/poller/main.py) |

**Related docs:** [Architecture](../architecture.md) · [Widget Health](../subsystems/widget-health.md) · [Usage Monitor](../subsystems/usage-monitor.md) · [Data Model](../reference/data-model.md)
