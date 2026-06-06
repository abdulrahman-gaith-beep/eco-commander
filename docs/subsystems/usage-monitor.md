# Usage Monitor

Live plan-quota mirror for Claude Code, Gemini CLI, and Codex CLI in the
macOS menu bar. Mirrors what each CLI shows in its own TUI quota panel
so you can see all three at a glance without opening any of them.

**Related docs:**
- [Poller Pipeline diagram](../diagrams/poller-pipeline.md)
- [Meter State Machine diagram](../diagrams/meter-state-machine.md)
- [ADR 0004 — Python poller carve-out](../adr/0004-usage-monitor-python-carveout.md)
- [Historical integration plan](./usage-monitor-integration.md)
- [Module Dependencies diagram](../diagrams/module-deps.md)

## What you see

Menu bar: a single color-coded icon (🟢/🟡/🔴) reflecting the worst quota
or health signal across all tools. Click to expand.

The expanded panel shows per-tool progress bars, reset countdowns, token
totals, pace-to-target indicators, and quick-action menu items. A compact
suggestion line appears when a meter is at risk:

```text
💡 Claude Session at 89% — 18m until reset, 11% unburned → SPRINT
```

A stale badge appears when the poller has not refreshed in more than 180 seconds:

```text
⚠ STALE — poller data is 5m old
```

## Install

```bash
cd ~/projects/eco-commander
make install
```

This symlinks `src/bin/eco-commander.15s.sh` into the SwiftBar plugin
directory. To also install the usage poller and SwiftBar login agents:

```bash
ECO_INSTALL_LAUNCHAGENTS=1 make install
```

That installs:

- `com.eco-commander.usage-poller` — runs the Python poller every 60 seconds.
- `com.eco-commander.swiftbar` — opens SwiftBar at login.

If SwiftBar is not installed, the SwiftBar LaunchAgent step is skipped:

```bash
brew install --cask swiftbar
```

## Uninstall

```bash
make uninstall
```

Removes installed LaunchAgents and the SwiftBar plugin symlinks. Logs and
snapshot data under `~/.eco/` are preserved.

## How it works

```text
┌─ launchd (every 60s) ──────────────────────────────────────────┐
│  python3 src/poller/main.py                                    │
│    • claude.py   → ~/.eco/current/usage-claude.json            │
│    • gemini.py   → ~/.eco/current/usage-gemini.json            │
│    • codex.py    → ~/.eco/current/usage-codex.json             │
│    • accounts.py → stamps plan/account context onto each       │
│    • value.py    → USD-equivalent spend estimate               │
│    • notify.py   → writes meter state to notify.json           │
│    • main.py merges all → ~/.eco/current/usage.json            │
└─────────────────────────┬──────────────────────────────────────┘
                          ▼
┌─ SwiftBar (every 15s) ─────────────────────────────────────────┐
│  src/bin/eco-commander.15s.sh                                  │
│    reads usage.json + state.json, renders menu bar             │
└────────────────────────────────────────────────────────────────┘
```

Failures in one tool's collector never block the others. Each collector
is wrapped in `_safe_collect()` which catches all exceptions, logs only
the exception class name to a private `0600`-mode log, and returns an
`ok: false` payload — the widget shows a per-tool warning badge.

### Per-tool sources

**Claude Code** (`src/poller/claude.py`)

- Parses `~/.claude/projects/**/*.jsonl` for assistant messages.
- Deduplicates by `message.id` (streaming partial→final rows emit the
  same id; only the row with the largest `output_tokens` is counted).
- Sums `input_tokens`, `output_tokens`, `cache_creation_input_tokens`
  in 5h and 7d windows. `cache_read_input_tokens` are excluded from
  rate-limit accounting (`CACHE_READ_WEIGHT = 0.00` in `caps.py`).
- Computes three usage percentages from local counters and neutral cap
  constants in `caps.py`:
  - 5-hour session (all models pooled)
  - 7-day all-models
  - 7-day Sonnet-only sub-bucket
- The weekly headline is `max(all, sonnet)` — mirroring Claude.ai's display.
- Source is tagged `"source": "jsonl"` (estimate). When server-truth OAuth
  is enabled, `claude_oauth.collect()` is tried first; on success the result
  is augmented with per-account detail from the JSONL pass.
- Account/plan metadata is stamped later by `accounts.py`. Tracked defaults
  are neutral (`plan: "Unknown"`, `configured_accounts: 0`); real local
  metadata belongs in untracked `$ECO_HOME/accounts.json`.

**Gemini CLI** (`src/poller/gemini.py`)

- Replays `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`
  — the same endpoint gemini-cli's model-picker quota panel uses.
- Auth: bearer token from `~/.gemini/oauth_creds.json`, auto-refreshed
  5 minutes before expiry via `https://oauth2.googleapis.com/token`.
- Three tiers extracted from `buckets[].remainingFraction`:
  - `flash` — any `modelId` containing "flash" (not "lite")
  - `flash_lite` — any `modelId` containing "flash-lite" or "flash_lite"
  - `pro` — any `modelId` containing "pro"
  - When multiple buckets map to the same tier, the highest `pct` wins.
- Source is tagged `"source": "api"` (authoritative).
- Set `ECO_GEMINI_DEBUG_DUMP=1` to write the raw API response to
  `~/.eco/logs/gemini-loadcodeassist.json` and
  `~/.eco/logs/gemini-userquota.json` for debugging (private, `0600`).
- Multi-account: reads the local account registry only to count and label
  account slots. Output slugs are neutral (`primary`, `account-2`, ...);
  raw emails are not emitted as identifiers.

**Codex CLI** (`src/poller/codex.py`)

