# Environment Variables

Every environment variable read by eco-commander, grouped by subsystem.
All variables have sensible defaults; none are required for basic operation.

## Core

| Variable | Default | Used by | Purpose |
|----------|---------|---------|---------|
| `ECO_HOME` | `~/.eco` | Most components | Root directory for runtime state, logs, config, and queue; some legacy recipes still write directly under `~/.eco` |
| `ECO_COMMANDER_REPO` | auto-detected from the installed script when unset | `eco`, `eco-alerts.sh`, `eco-commander.15s.sh` | Path to the eco-commander git repository; set only when auto-detection cannot find the clone |
| `ECO_AUDIT_DIR` | `$HOME/.eco/ecosystem-audit` | `eco audit` | Directory opened by the `eco audit` command; must exist or the command exits 1 |
| `SWIFTBAR_PLUGIN_DIR` | `~/Library/Application Support/SwiftBar/Plugins` | `scripts/install.sh`, `scripts/uninstall.sh` | Override SwiftBar plugin install location |
| `ECO_INSTALL_LAUNCHAGENTS` | `0` | `scripts/install.sh` | Set to `1` to install LaunchAgents during `make install` |
| `ECO_LAUNCHAGENTS_DIR` | `~/Library/LaunchAgents` | `scripts/install-launchagents.sh`, `scripts/uninstall-launchagents.sh` | Override LaunchAgent destination for tests |
| `HOME` | shell-provided | Bash recipes, widget, poller collectors | Base for default runtime paths and provider CLI credential/log locations |
| `PATH` | inherited; some scripts prepend common macOS paths | Bash recipes, widget, run wrappers | Command discovery for CLIs such as `gemini`, `docker`, `ollama`, `python`, and `open` |
| `PYTHON` | (unset) | `eco scheduler`, `scripts/run-poller.sh`, `scripts/run-scheduler.sh`, `scripts/install-launchagents.sh` | Preferred Python executable before versioned `python3.x` fallback |
| `PYTHON_BIN` | (unset) | `eco scheduler`, `scripts/setup-venv.sh`, `scripts/run-poller.sh`, `scripts/run-scheduler.sh`, `scripts/install-launchagents.sh` | Alternate Python executable override |
| `PYTHONPATH` | (inherited) | `eco scheduler`, run wrappers, LaunchAgent templates | Extended with the repo `src/` directory when invoking Python modules |
| `TMPDIR` | `/tmp` fallback in recipes | Provider log helpers | Directory for temporary provider stderr logs |

> `ECO_LIB` was removed. Recipes now source the shared library via a path relative to `$ECO_HOME/recipes/`.

## Usage poller (`src/poller/`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO_HOME` | `~/.eco` | Output directory for `current/usage*.json` and logs |
| `ECO_CLAUDE_ACCOUNTS` | (unset; collector has an internal fallback) | Comma-separated local account slugs to poll for JSONL-based Claude usage; prefer neutral slugs such as `primary,account-2` |
| `ECO_COMMENTS` | `0` | Set to `1` to enable burn-rate commentary generation in `usage.json` |
| `ECO_NOTIFICATIONS` | `1` | Set to `0` to disable macOS notification center alerts entirely |
| `ECO_NOTIFY_LOG_ONLY` | `1` | Set to `0` to fire real notifications; default is log-only (safe rollout mode) |
| `ECO_GEMINI_DEBUG_DUMP` | (unset) | Set to `1` to write raw Gemini API quota responses to disk for debugging |
| `ECO_GEMINI_OAUTH_CLIENT_ID` | (unset) | OAuth client ID used for Gemini server-truth quota polling |
| `ECO_GEMINI_OAUTH_CLIENT_SECRET` | (unset) | OAuth client secret used for Gemini server-truth quota polling |
| `ECO_VALUE_MODEL_JSON` | (unset) | Path to a canonical external financial-model export used by `src/poller/value.py`; absent means value output is marked unavailable |

## Scheduler (`src/scheduler/`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO_HOME` | `~/.eco` | Queue path (`$ECO_HOME/queue/jobs.yaml`), meter state, and logs |
| `ECO_LOG_LEVEL` | `INFO` | Python logging level for the scheduler (`DEBUG`, `INFO`, `WARNING`, `ERROR`) |
| `ECO_MAX_JOBS_PER_TICK` | `1` | Maximum jobs to fire per scheduler tick |
| `ECO_DRY_RUN` | (unset) | Set to `1` to echo commands instead of executing them (all adapters: Claude, Codex, Gemini, Ollama) |
| `ECO_SCHEDULER_PERSIST` | `0` | Set to `1` to render the scheduler LaunchAgent plist without loading it |
| `ECO_SCHEDULER_AUTO_LOAD` | `0` | Set to `1` to auto-load the scheduler LaunchAgent during `install-launchagents.sh` |

