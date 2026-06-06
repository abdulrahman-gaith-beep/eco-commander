# Architecture Diagram

Top-level component map of eco-commander: how the CLI, background agents,
recipes, state directories, and external AI tools relate to each other.

```mermaid
graph TB
    subgraph User["User Interface"]
        Terminal["Terminal"]
        SwiftBar["SwiftBar Menu Bar"]
    end

    subgraph CLI["CLI Layer"]
        eco["eco (router)"]
        commander["eco-commander.15s.sh"]
        alerts["eco-alerts.sh"]
    end

    subgraph Recipes["Recipe Library"]
        ask["ask"]
        note["note"]
        research["research"]
        swarm["swarm"]
        snapshot["snapshot"]
        arabicproof["arabic-proof"]
        dashboard["dashboard"]
        accountswap["account-swap"]
        hygiene["hygiene"]
        n8nstart["n8n-start"]
        dashrefresh["dashboard-refresh"]
        schedseed["scheduler-seed"]
    end

    subgraph Background["Background Agents (launchd)"]
        poller["Usage Poller (60s)"]
        scheduler["Job Scheduler (120s)"]
        sbstart["SwiftBar Autostart (login)"]
    end

    subgraph State["Runtime State (~/.eco/)"]
        snapshots["snapshots/"]
        usagejson["current/usage.json"]
        notifyjson["state/notify.json"]
        jobsyaml["queue/jobs.yaml"]
        alertruns["alert-runs/"]
    end

    subgraph External["External Services"]
        claude["Claude Code"]
        gemini["Gemini CLI"]
        codex["Codex CLI"]
        ollama["Ollama"]
        mcp["MCP Servers"]
        docker["Docker"]
    end

    Terminal --> eco
    SwiftBar --> commander

    eco --> Recipes
    eco --> commander
    eco --> scheduler
    eco --> alerts

    Recipes --> State
    Recipes --> External

    poller --> usagejson
    poller --> notifyjson
    scheduler --> jobsyaml
    scheduler --> notifyjson
    scheduler --> External

    commander --> snapshots
    commander --> usagejson
    alerts --> alertruns

    sbstart --> SwiftBar
```

## Source References

| Component | Source |
|-----------|--------|
| CLI router | [`src/bin/eco`](../../src/bin/eco) |
| SwiftBar widget | [`src/bin/eco-commander.15s.sh`](../../src/bin/eco-commander.15s.sh) |
| Recipe library | [`src/recipes/`](../../src/recipes/) |
| Poller | [`src/poller/`](../../src/poller/) |
| Scheduler | [`src/scheduler/`](../../src/scheduler/) |

**Related docs:** [Architecture](../architecture.md) · [README](../../README.md) · [ADR 0002](../adr/0002-bash-implementation.md) · [ADR 0004](../adr/0004-usage-monitor-python-carveout.md) · [ADR 0005](../adr/0005-job-scheduler.md)
