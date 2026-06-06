# Filesystem Layout — `~/.eco/` Ownership Map

Runtime directory tree with writer attribution and file permissions.

```mermaid
flowchart TB
    subgraph ECO["~/.eco/ (ECO_HOME)"]

        subgraph Current["current/ → symlink to latest snapshot"]
            StateJSON["state.json\n📝 snapshot.sh\n📖 widget"]
            UsageJSON["usage.json\n📝 poller/main.py\n📖 widget"]
            UsageClaude["usage-claude.json\n📝 poller/main.py\n📖 widget"]
            UsageGemini["usage-gemini.json\n📝 poller/main.py\n📖 widget"]
            UsageCodex["usage-codex.json\n📝 poller/main.py\n📖 widget"]
            Dashboard["dashboard.html\n📝 dashboard-refresh.sh\n📖 browser"]
        end

        subgraph Snapshots["snapshots/ (immutable)"]
            SnapDir["&lt;UTC ISO&gt;/\n📝 snapshot.sh\nNever modified after creation"]
        end

        subgraph State["state/ (0700)"]
            NotifyJSON["notify.json (0600)\n📝 poller/notify.py\n📖 scheduler/routing.py\n📝 scheduler/dispatcher.py\n   (stamps last_fired_ts)"]
            ActiveAccounts["active-accounts.json (0600)\n📝 account-swap.sh\n📖 widget"]
        end

        subgraph QueueDir["queue/ (0700)"]
            JobsYAML["jobs.yaml (0600)\n📝 scheduler/queue.py\n📖 scheduler/dispatcher.py\n📝 scheduler/cli.py"]
            JobLogs["logs/&lt;job-id&gt;/ (0700)\nstdout/stderr (0600)\n📝 scheduler/adapters/*"]
        end

        subgraph Logs["logs/"]
            PollerOut["usage-poller.out.log\n📝 launchd stdout"]
            PollerErr["usage-poller.err.log\n📝 launchd stderr"]
            PollerPrivate["poller.log (0600)\n📝 poller/main.py\n(sanitized errors only)"]
            SchedOut["scheduler.out.log\n📝 launchd stdout"]
            SchedErr["scheduler.err.log\n📝 launchd stderr"]
            SBLog["swiftbar-autostart.*.log\n📝 launchd"]
        end

        subgraph AuthSnaps["auth-snapshots/ (0700)"]
            AuthClaude["claude/&lt;slug&gt;/keychain.b64 (0600)"]
            AuthGemini["gemini/&lt;slug&gt;/oauth_creds.json (0600)"]
            AuthCodex["codex/&lt;slug&gt;/auth.json (0600)"]
        end

        subgraph FixPlans["fix-plans/"]
            FPDir["&lt;issue-id&gt;/\n📝 eco-alerts.sh delegate-fix"]
        end

        subgraph AlertRuns["alert-runs/"]
            ARDir["&lt;timestamp&gt;/\n📝 eco-alerts.sh run-logged"]
        end

        ConfigJSON["config.json (optional)\n📖 poller/discovery.py\n📖 common/config.py\n(plans, accounts, server_truth)"]

        subgraph Bin["bin/ real dir; file symlinks to src/bin/"]
            EcoCLI["eco"]
            Commander15["eco-commander.15s.sh"]
            Alerts["eco-alerts.sh"]
        end

        subgraph Recipes["recipes/ real dir; file symlinks to src/recipes/"]
            RecipeOutputs["_outputs/&lt;recipe&gt;/&lt;ts&gt;/\n📝 individual recipes"]
        end
    end

    style Current fill:#e8f5e9,stroke:#4caf50
    style State fill:#e3f2fd,stroke:#2196f3
    style QueueDir fill:#e3f2fd,stroke:#2196f3
    style AuthSnaps fill:#fce4ec,stroke:#e91e63
    style Logs fill:#fff3e0,stroke:#ff9800
```

## Legend

| Symbol | Meaning |
|--------|---------|
| 📝 | **Writer** — the subsystem that creates/updates this file |
| 📖 | **Reader** — subsystem(s) that consume this file |
| `(0600)` | Owner-only read/write |
| `(0700)` | Owner-only access on directory |

## Writer Color Key

| Color | Subsystem |
|-------|-----------|
| 🟢 Green | Snapshot + Poller (data producers) |
| 🔵 Blue | Scheduler (job dispatch) |
| 🔴 Pink | Account swap (credentials) |
| 🟠 Orange | LaunchAgent logs |

## Source References

| Component | Source |
|-----------|--------|
| Install script | [`scripts/install.sh`](../../scripts/install.sh) |
| Config loader | [`src/common/config.py`](../../src/common/config.py) |
| Discovery flags | [`src/poller/discovery.py`](../../src/poller/discovery.py) |

**Related docs:** [Architecture](../architecture.md) · [Installation](../getting-started/installation.md) · [Data Model](../reference/data-model.md) · [Security Model](../operations/security-model.md) · [Environment Variables](../reference/environment-variables.md)
