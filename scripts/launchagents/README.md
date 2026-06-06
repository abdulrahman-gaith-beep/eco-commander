# scripts/launchagents/ — macOS LaunchAgent Templates

Plist templates for the three eco-commander background services.
Installed by [`install-launchagents.sh`](../install-launchagents.sh) and removed by
[`uninstall-launchagents.sh`](../uninstall-launchagents.sh).

## Template Variables

The plist files contain placeholder strings that are replaced at install time:

| Variable | Replaced With | Used In |
|----------|--------------|---------|
| `__POLLER_PATH__` | Absolute path to `src/poller/main.py` | usage-poller.plist |
| `__SRC_DIR__` | Absolute path to `src/` directory | usage-poller.plist, scheduler.plist |
| `__ECO_HOME__` | `$ECO_HOME` (default: `~/.eco`) | All three plists |
| `__PYTHON_BIN__` | Supported Python 3.10-3.13 runner selected by `install-launchagents.sh` | usage-poller.plist, scheduler.plist |

## Rendering Mechanism

`install-launchagents.sh` uses an inline Python script to replace template vars
and HTML-escape the values (to keep the XML valid). The rendered plist is:

1. Written to a temporary file in `$LA_DST/`
2. Validated with `plutil -lint` (or `plistlib.load()` fallback)
3. Verified that the `Label` key matches the expected value
4. Atomically moved to the final destination

## Agents

### `com.eco-commander.usage-poller.plist`

- **Purpose:** Run the usage poller every 60 seconds
- **Label:** `com.eco-commander.usage-poller`
- **Interval:** 60s (`StartInterval`)
- **Logs:** `$ECO_HOME/logs/usage-poller.{out,err}.log`

### `com.eco-commander.scheduler.plist`

- **Purpose:** Run the scheduler dispatcher every 120 seconds
- **Label:** `com.eco-commander.scheduler`
- **Interval:** 120s (`StartInterval`)
- **Install modes:** `ECO_SCHEDULER_AUTO_LOAD=1` (install + load) or
  `ECO_SCHEDULER_PERSIST=1` (install only, don't load)

### `com.eco-commander.swiftbar.plist`

- **Purpose:** Keep SwiftBar.app running (KeepAlive on crash)
- **Label:** `com.eco-commander.swiftbar`
- **Interval:** N/A (KeepAlive, not periodic)
- **Condition:** Only installed if `/Applications/SwiftBar.app` exists

## Overriding the Install Directory

By default, plists are installed to `~/Library/LaunchAgents`. Override with:

```bash
ECO_LAUNCHAGENTS_DIR=/path/to/custom/dir bash scripts/install-launchagents.sh
```
