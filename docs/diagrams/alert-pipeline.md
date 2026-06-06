# Alert Pipeline

How `src/bin/eco-alerts.sh` routes raw findings through live verification and
into one of four states (active, evidence, triage, resolved) before dispatching
a fix action.

```mermaid
flowchart LR
    subgraph Sources["Alert Sources"]
        Snapshot["Snapshot probes"]
        Live["Live probes\n(HTTP, process)"]
    end

    subgraph Verification["Verification Pipeline"]
        Raw["Raw finding"]
        Verify{"Live verifier\nexists?"}
        RunVerify["Run live check"]
        Result{"Issue confirmed?"}
    end

    subgraph States["Alert States"]
        Active["🔴 active\n(confirmed real)"]
        Evidence["🟡 evidence\n(needs rerun)"]
        Triage["🟠 triage\n(no verifier)"]
        Resolved["🟢 resolved\n(cleared)"]
    end

    subgraph Actions["Fix Actions"]
        SafeFix["Safe/idempotent\n(direct command)"]
        BoundedFix["Bounded ops\n(run-logged)"]
        ComplexFix["Complex code\n(delegate-fix → Gemini Pro)"]
    end

    Snapshot --> Raw
    Live --> Raw
    Raw --> Verify

    Verify -->|Yes| RunVerify
    Verify -->|No| Triage

    RunVerify --> Result
    Result -->|Yes| Active
    Result -->|No| Resolved

    Active --> SafeFix
    Active --> BoundedFix
    Active --> ComplexFix
    Evidence --> BoundedFix
    Triage --> ComplexFix
```

## Source References

| Component | Source |
|-----------|--------|
| Alert engine | [`src/bin/eco-alerts.sh`](../../src/bin/eco-alerts.sh) |
| BATS tests | [`tests/bats/06_eco_alerts.bats`](../../tests/bats/06_eco_alerts.bats) |

**Related docs:** [Architecture](../architecture.md) · [Alert System](../subsystems/alerts.md) · [Widget Health](../subsystems/widget-health.md) · [Runbook §1](../operations/runbook.md)
