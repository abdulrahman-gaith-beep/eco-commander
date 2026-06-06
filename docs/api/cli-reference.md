# CLI Reference

> Maintained in sync with `src/bin/eco` and `src/scheduler/cli.py`.
> Regenerate the skeleton with `docs/api/generate-cli-reference.sh`, then
> hand-verify against the sources listed below.

---

## `eco` — CLI Router

The main entry point. Routes subcommands to recipes, scheduler, and
built-in operations.

```text
eco [<subcommand>] [args...]
```

When called with no subcommand, `eco` behaves identically to `eco list`.

### Subcommands

| Command | Aliases | Synopsis | Description |
|---------|---------|----------|-------------|
| `list` | _(default)_ | `eco list` | List all recipes with their one-line descriptions and required inputs. |
| `do` | — | `eco do <recipe> [args...]` | Run a named recipe. Exits 1 if a syntactically valid recipe is not found and 2 for an invalid recipe name. |
| `status` | — | `eco status` | Print one-screen ecosystem state via `eco-commander.15s.sh --cli`. |
| `dashboard` | — | `eco dashboard` | Open `~/.eco/current/dashboard.html` in the default browser. |
| `map` | — | `eco map` | Open `~/.eco/current/map.md`. |
| `audit` | — | `eco audit` | Open `ECO_AUDIT_DIR` (default: `$HOME/.eco/ecosystem-audit`). |
| `scheduler` | `sched` | `eco scheduler <sub>` | Run the quota-aware job scheduler CLI. See §scheduler below. |
| `hygiene` | `hyg` | `eco hygiene <sub>` | Mac hygiene watcher (RAM/swap/MCP/gemini-stuck). Delegates to `src/recipes/hygiene.sh`. |
| `account-swap` | `account`, `swap` | `eco account-swap <sub>` | Rotate auth across Claude/Gemini/Codex accounts. Delegates to `src/recipes/account-swap.sh`. |
| `doctor` | `doc` | `eco doctor` | Self-test the eco-commander installation. Optional LaunchAgents and missing poller `usage.json` are informational on a default install; real setup errors exit 1. |
| `help` | `-h`, `--help` | `eco help` | Print the usage header from `src/bin/eco`. |

**Implicit recipe shortcut:** If `<command>` does not match any built-in and
`~/.eco/recipes/<command>.sh` exists, the file is executed directly — equivalent
to `eco do <command>`.

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Syntactically valid unknown command/recipe, missing required runtime file or directory, `eco doctor` real setup error such as missing CLI on `PATH` or failed Python imports, or non-zero delegated recipe/subcommand status |
| `2` | Invalid recipe/command name syntax, scheduler argument validation error, scheduler queue load error, or scheduler YAML/job-shape error |

---

## Recipes

Each recipe is a standalone script under `src/recipes/`. Recipes can be run
directly via `eco do <name>` or the implicit shortcut.

| Recipe | Description | Inputs | Output |
|--------|-------------|--------|--------|
| `account-swap` | Rotate auth between multiple Claude/Gemini/Codex accounts without re-OAuth | subcommand: `list` \| `<tool> <slug>` \| `<tool> --register <slug> [--force]` | `~/.eco/auth-snapshots/<tool>/<slug>/` + `~/.eco/state/active-accounts.json` |
| `arabic-proof` | Proofread Arabic text with local Ollama (private, zero cloud) | `<file path>` OR stdin | Proofread version to stdout + corrections list |
| `ask` | Ask a question fast. Routes to Gemini (quick) by default. No ceremony. | `<question>` (prompted if omitted) | stdout; optionally pipe to a file |
| `dashboard-refresh` | Refresh dashboard metric placeholders from live ecosystem state | `[dashboard_html]` | Rewrites `<span class=metric data-id=…>NUMBER</span>` placeholders in place |
| `dashboard` | Open the EROR dashboard (always-current ecosystem state) | none | Opens `~/.eco/current/dashboard.html` in default browser |
| `hygiene` | Mac hygiene watcher — RAM/swap/MCP/gemini-stuck monitor with state in `~/.eco/state.json` | subcommand: `watch\|watch-fg\|snapshot\|stop\|status\|tail\|tail-high\|install\|uninstall` | — |
| `n8n-start` | Start local n8n via Docker when available, otherwise via npx | none | Running n8n on `http://127.0.0.1:5678` |
| `note` | Capture a note to long-term memory in the right space | `<content string>` OR opens `$EDITOR` if empty | File in `~/.ai-memory/spaces/<space>/` when available; otherwise `~/.eco/notes/spaces/<space>/` |
| `research` | Research a topic with Gemini (fast, cheap, wide — 1 M context) | `<topic string>` (prompted if omitted) | `~/Documents/research/<slug>/YYYY-MM-DD-<slug>.md` |
| `scheduler-seed` | Import mission YAML files into the scheduler queue | `<directory>` — path containing `.yaml`/`.yml` mission files (default: `examples/missions/`) | Jobs added to `~/.eco/queue/jobs.yaml` |
| `snapshot` | Re-run EROR ecosystem snapshot and publish it to `current/` | none | `~/.eco/snapshots/<iso>/` + assembled state/map/dashboard + `current` symlink |
| `swarm` | Dispatch N parallel Gemini agents on a task; synthesise results | `<task description>`, optional N (default 5) | `~/Documents/research/_swarm/<ts>/` with N agent outputs + summary |

