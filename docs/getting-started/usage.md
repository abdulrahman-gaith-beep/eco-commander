# Usage

> Complete reference for the `eco` CLI: every subcommand, recipe, and flag verified against `src/bin/eco` and `src/recipes/`.

## Synopsis

```bash
eco [subcommand] [args...]
```

`eco` with no arguments is equivalent to `eco list`.

## Top-level subcommands

| Subcommand | Alias(es) | Description |
|------------|-----------|-------------|
| `list` | _(default)_ | List available recipes with their `# DESC:` annotations and any `# INPUTS:` hints |
| `do <name> [args…]` | — | Run the named recipe, forwarding all remaining arguments |
| `<name> [args…]` | — | Shortcut: if `<name>` matches a recipe file, runs it directly |
| `status` | — | Render the SwiftBar status panel to stdout (calls `eco-commander.15s.sh --cli`) |
| `dashboard` | — | Open `$HOME/.eco/current/dashboard.html` in the default browser |
| `map` | — | Open `~/.eco/current/map.md` |
| `audit` | — | Open `ECO_AUDIT_DIR` (default: `$HOME/.eco/ecosystem-audit`) |
| `scheduler <sub>` | `sched <sub>` | Scheduler subcommands (see below) |
| `hygiene <sub>` | `hyg <sub>` | Mac hygiene watcher (see below) |
| `account-swap <sub>` | `account <sub>`, `swap <sub>` | Rotate CLI auth between registered accounts (see below) |
| `doctor` | `doc` | Self-test installation: optional LaunchAgent status, CLI on PATH, Python imports, usage freshness, queue directory |
| `help` | `-h`, `--help` | Print built-in usage text |

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Router failure, `eco doctor` required-check failure, or a delegated command returning `1` |
| `2` | Possible from delegated scheduler argument/validation errors or recipes that use `2` for refusal/invalid runtime state |

> The `eco` router's own unknown-command and missing-recipe errors exit `1`. Scheduler subcommands and recipes run as delegated commands and may propagate their own exit codes; check each recipe's header or the [recipes reference](../subsystems/recipes.md).

## Recipes

Recipes live in `~/.eco/recipes/` (symlinked from `src/recipes/`). Run `eco list` to see all installed recipes with their descriptions.

### Built-in recipes

| Recipe | Syntax | Description |
|--------|--------|-------------|
| `account-swap` | `eco do account-swap <sub>` | Rotate auth between Claude/Gemini/Codex accounts without re-OAuth |
| `arabic-proof` | `eco do arabic-proof <file>` | Proofread Arabic text with local Ollama (private, zero cloud) |
| `ask` | `eco do ask "<question>"` | Ask a question fast; routes to Gemini by default |
| `dashboard` | `eco do dashboard` | Open `$HOME/.eco/current/dashboard.html` in the default browser |
| `dashboard-refresh` | `eco do dashboard-refresh [html]` | Refresh dashboard metric placeholders from live ecosystem state |
| `hygiene` | `eco do hygiene <sub>` | Mac hygiene watcher — RAM/swap/MCP/gemini-stuck monitor |
| `n8n-start` | `eco do n8n-start` | Start local n8n via Docker (falls back to npx) |
| `note` | `eco do note "<content>"` | Capture a note to long-term memory; opens `$EDITOR` if no content supplied |
| `research` | `eco do research "<topic>"` | Research a topic with Gemini (1 M-context, prompted if omitted) |
| `scheduler-seed` | `eco do scheduler-seed <dir>` | Import mission YAML files from `<dir>` into the scheduler queue |
| `snapshot` | `eco do snapshot` | Re-run the ecosystem snapshot and publish to `~/.eco/current/` |
| `swarm` | `eco do swarm "<task>" [N]` | Dispatch N parallel Gemini agents on a task and synthesize results (default N=5) |

### Examples

```bash
eco list
eco status
eco doctor

# Run a recipe via 'do'
eco do snapshot
eco do ask "what is the current MCP profile?"
eco do research "vision 2030 procurement reforms 2026"
eco do swarm "audit PR #42 for security issues" 3
eco do arabic-proof ~/drafts/report.md

# Shortcut syntax (equivalent to 'eco do snapshot')
eco snapshot
```

### Verification and dashboard behavior

`eco doctor` exits `0` when required checks pass and exits `1` only when the CLI is missing from `PATH` or the Python imports fail. LaunchAgent status is reported as optional; missing or stale `usage.json` and a missing or unwritable queue directory are warnings/informational in the current router.

`eco dashboard` and `eco do dashboard` both call `open` on `$HOME/.eco/current/dashboard.html`. `eco do dashboard-refresh [html]` rewrites metric placeholders in place, defaulting to `$HOME/.eco/current/dashboard.html`; `STATE_JSON` defaults to the selected dashboard's sibling `state.json`, while `AGENTS_DIR`, `MCP_MASTER`, and `CLAUDE_SETTINGS` provide the live metric inputs. It fails non-zero if the dashboard file, required metric inputs, or placeholders are missing.

## Scheduler subcommands

