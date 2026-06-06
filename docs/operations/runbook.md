# Operational Runbook

> Purpose: step-by-step procedures for common operational scenarios, verified
> against the scripts and source in this repository. For symptom-first
> troubleshooting see [`../getting-started/troubleshooting.md`](../getting-started/troubleshooting.md).

**Agent boundary:** commands in this runbook that read `~/.eco` logs or runtime
JSON are manual operator steps. Do not paste raw output into agents or external
tools — provide a short redacted excerpt or summary instead.

Commands that reference `scripts/` or `src/` assume your shell is in the
eco-commander checkout root.

## Procedure index

| # | Scenario |
|---|----------|
| 1 | System is degraded — general recovery |
| 2 | Usage poller is not updating |
| 3 | Scheduler is stuck / not dispatching |
| 4 | Gemini OAuth expired |
| 5 | SwiftBar not showing widget |
| 6 | Full reinstall from clean state |
| 7 | Rotating CLI accounts |
| 8 | Adding new jobs to the scheduler |
| 9 | Checking system health after updates |
| 10 | Emergency: poller or scheduler crash-looping |

---

## 1. System is degraded — general recovery

**Symptom:** Widget shows stale data, alerts fire unexpectedly, or the status
icon is missing.

**Diagnosis:**

```bash
# Show ecosystem state
eco status

# Self-test installation (reports optional LaunchAgents/data and checks
# required CLI/Python wiring)
eco doctor

# Deep alert investigation
~/.eco/bin/eco-alerts.sh doctor
```

**Steps:**

```bash
# Take a fresh snapshot
eco do snapshot

# Run repository health check (widget, lint, runtime wiring)
~/.eco/bin/eco-alerts.sh repo-health

# Review recent alert-action logs (manual operator only)
ls -lt ~/.eco/alert-runs/ | head -5
```

**Verification:** `eco status` shows a green icon; `eco doctor` reports all required checks passed.

---

## 2. Usage poller is not updating

**Symptom:** Widget shows `usage:—` or stale data with a ⚠ marker.

**Diagnosis:**

```bash
# Confirm the LaunchAgent is loaded (label: com.eco-commander.usage-poller)
launchctl list | grep com.eco-commander.usage-poller
```

**Steps:**

```bash
# If not loaded, reinstall all LaunchAgents
bash scripts/install-launchagents.sh

# Force a manual poll run
python3 src/poller/main.py

# Manual operator only — check error log for details
tail -50 ~/.eco/logs/usage-poller.err.log
```

**Verification:**

```bash
# usage.json should be refreshed (mtime within the last 90 s)
stat -f "%Sm %N" ~/.eco/current/usage.json
```

---

## 3. Scheduler is stuck / not dispatching

**Symptom:** Jobs remain `pending` or `gated_by_quota` indefinitely.

**Diagnosis:**

```bash
# Check queue and meter state
eco scheduler status

# Confirm the LaunchAgent is loaded (label: com.eco-commander.scheduler)
launchctl list | grep com.eco-commander.scheduler

# Manual operator only — check error log
tail -50 ~/.eco/logs/scheduler.err.log
```

**Steps:**

```bash
# Force one manual tick
eco scheduler run-once

# If an attempted job fails, run-once exits non-zero and prints the failed
# attempt in its JSON summary; inspect that summary before retrying.

# Inspect meter availability in machine-readable form
eco scheduler status --json | python3 -m json.tool

# If a specific job is stuck in 'running', inspect its attempt log
eco scheduler tail --id <job-id>

# Stale 'running' jobs are reset automatically at each tick start, but you
# can trigger a reset immediately by running another tick
eco scheduler run-once
```

**Verification:** `eco scheduler status` shows jobs advancing from `pending` or
`gated_by_quota` to `completed`/`failed`. The LaunchAgent fires every 120 s
(StartInterval in `com.eco-commander.scheduler`).

---

## 4. Gemini OAuth expired

