# Configuration

All configuration files that eco-commander reads or writes, with their
locations and purposes.

## Repository configuration

| File | Purpose |
|------|---------|
| `Makefile` | Build targets: `install`, `uninstall`, `test`, `lint`, `release` |
| `.editorconfig` | Editor settings (indentation, line endings) |
| `.shellcheckrc` | shellcheck configuration |
| `.gitignore` | Git ignore patterns |

## LaunchAgent plists

Source templates live in `scripts/launchagents/`. During explicit LaunchAgent installation,
`__POLLER_PATH__`, `__SRC_DIR__`, `__ECO_HOME__`, and `__PYTHON_BIN__`
placeholders are replaced with actual paths, and the rendered plists are copied to
`ECO_LAUNCHAGENTS_DIR` (default: `~/Library/LaunchAgents/`). The main installer
only calls this flow when `ECO_INSTALL_LAUNCHAGENTS=1`.

| Plist | Purpose | Cadence |
|-------|---------|---------|
| `com.eco-commander.usage-poller.plist` | Run the Python usage poller | Every 60s (`StartInterval`) |
| `com.eco-commander.scheduler.plist` | Run the Python job scheduler | Every 120s (`StartInterval`); rendered only when `ECO_SCHEDULER_PERSIST=1` or loaded when `ECO_SCHEDULER_AUTO_LOAD=1` |
| `com.eco-commander.swiftbar.plist` | Open SwiftBar at login | `RunAtLoad` only |

### Plist settings

The LaunchAgent templates do not share identical launchd controls. Current
values in `scripts/launchagents/*.plist` are:

| Plist | `ProcessType` | `Nice` | `LowPriorityIO` | `LowPriorityBackgroundIO` | `ThrottleInterval` | `ExitTimeOut` | Logs |
|-------|---------------|--------|-----------------|---------------------------|--------------------|---------------|------|
| `com.eco-commander.usage-poller.plist` | `Background` | `5` | `true` | `true` | `30` | `30` | `$ECO_HOME/logs/usage-poller.{out,err}.log` |
| `com.eco-commander.scheduler.plist` | `Background` | `5` | `true` | `true` | `60` | `900` | `$ECO_HOME/logs/scheduler.{out,err}.log` |
| `com.eco-commander.swiftbar.plist` | _(unset)_ | _(unset)_ | _(unset)_ | _(unset)_ | `30` | _(unset)_ | `$ECO_HOME/logs/swiftbar-autostart.{out,err}.log` |

`StandardOutPath` and `StandardErrorPath` are rendered into `$ECO_HOME/logs/`
during installation.

See [`launchd-best-practices.md`](../subsystems/launchd-best-practices.md) for the
full rationale.

## Poller configuration

Tracked examples live under [`../../config/`](../../config/):

| Template | Runtime path | Purpose |
|----------|--------------|---------|
| `config/config.example.json` | `$ECO_HOME/config.json` | Illustrative local display/server-truth override example |
| `config/comments.example.json` | `$ECO_HOME/config/comments.json` | Optional usage-comment catalog override example |

### `~/.eco/config.json` (optional)

Optional JSON configuration file at `$ECO_HOME/config.json`, read by
`src/poller/discovery.py` for local display overrides and server-truth toggles.
An absent or empty file is valid.

```json
{
  "server_truth": {
    "claude": false,
    "gemini": false,
    "codex": false
  }
}
```

| Key | Purpose |
|-----|---------|
| `<tool>.plan` | Override the default plan name displayed in the widget |
| `claude.accounts` | Optional legacy Claude account-count override for `discovery.py`; Claude account inventory remains in `$ECO_HOME/accounts.json` |
| `server_truth.<tool>` | Set to `true` to enable OAuth / server-truth polling for that tool (default: `false`; requires credentials in place) |

### `~/.eco/accounts.json` (optional)

Optional local account/plan inventory read by `src/poller/accounts.py`. This
file is never shipped with operator-specific values; absent inventory is
neutral (`configured_accounts: 0`, `account_inventory: []`), while collectors
may still report detected local credential counts.

```json
{
  "tools": {
    "gemini": {
      "configured_accounts": 0,
      "account_inventory": [],
      "plan_events": []
    }
  }
}
```

### `~/.eco/config/comments.json` (optional)

Optional comment catalog override read by `src/poller/comments.py` when
`ECO_COMMENTS=1`. If absent, the bundled catalog at
`src/poller/data/comments.json` is used.