```bash
eco scheduler status                        # queue depth + meter availability
eco scheduler status --json                 # machine-readable JSON
eco scheduler add --file jobs.yaml          # import jobs from a YAML file
eco scheduler add -f jobs.yaml              # short flag alias
eco scheduler run-once                      # one dispatcher tick
eco scheduler drain                         # run ticks until queue is idle
eco scheduler drain --max-ticks 20          # cap ticks
eco scheduler drain --interval-s 5         # override inter-tick sleep
eco scheduler tail                          # most recent attempt log (latest job)
eco scheduler tail --id <job-id>            # tail a specific job's attempt log
eco scheduler seed --dir <directory>        # import mission YAMLs from a directory
eco scheduler seed -d <directory>           # short flag alias
eco scheduler cancel <job-id>               # cancel a pending or gated job
eco scheduler cancel --force <job-id>       # cancel regardless of state
```

> For the full scheduler reference including job YAML schema and meter state machine, see [../subsystems/scheduler.md](../subsystems/scheduler.md).

## Hygiene subcommands

```bash
eco hygiene watch          # install LaunchAgent and start daemon
eco hygiene watch-fg       # run daemon in foreground (same as 'daemon' alias)
eco hygiene snapshot       # take one hygiene snapshot now (alias: 'now')
eco hygiene stop           # unload daemon; remove PID file
eco hygiene status         # show daemon state and last snapshot metrics
eco hygiene tail           # follow the event log
eco hygiene tail-high      # follow only high-severity events
eco hygiene install        # install LaunchAgent plist only (no start)
eco hygiene uninstall      # unload and remove LaunchAgent plist
```

The daemon monitors RAM, swap pressure, MCP connection count, and stuck Gemini CLI processes. State is written to `~/.eco/state.json` under the `hygiene` key.

## Account-swap subcommands

```bash
eco account-swap list                             # list all registered accounts
eco account-swap claude <slug>                    # swap to Claude account <slug>
eco account-swap gemini <slug>                    # swap to Gemini account <slug>
eco account-swap codex  <slug>                    # swap to Codex account <slug>
eco account-swap claude --register <slug>         # register current Claude auth as <slug>
eco account-swap gemini --register <slug>         # register current Gemini auth as <slug>
eco account-swap codex  --register <slug>         # register current Codex auth as <slug>
eco account-swap claude --register <slug> --force # overwrite existing snapshot
eco account-swap claude --register <slug> --allow-keychain-prompt  # Claude only
```

Slugs must match `[A-Za-z0-9_-]+`. Swapping captures the current live auth state; registering snapshots it for future restores.

## Health tools

```bash
~/.eco/bin/eco-alerts.sh doctor
~/.eco/bin/eco-alerts.sh repo-health
~/.eco/bin/eco-alerts.sh debug-ollama
~/.eco/bin/eco-alerts.sh run-logged repo-health
~/.eco/bin/eco-alerts.sh delegate-fix <issue-id>
```

`repo-health` audits repository docs, changelog, runtime symlinks, expected commands, current `state.json`, widget renderability, and lint (via `shellcheck` when available).

> For the full alert workflow including fix tiers and delegate-fix mechanics, see [../subsystems/alerts.md](../subsystems/alerts.md).

## SwiftBar widget

The widget refreshes every 15 seconds. Click the menu-bar item to open the dropdown, which exposes the same operations as the CLI plus quick links to docs and the latest snapshot directory.

**Save snapshot (PNG + clipboard)** writes usage cards to `~/.eco/usage-snapshots/` by default. Set `ECO_SNAPSHOT_DIR` only when a one-off destination is intentional.

The llama count in the title is `loaded/installed`. `0/4` means no Ollama models are currently resident while four are installed. This is normal after `ollama stop <model>` or when the daemon is idle.

`--cli` mode prints the rendered widget to stdout; this is what `eco status` calls internally.

### Alert workflow

Snapshot findings are verified before the widget surfaces them as live alerts. Each alert row exposes:

- **Open evidence** — opens the source layer markdown for the finding
- **Fix: …** — runs the targeted remediation helper through a logged launcher
- **Alert doctor** — audits every snapshot finding and writes a run log
- **Repo health check** — audits the widget repository, docs, local commands, and runtime links

Fix tiers:

- **Safe/idempotent** — run directly (e.g., adding a stale-count guide banner)
- **Bounded operational** — run with logs and post-checks (e.g., snapshot reruns, n8n startup, dashboard metric refresh, memory index rebuilds)
- **Complex cross-project** — delegated to `gemini-3.1-pro-preview` by default; writes an evidence workspace under `~/.eco/fix-plans/` and produces a synthesis before any code-changing patch is applied

Alert action logs: `~/.eco/alert-runs/`
Fix-planning workspaces: `~/.eco/fix-plans/`

## Related

- [installation.md](./installation.md) — prerequisites and installation steps
- [troubleshooting.md](./troubleshooting.md) — common problems and fixes
- [../subsystems/scheduler.md](../subsystems/scheduler.md) — full scheduler reference
- [../subsystems/alerts.md](../subsystems/alerts.md) — alert workflow and fix tiers
- [../subsystems/recipes.md](../subsystems/recipes.md) — recipe authoring guide and conventions
- [../architecture.md](../architecture.md) — system overview