**Symptom:** Poller output shows "OAuth expired"; Gemini usage shows "setup needed".

**Diagnosis:**

```bash
# Manual operator only
tail -20 ~/.eco/logs/usage-poller.err.log
```

**Steps:**

```bash
# Re-authenticate by running the Gemini CLI interactively once
gemini

# The poller auto-refreshes tokens on the next run (StartInterval = 60 s).
# To verify immediately, force a manual poll
python3 src/poller/main.py

# Manual operator only — confirm Gemini data is populated
cat ~/.eco/current/usage-gemini.json
```

**Verification:** Widget shows a numeric Gemini usage percentage instead of
"setup needed".

---

## 5. SwiftBar not showing widget

**Symptom:** SwiftBar menu bar item is missing or shows a default icon.

**Diagnosis:**

```bash
# Confirm SwiftBar is installed
ls /Applications/SwiftBar.app

# Confirm SwiftBar is running
pgrep -lf SwiftBar

# Confirm the plugin symlink is in place
ls -la ~/Library/Application\ Support/SwiftBar/Plugins/eco-commander.15s.sh
```

**Steps:**

```bash
# If SwiftBar is not installed, install it
brew install --cask swiftbar

# Reinstall eco-commander to restore the symlink and LaunchAgents
make uninstall && make install

# Test widget rendering manually (should print 🟢, 🟡, or 🔴)
~/.eco/bin/eco-commander.15s.sh --cli
```

**Verification:** A status icon (🟢/🟡/🔴) appears in the macOS menu bar.

---

## 6. Full reinstall from clean state

**Symptom:** Installation is corrupt, symlinks are dangling, or a major
repo update requires a fresh wiring.

**Diagnosis:**

```bash
scripts/doctor.sh
```

**Steps:**

```bash
# Remove symlinks installed by eco-commander (preserves ~/.eco data)
make uninstall

# Remove LaunchAgents
bash scripts/uninstall-launchagents.sh

# Fresh install
make install

# Install LaunchAgents; include ECO_SCHEDULER_AUTO_LOAD=1 to also
# load and enable the scheduler LaunchAgent
ECO_SCHEDULER_AUTO_LOAD=1 bash scripts/install-launchagents.sh
```

**Verification:**

```bash
eco status
scripts/healthcheck.sh
eco doctor
```

---

## 7. Rotating CLI accounts

**Symptom / use case:** Switching between personal and work accounts for
Claude, Gemini, or Codex without re-running an OAuth flow.

**Diagnosis:**

```bash
# List all registered account snapshots and which is currently active
eco account-swap list
```

**Steps:**

```bash
# Switch a tool to a previously registered account slug
eco account-swap gemini <slug>
eco account-swap codex  <slug>

# Claude swaps require explicit Keychain consent
eco account-swap claude <slug> --allow-keychain-prompt

# Register a new account (captures current live auth as a named snapshot)
eco account-swap gemini --register <slug>
eco account-swap codex  --register <slug>
eco account-swap claude --register <slug> --allow-keychain-prompt
```

> **Note:** Claude Keychain restore via `security -w` is disabled for safety
> because it exposes the secret in process arguments. If a Claude swap fails at
> restore, re-authenticate Claude Code manually (`claude login`).

**Verification:** `eco account-swap list` shows the new slug marked `(active)`.

---

## 8. Adding new jobs to the scheduler

**Symptom / use case:** Loading a YAML job file into the persistent queue.

**Steps:**

```bash
# Import jobs from a YAML file
eco scheduler add --file path/to/jobs.yaml

# Confirm they were added
eco scheduler status

# Run one tick to test dispatch
eco scheduler run-once

# If the scheduler LaunchAgent is not loaded, install it
ECO_SCHEDULER_AUTO_LOAD=1 bash scripts/install-launchagents.sh
```

**Verification:** `eco scheduler status` shows the new jobs with status
`pending`, `gated_by_quota`, `completed`, or `failed`; `run-once` and `drain`
surface failed attempts with a non-zero exit. The LaunchAgent fires the next
tick within 120 s.

