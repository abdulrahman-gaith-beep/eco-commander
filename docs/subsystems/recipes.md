# Recipes

Standalone bash workflow scripts under `src/recipes/`. Each recipe is a
self-contained, directly executable script with a structured metadata header
that the widget and `eco list` read to build menus and documentation.

Runtime recipes live in the real directory `~/.eco/recipes/`, populated by
`make install` with per-file symlinks back to `src/recipes/*.sh`.

**Related docs:**
- [Snapshots](./snapshots.md)
- [Scheduler](./scheduler.md) — `scheduler-seed` populates the job queue

## Catalog

### `account-swap`

**Related diagram:** [Account Swap Flow](../diagrams/account-swap-flow.md)

Rotate registered Gemini or Codex auth snapshots, and register Claude Keychain
snapshots for manual recovery. Stores credential snapshots under
`~/.eco/auth-snapshots/`.

- **Args:** `list` | `<tool> <slug>` | `<tool> --register <slug> [--force] [--allow-keychain-prompt]`
- **Tools:** `claude` | `gemini` | `codex`
- **Output:** stdout confirmation of the active account; updates `~/.eco/state/active-accounts.json`.
- **Side effects:** overwrites live credential files for Gemini/Codex. Claude
  Keychain restore is disabled when using the real macOS `security` CLI, so
  Claude requires manual re-authentication instead of automatic restore.
- **Safety:** refuses to swap Claude/Codex while a CLI process is running.
  Claude Keychain restore is disabled for the real `security` CLI (it would
  expose the secret in process args); re-authenticate Claude manually.

```bash
src/recipes/account-swap.sh list
src/recipes/account-swap.sh gemini --register primary
src/recipes/account-swap.sh gemini account-2
src/recipes/account-swap.sh claude --register backup --allow-keychain-prompt
```

### `arabic-proof`

Proofread Arabic text locally with Ollama. No cloud call; private by design.

- **Args:** `<file path>` or piped stdin.
- **Output:** corrected text to stdout + a list of changes.
- **Model:** `ECO_ARABIC_MODEL` (default `qwen3.6:latest`); must be installed via `ollama pull`.

### `ask`

One-shot Q&A with smart routing.

- **Args:** `<question…>` (prompted interactively if omitted).
- **Output:** stdout answer; no files written.
- **Routing:** if the question contains a private-cue keyword (`private`,
  `secret`, `internal`, `confidential`, `بياناتي`, `خاص`), routes to the
  local Ollama model (`ECO_ASK_LOCAL_MODEL`, default `qwen3.6:latest`).
  Otherwise uses Gemini through `gem-smart 3.5f` when that wrapper is
  available, or the plain `gemini -p` CLI when it is not.
- **Env:** `ECO_GEM_SMART_BIN` (default `$HOME/bin/gem-smart`),
  `ECO_ASK_LOCAL_MODEL`. Non-private prompts require an authenticated Gemini
  CLI or a working `gem-smart` wrapper.

### `dashboard`

Open the ecosystem snapshot dashboard.

- **Args:** none.
- **Output:** opens `~/.eco/current/dashboard.html` in the default browser.

### `dashboard-refresh`

Inject live ecosystem metrics into the dashboard HTML template. Reads the
latest snapshot and rewrites `<span class=metric data-id=...>` placeholders
with current values.

- **Args:** optional `<dashboard_html>` path (default: `~/.eco/current/dashboard.html`).
- **Output:** updates dashboard HTML in place.
- **Uses:** `sed` (BSD/macOS), `python3`, `AGENTS_DIR`, `MCP_MASTER`,
  `CLAUDE_SETTINGS`, and `STATE_JSON`. By default `STATE_JSON` is the selected
  dashboard's sibling `state.json`; the other defaults are shown by
  `dashboard-refresh.sh --help`.

### `hygiene`

Mac hygiene watcher — monitors RAM/swap, stale MCP servers, stuck Gemini
processes, and workspace health. Replaces session-scoped Claude Monitor loops.

- **Args:** `watch` | `watch-fg` | `snapshot` | `stop` | `status` | `tail` | `install` | `uninstall`.
- **State:** `~/.eco/state.json`.
- **Output:** hygiene report to stdout; logs under `~/.eco/`.
- **Side effects:** `install`/`uninstall` register a launchd job.

### `n8n-start`

Start local n8n when the daemon is missing.

- **Args:** none.
- **Output:** running n8n on `http://127.0.0.1:5678`; stdout status.
- **Strategy:** Docker Compose if available; falls back to `npx`.
- **Side effects:** may start a Docker container.

### `note`

Capture a note to long-term memory in the right space.