### Adapter binary overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO_CLAUDE_BIN` | `claude` | Path to the Claude Code CLI binary |
| `ECO_CODEX_BIN` | `codex` | Path to the Codex CLI binary |
| `ECO_GEMINI_BIN` | `gemini` | Path to the Gemini CLI binary |
| `ECO_OLLAMA_BIN` | `ollama` | Path to the Ollama CLI binary |

### Gemini adapter options

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO_GEMINI_APPROVAL_MODE` | `plan` | Gemini CLI `--approval-mode` value; valid values are `default`, `auto_edit`, `yolo`, and `plan` |
| `ECO_GEMINI_ALLOW_EXTERNAL_INCLUDE_DIRS` | (unset) | Set to `1` to allow Gemini scheduler `include_directories` outside the job workdir after normal path validation |

## Alert system and n8n recipe (`src/bin/eco-alerts.sh`, `src/recipes/n8n-start.sh`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO` | `${ECO_HOME:-$HOME/.eco}` | Runtime root override used by `eco-alerts.sh` |
| `N8N_URL` | `http://127.0.0.1:5678/` | Local n8n health URL checked by alert actions |
| `GEMINI_FIX_MODEL` | `gemini-3.1-pro-preview` | Gemini model used by delegated alert-fix planning |
| `GEMINI_FIX_AGENTS` | `3` | Number of Gemini planning agents used by delegated alert-fix flows |
| `TOOLKIT_ROOT` | `$HOME/Projects/toolkit` | Optional legacy Toolkit checkout root used only by memory-router compatibility alert/fix checks; not required for a default install |
| `GUIDE_FILE` | `$HOME/ai-ecosystem-guide.html` | Optional local guide file checked by guide-staleness alert actions; missing files are treated as no guide target |
| `ECO_ALERT_OPEN_TERMINAL` | `1` | Set to `0` to suppress terminal window opening during automated runs |
| `ECO_ALERT_SHOW_CLEARED` | `0` | Show resolved alert rows in the SwiftBar Alerts section |
| `ECO_N8N_EXPECTED` | `1` | Treat local n8n as an expected service; set to `0` when n8n is on-demand only |
| `ECO_N8N_COMPOSE` | (none) | Explicit n8n Docker Compose file for `n8n-start`; missing files are errors |
| `ECO_N8N_COMPOSE_DEFAULT` | (unset) | Optional preferred n8n Docker Compose file tried before automatic project scanning |
| `ECO_N8N_STATUS` | (injected) | Internal: n8n health status injected by the widget into eco-alerts.sh |
| `N8N_CONTAINER_NAME` | `n8n` | Docker container name used by `n8n-start.sh` |
| `N8N_IMAGE` | `docker.n8n.io/n8nio/n8n` | Docker image used when creating an n8n container |
| `N8N_VOLUME_NAME` | `n8n_data` | Docker volume name used when creating an n8n container |
| `N8N_PORT` | `5678` | Host port exposed by Docker mode |
| `ECO_ALLOW_DIRECT_COMPLEX_FIX` | `0` | Set to `1` to bypass Gemini Pro planning for complex fixes |
| `ECO_FORCE_MEMORY_ROUTER_MISSING` | `0` | Testing: force the memory-router-missing alert to appear |

## Widget and audit surfaces (`src/bin/eco-commander.15s.sh`, `scripts/usage-snapshot.sh`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO_WIDGET_CONFIG` | `$ECO_HOME/config/widget.env` | Optional widget env/config file read for audit surface paths when corresponding environment variables are unset |
| `ECO_AUDIT_ROOT` | Snapshot: unset means prefer legacy runtime prompts when present, then repo examples; widget: unset unless env/config supplies it | Explicit custom snapshot prompt-library root (`$ECO_AUDIT_ROOT/prompts`); widget audit links are hidden/skipped when no audit root is configured |
| `ECO_EROR_SPEC` | `$ECO_AUDIT_ROOT/specs/EROR-v1-DRAFT.md` when `ECO_AUDIT_ROOT` is set | Optional EROR specification path used by the widget |
| `ECO_DOMAIN_CHARTERS` | `$ECO_AUDIT_ROOT/specs/DOMAIN-CHARTERS.md` when `ECO_AUDIT_ROOT` is set | Optional domain-charters path used by the widget |
| `ECO_ORG_LABEL` | (unset) | Optional organization label rendered in shipped UI/output; empty by default and omitted when unset |

## Account swap recipe (`src/recipes/account-swap.sh`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO_ACCOUNT_SECURITY` | `security` | Path to the `security` CLI binary (macOS Keychain tool) |
| `ECO_ACCOUNT_PGREP` | `pgrep` | Path to `pgrep` binary used to detect running Claude processes |
| `GEMINI_HOME` | `$HOME/.gemini` | Gemini auth directory used by account-swap snapshots |
| `CODEX_HOME` | `$HOME/.codex` | Codex auth directory used by account-swap snapshots |
| `ECO_ALLOW_KEYCHAIN_PROMPT` | `0` | Set to `1` to allow Keychain read/write prompts during account swap (required for the swap to proceed) |
| `ECO_ACCOUNT_SECURITY_STDIN_PASSWORD` | `0` | Set to `1` to allow writing Claude credentials via stdin to a helper binary; gated explicitly to prevent accidental secret exposure |