---

## 9. Checking system health after updates

**Use case:** Run after pulling new code or modifying configuration.

**Steps:**

```bash
# Reinstall to pick up new scripts
make install

# Run all health checks
# Default run: 8 always-on checks (6 binary + snapshot + widget render).
# Add ECO_HEALTHCHECK_MACOS_SURFACES=1 for 9 additional plist/launchctl checks.
# Add ECO_HEALTHCHECK_LIVE_RUNTIME=1 for live usage.json freshness + log size.
scripts/healthcheck.sh

# Optionally run the full suite with all opt-in checks
ECO_HEALTHCHECK_MACOS_SURFACES=1 ECO_HEALTHCHECK_LIVE_RUNTIME=1 \
  scripts/healthcheck.sh

# Deeper installation self-diagnosis (symlinks, config.json, usage data age)
scripts/doctor.sh

# Lint
make lint

# Test
make test

# Alert system check
~/.eco/bin/eco-alerts.sh doctor
```

**Verification:** `scripts/healthcheck.sh` exits 0; `eco doctor` reports all
required checks passed.

---

## 10. Emergency: poller or scheduler crash-looping

**Symptom:** `launchctl list | grep eco` shows a rapidly incrementing PID or
non-zero last-exit code (launchd throttle indicator).

**Diagnosis:**

```bash
# Inspect launchd status for all eco agents
launchctl list | grep com.eco-commander
```

**Steps:**

```bash
# Stop the crash-looping agent (substitute scheduler label if needed)
launchctl bootout gui/$(id -u)/com.eco-commander.usage-poller
# or
launchctl bootout gui/$(id -u)/com.eco-commander.scheduler

# Manual operator only — read error logs to identify the root cause
tail -100 ~/.eco/logs/usage-poller.err.log
tail -100 ~/.eco/logs/scheduler.err.log

# Fix the underlying issue, then restart
launchctl bootstrap gui/$(id -u) \
  ~/Library/LaunchAgents/com.eco-commander.usage-poller.plist
```

**Verification:** `launchctl list | grep com.eco-commander.usage-poller`
shows a PID (not `-`) and a last-exit code of `0`.

---

## LaunchAgent labels

| Agent | Label | StartInterval |
|-------|-------|---------------|
| Usage poller | `com.eco-commander.usage-poller` | 60 s |
| Scheduler | `com.eco-commander.scheduler` | 120 s |
| SwiftBar autostart | `com.eco-commander.swiftbar` | on crash only |

Labels are validated by `scripts/healthcheck.sh` (`plutil -lint`) and checked
by `eco doctor`.

---

## Key log locations

| Log | Path |
|-----|------|
| Poller stdout | `~/.eco/logs/usage-poller.out.log` |
| Poller stderr | `~/.eco/logs/usage-poller.err.log` |
| Scheduler stdout | `~/.eco/logs/scheduler.out.log` |
| Scheduler stderr | `~/.eco/logs/scheduler.err.log` |
| SwiftBar autostart stdout | `~/.eco/logs/swiftbar-autostart.out.log` |
| SwiftBar autostart stderr | `~/.eco/logs/swiftbar-autostart.err.log` |
| Alert action logs | `~/.eco/alert-runs/` |
| Fix planning workspaces | `~/.eco/fix-plans/` |
| Job execution logs | `~/.eco/queue/logs/` |
| Gemini quota cache | `~/.eco/logs/gemini-userquota.json` |

---

## Related

- [`security-model.md`](./security-model.md) — credential handling and attack surface
- [`../getting-started/troubleshooting.md`](../getting-started/troubleshooting.md) — symptom-first quick reference
- [`../subsystems/alerts.md`](../subsystems/alerts.md) — alert investigation
- [`../subsystems/widget-health.md`](../subsystems/widget-health.md) — widget diagnostics