---

## `eco scheduler` — Job Scheduler

Quota-aware cross-project AI-job dispatcher. Exposes a CLI for manual control
and can run as a launchd agent every 120 s when the scheduler LaunchAgent is
explicitly installed.

```text
eco scheduler <subcommand> [flags]
```

Internally delegates to `python3 -m scheduler.cli` with `PYTHONPATH` set to
`src/`.

### Subcommands

| Command | Flags | Description |
|---------|-------|-------------|
| `status` | `[--json]` | Show queue depth, per-status counts, and meter availability. Pass `--json` for machine-readable output. |
| `add` | `--file <path>` | Append jobs from a YAML file (`{jobs: [...]}` or bare list). Skips duplicate IDs. |
| `run-once` | `[--max-jobs N]` | Execute one dispatch tick (default max-jobs=1). Prints summary JSON. |
| `drain` | `[--max-ticks N] [--interval-s S]` | Run ticks until the queue is idle or fully gated, up to N ticks (default 10). |
| `tail` | `[--id <job-id>]` | Print the most recent attempt's stdout log. Defaults to the latest attempt across all jobs. |
| `seed` | `--dir <path>` | Scan a directory for `.yaml`/`.yml` mission files and import all jobs. |
| `cancel` | `<job-id> [--force]` | Cancel a pending or gated job. Use `--force` to cancel jobs in other states. |

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Job/log not found, no seed YAML files, invalid seed files/entries, cancelled job not eligible, or `run-once`/`drain` summary reports errors or failed attempts |
| `2` | Bad arguments, missing/invalid `add --file` input, invalid `add --file` YAML/job shape, invalid seed directory, or scheduler queue load error |

---

## Environment Variables

See [`.env.example`](../../.env.example) for the full list with defaults.
Detailed reference: [`docs/reference/environment-variables.md`](../reference/environment-variables.md).

Key variables that affect CLI behaviour:

| Variable | Default | Effect |
|----------|---------|--------|
| `ECO_HOME` | `~/.eco` | Root of the runtime state directory |
| `ECO_COMMANDER_REPO` | auto-detected from the installed script when unset | Repo root used by `eco scheduler` to locate `src/`; set only when auto-detection cannot find the clone |
| `ECO_AUDIT_DIR` | `$HOME/.eco/ecosystem-audit` | Directory opened by `eco audit` |
| `ECO_COMMENTS` | `0` | Set to `1` to enable burn-rate commentary in `usage.json` |
| `ECO_MAX_JOBS_PER_TICK` | `1` | Maximum jobs the scheduler fires per launchd invocation |
| `ECO_LOG_LEVEL` | `INFO` | Python log level for poller and scheduler |

---

## Source References

| Component | Source |
|-----------|--------|
| CLI router | [`src/bin/eco`](../../src/bin/eco) |
| Scheduler CLI | [`src/scheduler/cli.py`](../../src/scheduler/cli.py) |
| Scheduler dispatcher | [`src/scheduler/dispatcher.py`](../../src/scheduler/dispatcher.py) |
| Recipe library | [`src/recipes/`](../../src/recipes/) |
| Generator script | [`docs/api/generate-cli-reference.sh`](generate-cli-reference.sh) |
