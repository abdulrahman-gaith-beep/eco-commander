# ADR 0004 — Usage Monitor: Python Carve-out + LaunchAgent Poller

| Field   | Value |
|---------|-------|
| Status  | Accepted |
| Date    | 2026-05-09 |
| Amends  | [ADR 0002 — Bash Implementation](./0002-bash-implementation.md) |
| Related | [ADR 0005 — Job Scheduler](./0005-job-scheduler.md) extends the Python carve-out |

## Context

A typical operator runs Claude Code, Gemini CLI, and Codex CLI daily. Each exposes a
per-tool plan-quota panel inside its TUI (`/usage` for Claude, the model picker
for Gemini, the account menu for Codex). Switching between three TUIs to check
capacity is friction; missing a weekly limit is costly.

`eco-commander` already has a SwiftBar status panel and a snapshot pattern
(`~/.eco/current/state.json`). At the time of this decision it did NOT:

- run any background daemon,
- read OAuth credentials, or
- contain Python code (per ADR 0002, the runtime was bash + jq).

> **Related Diagrams:**
> - [`docs/diagrams/poller-pipeline.md`](../diagrams/poller-pipeline.md) — data-collection flow
> - [`docs/diagrams/meter-state-machine.md`](../diagrams/meter-state-machine.md) — notification thresholds

## Decision

### 1. Add a Python module at `src/poller/`

Bash + jq cannot reasonably:

- parse multi-MB JSONL files in a tight loop,
- perform OAuth-refreshed HTTPS calls, or
- aggregate rolling-window token sums across many files.

Forcing bash here would be slow, fragile, or both. The poller module ships the
following Python files:

```text
src/poller/
├── main.py          # entrypoint — orchestrates all collectors
├── claude.py        # JSONL-based token aggregation
├── claude_oauth.py  # OAuth token refresh for Claude API
├── gemini.py        # Gemini quota collection
├── codex.py         # Codex usage collection
├── codex_oauth.py   # OAuth token refresh for Codex
├── caps.py          # calibrated plan-cap constants
├── accounts.py      # multi-account iteration
├── alternatives.py  # fallback account handling
├── discovery.py     # JSONL file discovery
├── notify.py        # writes ~/.eco/state/notify.json (meter events)
├── pace.py          # rate-limit pacing helpers
├── value.py         # USD-equivalent cost calculation
├── time_utils.py    # timezone and window utilities
└── comments.py      # embedded display-comment support
```

### 2. Constrain the Python carve-out

- Lives only in `src/poller/` (and `src/scheduler/` per ADR 0005).
- **stdlib only** — no `pip install` for the poller itself (`PyYAML` is added
  in ADR 0005 for the scheduler only).
- Never invoked from SwiftBar plugins or recipes; called only by launchd.

### 3. Keep the renderer in bash + jq

`src/bin/eco-commander.15s.sh` reads `~/.eco/current/usage.json` and exits in
< 50 ms. (The plugin was originally planned as `usage-monitor.15s.sh`; it was
merged into the main plugin file instead.)

### 4. Run the poller via a user LaunchAgent at 60-second intervals

```text
scripts/launchagents/com.eco-commander.usage-poller.plist
  └── StartInterval: 60
```

### 5. Auto-start SwiftBar at login via a sibling LaunchAgent

```text
scripts/launchagents/com.eco-commander.swiftbar.plist
```

This ensures the entire eco-commander surface is live the moment the user logs
in, even after a reboot.

### 6. `make install` wires both LaunchAgents

`scripts/install.sh` (invoked by `make install`) calls
`scripts/install-launchagents.sh`. `make uninstall` reverses the process via
`scripts/uninstall-launchagents.sh`.

## Why the Poller and Renderer Are Split

API/file work can take 1–2 seconds; the SwiftBar plugin must return in under
100 ms or SwiftBar pauses the UI. Splitting gives three further benefits:

- The renderer keeps showing last-known data even if the poller fails.
- Poller cadence (60 s) and widget cadence (15 s) are tuned independently.
- Tests can inject a fake `usage.json` without mocking subprocesses.

## Why No Third-Party Python Deps (Poller)

Adding `pip install` to a previously zero-dep repo creates an install burden
the user has not paid before. The stdlib covers everything needed: `json`,
`glob`, `urllib`, `sqlite3`, `tempfile`, `pathlib`. Future ADRs may revisit
this if Gemini OAuth requires a heavyweight client.

## Consequences

**Positive:**
- Single command (`make install`) yields a fully live menu-bar widget.
- Survives reboots; survives the user closing SwiftBar manually (next login
  restarts it).
- Per-tool failures do not poison other tools' data.
- Aligns with eco-commander's existing repo → `~/.eco/` → SwiftBar pipeline.

**Negative:**
- ADR 0002's "bash only" claim is now amended.
- Adds two LaunchAgents under `~/Library/LaunchAgents/`.
- Uses calibrated/estimated caps for Claude and Codex (Anthropic and OpenAI do
  not publish exact plan caps); output is marked `"source": "jsonl"` to flag
  the estimate.
- Gemini panel shipped initially as a stub until the quota endpoint was
  captured; widget shows "setup needed" instead of fabricated numbers.

## Alternatives Considered

| Alternative | Reason rejected |
|-------------|-----------------|
| **Bash-only poller** | JSONL parsing in pure bash is too slow at scale; OAuth refresh would mean shelling out to a Python one-liner anyway. |
| **Inline polling in the SwiftBar plugin** | Would freeze the menu bar on every 15-second refresh. |
| **Third-party tools (`ccusage`, `Claude-Code-Usage-Monitor`)** | Studied and used as cap-calibration references; not adopted as a dependency because they cover Claude only and require Node.js. |
| **Native SwiftUI `MenuBarExtra` app** | Deferred to a future Phase 3 if the bash widget gets daily use for a month. |