- Scans `~/.codex/sessions/**/*.jsonl` for cumulative token counters.
- Codex stores counters cumulatively within a session file. The collector
  takes the max value seen within each window and subtracts the pre-window
  baseline to avoid counting tokens from before the quota period.
- Fields tracked: `total_tokens`, `input_tokens`, `output_tokens`,
  `cached_input_tokens`, `reasoning_output_tokens`.
- Source is tagged `"source": "jsonl"` (estimate). When server-truth OAuth
  is enabled, `codex_oauth.collect()` is tried first; JSONL token detail
  is grafted on for value and credit estimates without overwriting
  authoritative pct values.

### Account metadata

The `accounts.py` module stamps configured plan/account metadata onto each
tool payload without overwriting collector-provided usage values.

Shipped metadata is intentionally generic. Real plan labels, account counts,
aliases, account inventory, and dated plan events live only in untracked local
config (`$ECO_HOME/accounts.json`, with older plan overrides in
`$ECO_HOME/config.json`).

| Tool | Shipped default |
|------|-----------------|
| Claude | `plan: "Unknown"`, `configured_accounts: 0` |
| Gemini | `plan: "Unknown"`, `configured_accounts: 0` |
| Codex | `plan: "Unknown"`, `configured_accounts: 0` |

### Pace-to-target

Each window carries a `pace_label` (`ahead`, `on-pace`, `behind`, `idle`)
and `pace_delta_pp` (percentage points over/under a linear burn target).
The widget surface shows a suggestion line when a meter is materially
off-pace. All pace math lives in `src/poller/pace.py` as a shared module.

### Plan-change warnings

The `accounts.py` module supports optional dated `plan_events` from
`$ECO_HOME/accounts.json`. Tracked source ships no operator-specific plan
events; local deployments can add private reminders without changing the repo.

## Calibration

**Gemini** — no calibration needed; `retrieveUserQuota` returns authoritative
`remainingFraction` from Google's servers.

**Claude** caps (`src/poller/caps.py`) ship as neutral placeholders. Local
deployments that need calibrated caps should keep those values outside tracked
source.

| Cap | Value (tokens) | Window |
|-----|---------------|--------|
| `CLAUDE_DEFAULT_5H_TOKENS` | `UNKNOWN_TOKEN_CAP` (`1`) | 5-hour rolling session |
| `CLAUDE_DEFAULT_7D_ALL_TOKENS` | `UNKNOWN_TOKEN_CAP` (`1`) | 7-day all-models |
| `CLAUDE_DEFAULT_7D_SONNET_TOKENS` | `UNKNOWN_TOKEN_CAP` (`1`) | 7-day Sonnet sub-bucket |
| `CACHE_READ_WEIGHT` | 0.00 | cache_read excluded from rate limits |

**Codex** caps use the same neutral placeholder policy:

| Cap | Value (tokens) |
|-----|---------------|
| `CODEX_DEFAULT_SESSION_TOKENS` | `UNKNOWN_TOKEN_CAP` (`1`) |
| `CODEX_DEFAULT_WEEKLY_TOKENS` | `UNKNOWN_TOKEN_CAP` (`1`) |

Back-compat alias names remain in source for older imports, but their values
resolve to the neutral defaults.

## Troubleshooting

| Symptom | Action |
|---------|--------|
| No data in menu bar after install | Wait 60s for the first poller cycle. Check: `launchctl list \| grep eco`. |
| `⚠ STALE` marker (>180s) | Check: `launchctl list \| grep eco.usage-poller`. Restart: `launchctl kickstart -k gui/$(id -u)/com.eco-commander.usage-poller`. |
| Gemini shows "OAuth expired" | Run `gemini` once to re-authenticate; the token in `~/.gemini/oauth_creds.json` is auto-refreshed on subsequent cycles while a `refresh_token` is present. |
| Gemini shows "no buckets" | The API response schema may have changed. Set `ECO_GEMINI_DEBUG_DUMP=1`, inspect `~/.eco/logs/gemini-userquota.json`, and update `_extract_tiers()` in `src/poller/gemini.py`. |
| Tokens look 10× too high | Your local cap calibration is too low. Keep private calibrated values outside tracked source, then `make install` your local runtime. |
| Widget shows nothing | Confirm SwiftBar is running: `pgrep -lf SwiftBar`. Confirm plugin symlink: `ls ~/Library/Application\ Support/SwiftBar/Plugins/`. |
| Claude % differs from Claude.ai | Check `caps.py` calibration; run `eco-alerts.sh doctor` to detect stale data. |

## Logs

| Path | Contents |
|------|---------|
| `~/.eco/logs/usage-poller.out.log` | Poller stdout |
| `~/.eco/logs/usage-poller.err.log` | Poller stderr |
| `~/.eco/logs/poller.log` | Sanitized per-exception tracebacks (0600 mode) |
| `~/.eco/logs/swiftbar-autostart.out.log` | SwiftBar LaunchAgent stdout |
| `~/.eco/logs/swiftbar-autostart.err.log` | SwiftBar LaunchAgent stderr |
| `~/.eco/current/usage.json` | Latest merged payload |
| `~/.eco/current/usage-<tool>.json` | Per-tool payload |

Treat logs and usage payloads as local/private. Exception messages are
never written to `usage.json`; only the exception class name appears
there, so bearer tokens cannot leak into world-readable JSON files.

## Related

- [Alerts](./alerts.md) — alert categories include quota and data-freshness
- [Widget Health](./widget-health.md) — widget rendering health playbook
- [Scheduler](./scheduler.md) — reads meter state written by `notify.py`
- [Architecture overview](../architecture.md)
- [Environment variables reference](../reference/environment-variables.md)
- [Data model reference](../reference/data-model.md)
- [LaunchAgent best practices](./launchd-best-practices.md)
