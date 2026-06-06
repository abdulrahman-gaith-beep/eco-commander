# LaunchAgent Best Practices

How eco-commander applies Apple's launchd guidelines for always-on background
agents. Based on `man launchd.plist(5)`, Apple's Daemons and Services
Programming Guide, WWDC 2018/2022, and a survey of how 1Password, Spotify,
Docker Desktop, and Homebrew Services ship their agents.

## TL;DR — required settings for every agent

| Concern | Best practice | Key | Poller | Scheduler | SwiftBar |
|---------|---------------|-----|--------|-----------|---------|
| Per-user (not root) | LaunchAgent in `~/Library/LaunchAgents/` | (path) | ✓ | ✓ | ✓ |
| Run at login | `RunAtLoad: true` | `RunAtLoad` | ✓ | ✓ | ✓ |
| Restart on crash only | Dict form of KeepAlive | `KeepAlive: {Crashed: true, SuccessfulExit: false}` | — | — | ✓ |
| No restart on clean exit | `KeepAlive: false` for one-shot jobs | `KeepAlive` | ✓ | ✓ | — |
| Throttle restart loops | ≥ 30s between crash-respawns | `ThrottleInterval` | 30s | 60s | 30s |
| Background CPU/IO | Low-priority QoS | `ProcessType: Background` | ✓ | ✓ | — |
| CPU niceness | Yield to foreground | `Nice: 5` | ✓ | ✓ | — |
| Low-priority disk IO | Don't fight foreground | `LowPriorityIO: true` | ✓ | ✓ | — |
| Periodic cadence | Poller: 60s; Scheduler: 120s | `StartInterval` | 60s | 120s | — |
| Graceful shutdown | Allow clean exit before SIGKILL | `ExitTimeOut` | 30s | 900s | — |
| Log to disk | Capture stdout + stderr | `StandardOut/ErrorPath` | ✓ | ✓ | ✓ |

## Plist templates

Templates live at `scripts/launchagents/`. Placeholders like `__ECO_HOME__`
and `__SRC_DIR__` are substituted by `scripts/install-launchagents.sh` at
install time.

### Usage poller (`com.eco-commander.usage-poller`)

```xml
<key>ProgramArguments</key>
<array>
  <string>__PYTHON_BIN__</string>
  <string>__POLLER_PATH__</string>
</array>
<key>WorkingDirectory</key><string>__SRC_DIR__</string>
<key>EnvironmentVariables</key>
<dict>
  <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  <key>ECO_HOME</key><string>__ECO_HOME__</string>
  <key>PYTHONPATH</key><string>__SRC_DIR__</string>
</dict>
<key>StartInterval</key><integer>60</integer>
<key>KeepAlive</key><false/>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Background</string>
<key>Nice</key><integer>5</integer>
<key>LowPriorityIO</key><true/>
<key>LowPriorityBackgroundIO</key><true/>
<key>ThrottleInterval</key><integer>30</integer>
<key>ExitTimeOut</key><integer>30</integer>
```

Logs: `__ECO_HOME__/logs/usage-poller.{out,err}.log`

### Scheduler (`com.eco-commander.scheduler`)

```xml
<key>ProgramArguments</key>
<array>
  <string>__PYTHON_BIN__</string>
  <string>-m</string>
  <string>scheduler.dispatcher</string>
</array>
<key>WorkingDirectory</key><string>__SRC_DIR__</string>
<key>EnvironmentVariables</key>
<dict>
  <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  <key>PYTHONPATH</key><string>__SRC_DIR__</string>
  <key>ECO_HOME</key><string>__ECO_HOME__</string>
  <key>ECO_MAX_JOBS_PER_TICK</key><string>1</string>
</dict>
<key>StartInterval</key><integer>120</integer>
<key>KeepAlive</key><false/>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Background</string>
<key>Nice</key><integer>5</integer>
<key>LowPriorityIO</key><true/>
<key>LowPriorityBackgroundIO</key><true/>
<key>ThrottleInterval</key><integer>60</integer>
<key>ExitTimeOut</key><integer>900</integer>
```

`ExitTimeOut: 900` gives a running job up to 15 minutes to finish before
launchd sends SIGKILL on the next scheduled tick.

Logs: `__ECO_HOME__/logs/scheduler.{out,err}.log`

### SwiftBar autostart (`com.eco-commander.swiftbar`)

```xml
<key>ProgramArguments</key>
<array>
  <string>/usr/bin/open</string>
  <string>-gja</string>
  <string>/Applications/SwiftBar.app</string>
</array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key>
<dict>
  <key>SuccessfulExit</key><false/>
  <key>Crashed</key><true/>
</dict>
<key>ThrottleInterval</key><integer>30</integer>
```

The dict form of `KeepAlive` means launchd relaunches SwiftBar only after a
crash — not after the user intentionally quits it.

Logs: `__ECO_HOME__/logs/swiftbar-autostart.{out,err}.log`

