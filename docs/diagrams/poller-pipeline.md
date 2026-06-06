# Poller Data Pipeline

Detailed view of `src/poller/main.py` — the 60-second usage collection cycle.

```mermaid
flowchart TB
    subgraph Main["main.py entry"]
        Start["Load prev usage.json\n(for delta computation)"]
    end

    subgraph Claude["Claude Collection"]
        CCheck{"server_truth\nenabled?"}
        COAuth["claude_oauth.py\n(OAuth API)"]
        CJSONL["claude.py\n(collect_multi → JSONL)"]
        COAuthFail{"OAuth\nresult OK?"}
        CTransient{"Transient\nfailure?"}
        CReuse["Reuse prev cycle's\nOAuth result (stale=true)"]
        CFallback["Fall back to JSONL"]
        CAugment["Augment OAuth with JSONL\n(per_account, token splits)"]
    end

    subgraph Gemini["Gemini Collection"]
        GCollect["gemini.py\n(quota API — always runs)"]
    end

    subgraph Codex["Codex Collection"]
        XCheck{"server_truth\nenabled?"}
        XOAuth["codex_oauth.py\n(OAuth API)"]
        XJSONL["codex.py\n(JSONL parsing)"]
        XOAuthFail{"OAuth\nresult OK?"}
        XTransient{"Transient\nfailure?"}
        XReuse["Reuse prev cycle's\nOAuth result"]
        XFallback["Fall back to JSONL"]
        XAugment["Augment OAuth with JSONL\n(token splits)"]
    end

    subgraph Enrichment["Enrichment"]
        Stamp["accounts.py\nstamp plan/account context"]
        PerTool["Atomic write per-tool JSONs\n(usage-claude/gemini/codex.json)"]
        Alts["alternatives.py\n(model suggestions)"]
        Merge["Merge into usage.json\n+ ts, duration_ms, version"]
        ValBlock["value.py\n(USD pricing)"]
        CommBlock["comments.py\n(burn-rate commentary,\ngated by ECO_COMMENTS=1)"]
    end

    subgraph Output["Output"]
        UsageJSON["Atomic write\n~/.eco/current/usage.json"]
        NotifyEval["notify.py\n(evaluate thresholds)"]
        NotifyJSON["~/.eco/state/notify.json\n(meter state for scheduler)"]
        MacNotif["macOS notification\n(osascript)"]
        PrivateLog["~/.eco/logs/poller.log\n(sanitized errors, 0600)"]
    end

    %% Claude flow
    Start --> CCheck
    CCheck -->|Yes| COAuth
    CCheck -->|No| CJSONL
    COAuth --> COAuthFail
    COAuthFail -->|Yes| CAugment
    COAuthFail -->|No| CTransient
    CTransient -->|Yes + prev exists| CReuse
    CTransient -->|No or no prev| CFallback
    CFallback --> CAugment
    CReuse --> CAugment

    %% Gemini flow
    Start --> GCollect

    %% Codex flow
    Start --> XCheck
    XCheck -->|Yes| XOAuth
    XCheck -->|No| XJSONL
    XOAuth --> XOAuthFail
    XOAuthFail -->|Yes| XAugment
    XOAuthFail -->|No| XTransient
    XTransient -->|Yes + prev exists| XReuse
    XTransient -->|No or no prev| XFallback
    XFallback --> XAugment
    XReuse --> XAugment

    %% Enrichment
    CAugment --> Stamp
    GCollect --> Stamp
    XAugment --> Stamp
    CJSONL --> Stamp
    XJSONL --> Stamp
    Stamp --> PerTool
    Stamp --> Alts
    PerTool -.->|"side-write (not piped)"| Merge
    Alts --> Merge
    Merge --> ValBlock
    ValBlock --> CommBlock
    CommBlock --> UsageJSON

    %% Notify
    UsageJSON --> NotifyEval
    NotifyEval --> NotifyJSON
    NotifyEval -->|threshold hit| MacNotif

    %% Error handling (any collector failure)
    COAuth -.->|exception| PrivateLog
    CJSONL -.->|exception| PrivateLog
    GCollect -.->|exception| PrivateLog
    XOAuth -.->|exception| PrivateLog
    XJSONL -.->|exception| PrivateLog
```

## Source References

| Component | Source |
|-----------|--------|
| Entry point | [`src/poller/main.py`](../../src/poller/main.py) |
| Claude JSONL | [`src/poller/claude.py`](../../src/poller/claude.py) |
| Claude OAuth | [`src/poller/claude_oauth.py`](../../src/poller/claude_oauth.py) |
| Gemini collector | [`src/poller/gemini.py`](../../src/poller/gemini.py) |
| Codex JSONL | [`src/poller/codex.py`](../../src/poller/codex.py) |
| Codex OAuth | [`src/poller/codex_oauth.py`](../../src/poller/codex_oauth.py) |
| Account stamping | [`src/poller/accounts.py`](../../src/poller/accounts.py) |
| Alternatives | [`src/poller/alternatives.py`](../../src/poller/alternatives.py) |
| USD pricing | [`src/poller/value.py`](../../src/poller/value.py) |
| Burn-rate comments | [`src/poller/comments.py`](../../src/poller/comments.py) |
| Notification eval | [`src/poller/notify.py`](../../src/poller/notify.py) |
| LaunchAgent plist | [`scripts/launchagents/`](../../scripts/launchagents/) |

**Related docs:** [Architecture](../architecture.md) · [Usage Monitor](../subsystems/usage-monitor.md) · [ADR 0004](../adr/0004-usage-monitor-python-carveout.md) · [Data Model](../reference/data-model.md)