## Hygiene watcher (`src/recipes/hygiene.sh`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO_HYGIENE_INTERVAL` | `30` | Polling interval in seconds for the hygiene daemon |
| `ECO_HYGIENE_RED_MEM_GB` | `3` | Available memory threshold (GB) below which status turns red |
| `ECO_HYGIENE_YEL_MEM_GB` | `6` | Available memory threshold (GB) below which status turns yellow |
| `ECO_HYGIENE_RED_SWAP_MB` | `6000` | Swap used threshold (MB) above which status turns red |
| `ECO_HYGIENE_YEL_SWAP_MB` | `5500` | Swap used threshold (MB) above which status turns yellow |
| `ECO_HYGIENE_RED_MCP` | `80` | MCP process count above which status turns red |
| `ECO_HYGIENE_YEL_MCP` | `50` | MCP process count above which status turns yellow |
| `ECO_HYGIENE_STUCK_MIN` | `20` | Minutes a Gemini process may run before being flagged as stuck |

## Arabic proof recipe (`src/recipes/arabic-proof.sh`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO_ARABIC_PROOF_MODEL` | (falls back to `ECO_ARABIC_MODEL`) | Ollama model to use for Arabic proofing |
| `ECO_ARABIC_MODEL` | `qwen3.6:latest` | Fallback Ollama model when `ECO_ARABIC_PROOF_MODEL` is unset |
| `ECO_ARABIC_PROOF_AUTO_UNLOAD` | `0` | Set to `1` to unload the Ollama model from memory after the proof run |

## Gem-smart / research recipes (`src/recipes/snapshot.sh`, `research.sh`, `ask.sh`, `swarm.sh`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO_GEM_SMART_BIN` | `$HOME/bin/gem-smart` | Path to the optional `gem-smart` Gemini wrapper; recipes fall back to plain `gemini` when the configured/default wrapper path does not resolve, and fail only when neither backend is available |
| `ECO_ASK_LOCAL_MODEL` | `qwen3.6:latest` | Ollama model used when `eco ask` detects private/secret/internal/confidential cues; there is no `--local` flag |
| `GEMINI_LAYER_TIMEOUT_SEC` | `180` | Per-layer timeout for the snapshot recipe's Gemini analysis subprocess |

## Dashboard refresh recipe (`src/recipes/dashboard-refresh.sh`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `DASHBOARD_HTML` | `~/.eco/current/dashboard.html` | Target dashboard file when no positional argument is passed |
| `AGENTS_DIR` | `~/.claude/agents` | Optional agent markdown directory used for agent-count metrics; missing directory counts as `0` |
| `MCP_MASTER` | `~/.ai-ecosystem/mcp-master.json` | Optional MCP registry used for MCP count metrics; missing file counts as `0` |
| `CLAUDE_SETTINGS` | `~/.claude/settings.json` | Optional Claude settings file used for plugin/tool metrics; missing file counts as `0` |
| `STATE_JSON` | `<dashboard dir>/state.json` | Snapshot state file used for snapshot-age metrics |

## Scripts (`scripts/`)

| Variable | Default | Used by | Purpose |
|----------|---------|---------|---------|
| `ECO_SNAPSHOT_DIR` | `$ECO_HOME/usage-snapshots` | `scripts/usage-snapshot.sh` | Override shareable usage snapshot output directory |
| `ECO_SNAPSHOT_CLIPBOARD` | `1` | `scripts/usage-snapshot.sh` | Set to `0` to skip copying snapshot to clipboard |
| `ECO_SNAPSHOT_REVEAL` | `1` | `scripts/usage-snapshot.sh` | Set to `0` to skip revealing snapshot in Finder |
| `ECO_SNAPSHOT_NOTIFY` | `1` | `scripts/usage-snapshot.sh` | Set to `0` to skip sending macOS notification on snapshot completion |
| `ECO_ALLOW_LIVE_CREDENTIAL_PROBE` | `0` | `scripts/toggle-precise.sh` | Set to `1` to allow Keychain/OAuth probes when enabling server-truth mode |
| `ECO_HEALTHCHECK_MACOS_SURFACES` | `0` | `scripts/healthcheck.sh` | Set to `1` to check LaunchAgents and SwiftBar installation during healthcheck |
| `ECO_HEALTHCHECK_LIVE_RUNTIME` | `0` | `scripts/healthcheck.sh` | Set to `1` to validate live `usage.json` and log sizes during healthcheck |

## Related

- [configuration.md](./configuration.md) — Config files, LaunchAgent plists, and neutral cap constants
- [data-model.md](./data-model.md) — JSON schemas written and read by the poller and scheduler
- [../subsystems/alerts.md](../subsystems/alerts.md) — Alert system that consumes several alert variables
- [../subsystems/scheduler.md](../subsystems/scheduler.md) — Scheduler that consumes adapter and meter variables