## What we deliberately don't do

### We don't use SMAppService (macOS 13+ API)

Apple recommends `SMAppService` for distributable apps that need to appear
in System Settings → Login Items. We don't use it because:

- It requires a **bundled app** with code signing. Our agents are plain
  `python3` and `bash` scripts, not app bundles.
- The underlying mechanism is still a plist + launchd — no efficiency gain.
- The user is the developer; "manage in GUI" adds no value over
  `launchctl bootout` / `bootstrap`.

If eco-commander were ever shipped as a distributable app, the LoginItem
helper pattern via `SMAppService` would be the right call.

### We don't use LaunchDaemon

LaunchDaemons run as root before user login. They are for system services.
Our agents are per-user processes with per-user data. `LaunchAgent` is correct.

### We don't poll faster than 60 seconds (poller) or 120 seconds (scheduler)

- The widget re-renders every 15s but reads a static JSON file — no network
  cost at render time.
- Quota meters change on minute-to-hour timescales. 60s is ample.
- Sub-10s polling on Apple Silicon defeats Background QoS scheduling and
  burns efficiency-core budget unnecessarily.

### We don't use `KeepAlive: true` on the poller or scheduler

`KeepAlive: true` would relaunch the agent immediately after every exit,
creating a tight loop when the script is a one-shot job. `StartInterval`
respawns on the correct cadence; `KeepAlive: false` lets launchd wait for
the next scheduled interval after a crash.

## Energy efficiency

1. **`ProcessType: Background`** — allows the OS to schedule on
   high-efficiency cores and defer on battery / Low Power Mode.
2. **`LowPriorityIO: true`** — disk reads/writes happen below foreground
   app priority.
3. **`Nice: 5`** — CPU priority below interactive processes.
4. **Sleep awareness** — launchd defers `StartInterval` jobs during sleep
   and catches up on wake. No manual wake-lock needed.
5. **No persistent connections** — the poller opens network connections,
   reads, and closes. No keep-alive idle handles.
6. **Low Power Mode** — macOS automatically degrades Background QoS in LPM.

## Log discipline

- All output goes through `StandardOut/ErrorPath` so launchd captures it
  even if the script crashes before its own logger initializes.
- Log rotation is registered via `scripts/install-log-rotation.sh`
  (writes to `/etc/newsyslog.d/eco-commander.conf`; requires sudo once).
  Logs rotate at ≥ 1 MB; up to 5 compressed archives retained.
- Secrets are never written to logs. The poller logs only exception class
  names, never raw OAuth token contents.

## Survivability checklist

| Scenario | Behavior |
|----------|---------|
| Reboot | `RunAtLoad: true` resumes at next login |
| User logout | Agent unloads; returns at next login |
| User Cmd-Q on SwiftBar | `KeepAlive {SuccessfulExit: false}` prevents relaunch on clean quit |
| App moved / uninstalled | `open -gja /Applications/SwiftBar.app` fails fast; installer skips registration |
| OS sleep/wake | launchd handles time skew on `StartInterval` |
| Network outage | All poller calls are wrapped in try/except; failure is recorded and next cycle retries |
| Missing deps | PATH preamble + healthcheck catches this before a silent failure |
| Disk full | JSON writes use `tempfile.mkstemp` + `os.replace`; on disk-full the write fails and the previous JSON remains valid |

## Verifying the install

```bash
# Healthcheck (default-safe checks; opt in to live macOS/runtime surfaces via env)
scripts/healthcheck.sh

# Inspect launchd job state
launchctl list | grep eco

# Manually trigger the poller once
launchctl kickstart -k gui/$(id -u)/com.eco-commander.usage-poller

# Manually trigger a scheduler tick
python -m scheduler.cli run-once

# Validate a plist before loading
plutil -lint scripts/launchagents/com.eco-commander.usage-poller.plist
```

## Installing log rotation

```bash
# One-time, requires sudo
scripts/install-log-rotation.sh
```

Writes `/etc/newsyslog.d/eco-commander.conf`. After install, macOS's daily
`newsyslog` cron rotates logs ≥ 1 MB and keeps up to 5 compressed archives.

## Sources

- Apple, `man launchd.plist(5)` — authoritative key reference
- Apple, "Daemons and Services Programming Guide" (archived; launchd sections remain authoritative)
- WWDC 2018, "Reduce Memory Use" — process types and QoS classes
- WWDC 2022 session 10081, "What's new in privacy" — SMAppService for app bundles
- `man newsyslog.conf(5)` — log rotation format
- BSD `man 2 setpriority` — CPU nice values

## Related

- [Usage Monitor](./usage-monitor.md) — poller LaunchAgent setup and log paths
- [Scheduler](./scheduler.md) — scheduler LaunchAgent setup
- [Architecture overview](../architecture.md)
- [Environment variables reference](../reference/environment-variables.md)
