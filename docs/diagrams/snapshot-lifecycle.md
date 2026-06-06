# Snapshot Lifecycle

How snapshots are created and consumed by the ecosystem.

## Write Path

```mermaid
flowchart TB
    subgraph Trigger["Snapshot Triggers"]
        Manual["eco snapshot"]
        WidgetAction["Widget / alert action\nfix-snapshot-timeout"]
    end

    subgraph Recipe["src/recipes/snapshot.sh"]
        direction TB
        CreateDir["mkdir ~/.eco/snapshots/2026-04-24T00-55Z/"]

        subgraph Prompts["Prompt library resolution"]
            Explicit["$ECO_AUDIT_ROOT/prompts"]
            Runtime["~/.eco/ecosystem-audit/prompts"]
            Examples["examples/snapshot-prompts/"]
        end

        RunLayers["Run each prompt layer\nvia gem-smart or gemini\n(timeout: GEMINI_LAYER_TIMEOUT_SEC)"]
        Assemble["Assemble state.json\nmap.md\ndashboard.html"]
        Manifest["Write raw/prompt-names.txt"]

        CreateDir --> Prompts
        Prompts --> RunLayers
        RunLayers --> Manifest
        RunLayers --> Assemble

        Manifest --> Link
        Assemble --> Link
    end

    Link["Atomic Symlink\nln -sfn ~/.eco/snapshots/... ~/.eco/current"]

    Trigger --> Recipe
```

## Read Path (Consumers)

```mermaid
flowchart LR
    subgraph State["~/.eco/current/state.json"]
        direction TB
        StateData["snapshot_id\ngenerated_at\nlayers\nalert_count\ngate_status"]
    end

    subgraph Consumers["Subsystems"]
        Widget["SwiftBar Widget\n(Renders snapshot age/issues)"]
        Alerts["eco-alerts.sh doctor\n(Verifies findings)"]
        Dashboard["Dashboard view\n(Opens dashboard.html)"]
    end

    State --> Widget
    State --> Alerts
    State --> Dashboard

    note["📌 Snapshots are IMMUTABLE.\nOld snapshots are never updated,\nonly garbage-collected."]
    State -.-> note
```

## Source References

| Component | Source |
|-----------|--------|
| Snapshot recipe | [`src/recipes/snapshot.sh`](../../src/recipes/snapshot.sh) |
| BATS tests | [`tests/bats/recipes/`](../../tests/bats/recipes/) |

**Related docs:** [Architecture](../architecture.md) · [Snapshots](../subsystems/snapshots.md) · [ADR 0003](../adr/0003-snapshot-immutability.md) · [Data Model](../reference/data-model.md)
