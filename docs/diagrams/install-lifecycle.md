# Install Lifecycle

Installation, setup, and teardown flow for eco-commander.

## Full Bootstrap

```mermaid
flowchart TB
    subgraph Bootstrap["make bootstrap (scripts/bootstrap.sh)"]
        direction TB
        B1["Check prerequisites\n(bash 4+, python3, jq)"]
        B1 --> B2["make venv\n(scripts/setup-venv.sh)"]
        B2 --> B3["make install\n(scripts/install.sh)"]
        B3 --> B4["make install-hooks\n(scripts/install-hooks.sh)"]
        B4 --> B5{"ECO_INSTALL_LAUNCHAGENTS=1?"}
        B5 -->|Yes| B6["scripts/install-launchagents.sh"]
        B5 -->|No| B7["Skip LaunchAgents\n(manual install later)"]
    end
```

## Install Detail

```mermaid
flowchart TB
    subgraph Install["make install (scripts/install.sh)"]
        I1["Create ~/.eco/bin and ~/.eco/recipes\n(mode 0700)"]
        I1 --> I2["Symlink src/bin/* → ~/.eco/bin/\n(eco, eco-commander.15s.sh,\neco-alerts.sh, ai-clear.sh)"]
        I2 --> I3["Symlink src/recipes/* → ~/.eco/recipes/"]
        I3 --> I4["Symlink eco-commander.15s.sh\n→ ~/Library/.../SwiftBar/Plugins/"]
        I4 --> I5{"ECO_INSTALL_LAUNCHAGENTS=1?"}
        I5 -->|No| I6["Skip LaunchAgents"]
    end

    subgraph LaunchAgents["scripts/install-launchagents.sh"]
        LA1["Read plist templates from\nscripts/launchagents/*.plist"]
        LA1 --> LA2["Render templates:\n__POLLER_PATH__ → src/poller/main.py\n__SRC_DIR__ → src/\n__ECO_HOME__ → ~/.eco\n__PYTHON_BIN__ → supported Python"]
        LA2 --> LA3["Copy rendered plists to\n~/Library/LaunchAgents/"]
        LA3 --> LA4["plutil -lint each plist"]
        LA4 --> LA5["launchctl bootstrap\nusage-poller"]
        LA4 --> LA6{"ECO_SCHEDULER_AUTO_LOAD=1?"}
        LA6 -->|Yes| LA7["render + bootstrap\nscheduler"]
        LA6 -->|No| LA8{"ECO_SCHEDULER_PERSIST=1?"}
        LA8 -->|Yes| LA9["render scheduler plist\nwithout loading"]
        LA8 -->|No| LA10["skip scheduler"]
        LA4 --> LA11{"SwiftBar.app exists?"}
        LA11 -->|Yes| LA12["render + bootstrap\nswiftbar autostart"]
        LA11 -->|No| LA13["skip swiftbar autostart"]
    end

    subgraph LogRotation["Optional: scripts/install-log-rotation.sh (sudo)"]
        LR1["Copy scripts/log-rotate.conf\n→ /etc/newsyslog.d/eco-commander.conf"]
        LR1 --> LR2["Rotation: ≥1 MB daily\n5 compressed archives retained"]
    end

    I5 -->|Yes| LaunchAgents
```

## Uninstall

```mermaid
flowchart TB
    subgraph Uninstall["make uninstall"]
        U1["scripts/uninstall.sh"]
        U2["scripts/uninstall-launchagents.sh"]
        U1 --> U3["Remove SwiftBar plugin symlink"]
        U1 --> U4["Remove ~/.eco/bin/ symlinks\n(preserves data directories)"]
        U1 --> U5["Remove ~/.eco/recipes/ symlinks"]
        U2 --> U6["launchctl bootout installed\neco-commander agents"]
        U2 --> U7["Remove plists from\n~/Library/LaunchAgents/"]
    end

    Note["📌 ~/.eco/current/, snapshots/,\nstate/, queue/, logs/, config.json\nare ALL preserved on uninstall"]
```

## LaunchAgent Agents

```mermaid
flowchart LR
    subgraph Agents["Supported LaunchAgent labels"]
        Poller["com.eco-commander.usage-poller\nStartInterval: 60s\nselected Python src/poller/main.py"]
        Scheduler["com.eco-commander.scheduler\nStartInterval: 120s\nopt-in; selected Python -m scheduler.dispatcher"]
        SwiftBar["com.eco-commander.swiftbar\nRunAtLoad only\ninstalled when SwiftBar.app exists"]
    end

    subgraph Settings["Common plist settings"]
        S1["ProcessType: Background"]
        S2["Nice: 5"]
        S3["LowPriorityIO: true"]
        S4["ThrottleInterval: 30"]
        S5["ExitTimeOut: 30"]
        S6["Logs → ~/.eco/logs/"]
    end

    Agents --- Settings
```

## Source References

| Component | Source |
|-----------|--------|
| Bootstrap | [`scripts/bootstrap.sh`](../../scripts/bootstrap.sh) |
| Install | [`scripts/install.sh`](../../scripts/install.sh) |
| Uninstall | [`scripts/uninstall.sh`](../../scripts/uninstall.sh) |
| LaunchAgents | [`scripts/install-launchagents.sh`](../../scripts/install-launchagents.sh) |
| Plist templates | [`scripts/launchagents/`](../../scripts/launchagents/) |
| Log rotation | [`scripts/install-log-rotation.sh`](../../scripts/install-log-rotation.sh) |
| Healthcheck | [`scripts/healthcheck.sh`](../../scripts/healthcheck.sh) |

`scripts/healthcheck.sh` is an operator validation command, not an automatic
step in `make install`.

**Related docs:** [Architecture](../architecture.md) · [Installation](../getting-started/installation.md) · [Runbook §6](../operations/runbook.md) · [Filesystem Layout](filesystem-layout.md)