- **Args:** `<content string>` or opens `$EDITOR` if empty.
- **Output:** file under `~/.ai-memory/spaces/<space>/` + index rebuild.
- **Routing:** auto-routes to the right memory space by current working
  directory.
- **Uses:** filesystem write + `memory_router` index rebuild.

### `research`

Research a topic with Gemini (fast, wide — 1M context).

- **Args:** `<topic string>` (prompted if omitted).
- **Output:** `~/Documents/research/<slug>/YYYY-MM-DD-<slug>.md`.
- **Model/invocation:** `gem-smart 3.5f` with MCP servers disabled when the
  wrapper is available; otherwise plain `gemini -p`.

### `scheduler-seed`

Import mission YAML files into the scheduler queue.

- **Args:** `<directory>` — path containing `.yaml`/`.yml` mission files
  (default: `examples/missions/`).
- **Output:** jobs added to `~/.eco/queue/jobs.yaml`; prints added/skipped counts.
- **Uses:** `python -m scheduler.cli seed --dir <directory>`.

### `snapshot`

Capture ecosystem state into an immutable timestamped directory.

- **Args:** none.
- **Output:**
  - `~/.eco/snapshots/<YYYY-MM-DDTHH-MMZ>/` — raw layer outputs, assembled
    `state.json`, `map.md`, and `dashboard.html`.
  - `~/.eco/current` — atomic symlink update to the new snapshot.
- **Uses:** one parallel Gemini prompt-layer run per prompt in the selected
  prompt library. If any canonical prompt file is present, the snapshot
  manifest uses the fixed layer names `GA-hardware-llm`, `GB-ai-clients`,
  `GC-mcp`, `GD-hooks-plugins`, `GE-agents-memory`,
  `GF-toolkit-projects-external`, and `GG-wiring-behavior`; present canonical
  files are run and missing canonical files are skipped during execution.
  Non-canonical libraries use their own prompt filenames.
- **Invocation:** `gem-smart 3.5f` with MCP servers disabled when the wrapper is
  available; otherwise plain `gemini -p`. If `ECO_GEM_SMART_BIN` points at a
  non-resolving wrapper, the recipe still falls back to plain `gemini` when it
  is on `PATH`.
- **Env:** `GEMINI_LAYER_TIMEOUT_SEC` (default `180`), `ECO_GEM_SMART_BIN`,
  `ECO_AUDIT_ROOT`. When `ECO_AUDIT_ROOT` is set, prompt lookup is only
  `$ECO_AUDIT_ROOT/prompts`, and that directory must contain at least one
  layer prompt. When it is unset, lookup prefers
  `$HOME/.eco/ecosystem-audit/prompts` when populated, then the shipped
  `examples/snapshot-prompts/` library.
- **Lock:** uses a `mkdir`-based lock at `~/.eco/.snapshot.lock` to prevent
  concurrent runs.

```bash
src/recipes/snapshot.sh
```

### `swarm`

Dispatch N parallel Gemini agents on a task and synthesize results.

- **Args:** `<task description>` optional N (default 5).
- **Output:** `~/Documents/research/_swarm/<ts>/` with N agent outputs +
  a merged summary.
- **Model/invocation:** `gem-smart 3.5f` with
  `--allowed-mcp-server-names none` when the wrapper is available; otherwise
  plain `gemini -p`.

## Recipe contract

Maintained recipes should:

1. Begin with `#!/usr/bin/env bash` and `set -eu` (or `set -euo pipefail`).
2. Include metadata headers scanned by the widget and `eco list`:
   ```bash
   # DESC: <one-line description>
   # INPUTS: <args spec>
   # OUTPUT: <where results go>
   # USES: <which model/tool>
   # HUMAN: <what the human does vs. what the AI does>
   ```
3. Validate arguments and emit a one-line `usage:` to stderr on misuse.
4. Exit 0 on success.

`# DESC:` is the discovery key that `eco list` and the widget read. A recipe
may include additional human-readable headers such as `# Purpose:`; for example,
`hygiene.sh` starts with a `# Purpose:` line and still includes `# DESC:` and
`# INPUTS:` for discovery.

Recipes that call external APIs must:

- Read secrets from environment variables, never from disk (unless the tool
  uses a well-known credential file such as `~/.gemini/oauth_creds.json`).
- Redact secrets from any log output.
- Time out within 5 minutes unless explicitly overridden by the caller.
- Never log auth token contents (exception class name only, if logging at all).

## Related

- [Snapshots](./snapshots.md) — the snapshot recipe's output format and lifecycle
- [Scheduler](./scheduler.md) — `scheduler-seed` populates the scheduler queue
- [Architecture overview](../architecture.md)
- [Environment variables reference](../reference/environment-variables.md)