The override shape is:

```json
{
  "version": 1,
  "tiers": {
    "gentle": ["usage is warming up"],
    "bold": ["meter is moving quickly"],
    "alarmed": ["quota burn is unusually high"]
  }
}
```

### `src/poller/caps.py`

Neutral usage-window constants for Claude and Codex. Account-specific token
caps are not shipped in public source; local deployments that need calibrated
limits should keep them in untracked local configuration. Gemini uses
server-side quota fractions when server-truth polling is enabled.

| Constant | Value | Purpose |
|----------|-------|---------|
| `UNKNOWN_TOKEN_CAP` | `1` | Neutral non-zero placeholder used to avoid division by zero |
| `CLAUDE_DEFAULT_5H_TOKENS` | `1` | Neutral Claude 5-hour session cap placeholder |
| `CLAUDE_DEFAULT_7D_ALL_TOKENS` | `1` | Neutral Claude 7-day all-models cap placeholder |
| `CLAUDE_DEFAULT_7D_SONNET_TOKENS` | `1` | Neutral Claude 7-day Sonnet-only cap placeholder |
| `CODEX_DEFAULT_SESSION_TOKENS` | `1` | Neutral Codex 5-hour session cap placeholder |
| `CODEX_DEFAULT_WEEKLY_TOKENS` | `1` | Neutral Codex 7-day cap placeholder |
| `CACHE_READ_WEIGHT` | `0.00` | Cache-read token weight toward quota (0% — Anthropic excludes cache reads from rate limits) |
| `SESSION_WINDOW_SECONDS` | `18,000` | 5-hour rolling session window |
| `WEEKLY_WINDOW_SECONDS` | `604,800` | 7-day weekly window |
| `WARN_PCT` | `80` | Warning threshold percentage |
| `CRIT_PCT` | `95` | Critical threshold percentage |

Back-compat aliases for prior Claude and Codex cap names are preserved for
older imports. In current source they point at the same neutral placeholder
values.

## OAuth credentials (read-only)

The poller reads OAuth tokens from the CLI tools' own credential stores.
It never writes to these files.

| File | Tool | Module |
|------|------|--------|
| `~/.gemini/oauth_creds.json` | Gemini CLI (active account) | `src/poller/gemini.py` |
| `~/.gemini/accounts/oauth_creds.*.json` | Gemini CLI (additional accounts) | `src/poller/discovery.py` |
| macOS Keychain generic password service `Claude Code-credentials` | Claude Code | `src/poller/claude_oauth.py` |
| `~/.codex/auth.json` | Codex CLI | `src/poller/codex_oauth.py` |

`src/poller/claude_oauth.py` reads the Claude bearer with
`security find-generic-password -s Claude Code-credentials -w`. The JSONL Claude
collector reads Claude Code usage logs, but it does not read OAuth credentials.

## MCP configuration

| File | Purpose |
|------|---------|
| `~/.ai-ecosystem/mcp-master.json` | Master MCP server registry; read by snapshot probes |
| `~/.ai-ecosystem/.current-profile` | Active MCP profile name; displayed in the widget |

## Log rotation

| File | Purpose |
|------|---------|
| `scripts/log-rotate.conf` | newsyslog drop-in template for eco-commander logs |
| `/etc/newsyslog.d/eco-commander.conf` | Installed copy (requires `sudo`). Rotates logs ≥ 1 MB daily; retains 5 compressed archives. |

Install with:

```bash
sudo ./scripts/install-log-rotation.sh
```

## Seed and mission files

Mission YAML files live under `examples/missions/`. A generic, ready-to-run
example ships with the repository.

| File | Purpose |
|------|---------|
| `examples/missions/seed-jobs.example.yaml` | Example job seed file for the scheduler |

Import into the scheduler queue with:

```bash
eco scheduler add --file examples/missions/seed-jobs.example.yaml
```

## Related

- [environment-variables.md](./environment-variables.md) — Every variable that controls runtime behavior
- [data-model.md](./data-model.md) — JSON schemas for `config.json`, `usage.json`, and `notify.json`
- [../subsystems/scheduler.md](../subsystems/scheduler.md) — Scheduler that reads meter state and job YAML
- [../subsystems/usage-monitor.md](../subsystems/usage-monitor.md) — Poller that reads `server_truth` from `config.json` via `discovery.py`
