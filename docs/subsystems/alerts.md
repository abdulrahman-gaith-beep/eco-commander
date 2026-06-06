# Alert System (`eco-alerts.sh`)

Evidence-backed local operations router that triages snapshot findings, runs
live verifiers, and exposes targeted fix actions for conditions that threaten
AI tool continuity, quota value, scheduled work, or workstation health.

`src/bin/eco-alerts.sh` owns alert normalization, live verification,
diagnostics, remediation, and repository health checking. The SwiftBar widget
calls `widget-issues` so menu rendering and `doctor` use the same
classification contract instead of duplicating alert logic.

**Related docs:**
- [Alert Pipeline diagram](../diagrams/alert-pipeline.md)
- [Widget Health playbook](./widget-health.md)

## Subcommands

| Subcommand | Description |
|---|---|
| `doctor` | Audit every snapshot finding — runs live verifiers, prints `[active/resolved/triage]` for each, and lists the recommended fix action. Writes a timestamped run log under `~/.eco/alert-runs/`. |
| `widget-issues` | Emit normalized TSV rows for the SwiftBar Alerts section. Reads `state.json`, runs the same classifiers as `doctor`, and outputs one `META` row then one `ISSUE` row per finding. |
| `repo-health` | Audit the repository itself: docs, changelog, runtime symlinks, expected CLIs, current `state.json` validity, widget renderability under restricted PATH, and lint (when `shellcheck` is available). |
| `debug-ollama` | Print the exact Ollama binary path, daemon reachability, `ollama ps`, and `ollama list`. Use when the widget shows `0/0` but models are installed. |
| `run-logged <action> [args]` | Run a bounded alert action in the background with timestamped stdout/stderr/exit logging under `~/.eco/alert-runs/`. Opens the log in Terminal (unless `ECO_ALERT_OPEN_TERMINAL=0`). |
| `delegate-fix <issue-id>` | Route a complex fix to Gemini 3.1 Pro planning. Creates a workspace under `~/.eco/fix-plans/` containing sanitized evidence, an issue JSON extract, and a structured prompt. Runs Gemini asynchronously; produces `gemini-plan.md`. |
| `orchestrate-fix <issue-id>` | Multi-agent version of `delegate-fix`. Runs 3–6 parallel Gemini Pro evaluators (evidence verifier, implementation strategist, risk reviewer, etc.) then synthesizes a final plan. |
| `open-source <issue-id>` | Open the source layer markdown file behind a snapshot finding. |
| `open-state` | Open `~/.eco/current/state.json` in the default app. |
| `open-dashboard` | Open `~/.eco/current/dashboard.html` in the default browser. |
| `fix-snapshot-timeout` | Rerun `snapshot.sh` to replace findings that stem from Gemini timeouts or quota failures. |
| `fix-n8n` | Start n8n via Docker Compose. Reads `ECO_N8N_COMPOSE` or falls back to the preferred compose path. |
| `fix-dashboard-refresh` | Refresh dashboard metric placeholders via `recipes/dashboard-refresh.sh`. |
| `fix-memory-router` | Legacy: create a `toolkit.memory.router` compatibility adapter. Disabled by default; routes to `delegate-fix` unless `ECO_ALLOW_DIRECT_COMPLEX_FIX=1`. |
| `fix-guide-stale` | Insert a stale-count banner into `~/ai-ecosystem-guide.html`. |
| `rebuild-memory-indexes` | Run `memory_router.py --build-all`. |

Allowed actions for `run-logged` are hard-coded in the script to prevent
injection: `doctor`, `repo-health`, `debug-ollama`, `delegate-fix`,
`orchestrate-fix`, `run-recipe`, `fix-snapshot-timeout`, `fix-n8n`,
`fix-memory-router`, `fix-dashboard-refresh`, `fix-guide-stale`,
`rebuild-memory-indexes`.

## Alert model

Every snapshot finding goes through a live-verification pipeline before the
widget treats it as actionable. Severity, state, and category are separate so
the menu can distinguish "urgent and verified" from "interesting but stale."

### Alert states

| State | Meaning | Widget behavior |
|---|---|---|
| `active` | A live verifier confirms the issue is real right now | Show the fix action |
| `evidence` | Snapshot/log evidence indicates a likely failure; a bounded rerun is the safest first step | Offer a bounded rerun |
| `triage` | No live verifier exists yet | Offer "Plan with Gemini Pro", not a blind patch |
| `resolved` | The live system now passes or a mitigation is present | Collapse under the cleared count unless `ECO_ALERT_SHOW_CLEARED=1` |

### Priority mapping

| Priority | Meaning |
|---|---|
| `P1` | Action needed soon: live/active alert, expected service offline, hard quota wall |
| `P2` | Watch item: evidence-backed rerun candidate, high-severity unverified finding |
| `P3` | Info / cleared / maintenance context |

### Alert categories

| Category | Examples |
|---|---|
| `quota` | Claude/Gemini/Codex pace, reset windows, hard walls |
| `scheduler` | Failed/gated jobs, stale running jobs, scheduler launch state |
| `service` | n8n, Ollama daemon, local runtime endpoints |
| `recipe` | Recipe failures, missing metadata, stale recipe outputs |
| `workstation` | RAM, swap, stuck Gemini processes, MCP process pressure |
| `data-freshness` | Stale or malformed `usage.json`, `state.json`, `notify.json`, dashboard/guide drift |
| `repo-ops` | Repo health, docs drift, missing executable/symlink, lint/test health |

### Built-in live verifiers

| Finding pattern | Verifier | Resolution when live check passes |
|---|---|---|
| Contains "n8n" | `curl -s -m 2 $N8N_URL` | `resolved` (n8n responds) |
| Contains "n8n" + n8n not expected | `ECO_N8N_EXPECTED != 0` | `resolved` (on-demand service, not required) |
| Contains `toolkit.memory.router` / memory router | `python3 importlib.util.find_spec(...)` | `resolved` (importable) |
| Contains `ai-ecosystem-guide.html` / dashboard stale | `grep eco-alert-stale-counts-banner` | `resolved` (banner present) |
| Contains `rc=124` / timeout / quota | Regex match | `evidence` (rerun is the fix) |
| Any other finding | (none) | `triage` (Gemini Pro planning) |

## Fix tiers

Fixes launched from the widget or CLI are tiered by risk:

| Tier | Examples | Allowed action |
|---|---|---|
| Safe / idempotent | Add a detectable banner, open evidence, open logs | Direct command or `open` action |
| Bounded operations | Rerun snapshot, start n8n, refresh dashboard metrics, rebuild memory indexes | `run-logged` with verification and local logs |
| Complex code fixes | Toolkit imports, cross-project router changes, missing packages, broad refactors | `delegate-fix` → Gemini 3.1 Pro plan first; Codex/Claude Code applies later |

## Widget integration

Each alert row in the SwiftBar widget exposes:

- **Open evidence** — opens the source layer markdown for the finding
- **Fix: …** — runs the targeted remediation helper through `run-logged`
- **Alert doctor** — runs `eco-alerts.sh doctor` to audit all findings
- **Repo health check** — runs `eco-alerts.sh repo-health`

Widget headline format:

```text
⚠ 2 Alerts
-- 1 live · 0 evidence · 1 triage · 4 cleared · 6 total
```

Cleared rows are hidden by default. Set `ECO_ALERT_SHOW_CLEARED=1` while
debugging to inspect them.

## Fix workspaces

`delegate-fix` and `orchestrate-fix` create timestamped workspaces under
`~/.eco/fix-plans/` containing:

| File | Contents |
|------|---------|
| `evidence.md` | Formatted evidence summary with live check results |
| `issue.json` | Issue record extracted from `state.json` |
| `state.json` | Full snapshot state at triage time |
| `source-layer.md` | Source layer markdown when available |
| `prompt.md` | Structured Gemini prompt |
| `gemini-plan.md` | Gemini evaluation output |
| `agent-<n>.md` | Per-agent evaluation outputs (orchestrate mode) |
| `agent-bundle.md` | All agent outputs concatenated |
| `synthesis.md` | Multi-agent synthesis (orchestrate mode) |

Do not paste raw workspaces into external AI tools. Use redacted snippets
or fixtures for agent-assisted review.

## File locations

| Path | Purpose |
|------|---------|
| `src/bin/eco-alerts.sh` | Source — all alert logic |
| `~/.eco/bin/eco-alerts.sh` | Runtime symlink (created by `make install`) |
| `~/.eco/alert-runs/` | Timestamped alert action logs |
| `~/.eco/fix-plans/` | AI fix-planning workspaces |

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECO_COMMANDER_REPO` | Auto-detected | Path to the eco-commander repository root |
| `ECO_ALERT_OPEN_TERMINAL` | `1` | Set to `0` to suppress Terminal windows during automated runs |
| `ECO_ALERT_SHOW_CLEARED` | `0` | Show resolved alert rows in the widget |
| `ECO_N8N_EXPECTED` | `1` | Treat local n8n as a required service; set to `0` for on-demand use |
| `ECO_N8N_COMPOSE` | (none) | Path to n8n Docker Compose file |
| `ECO_N8N_STATUS` | (none) | Pre-computed n8n status (`online`/`offline`) passed by the widget |
| `GEMINI_FIX_MODEL` | `gemini-3.1-pro-preview` | Model used for `delegate-fix` and `orchestrate-fix` |
| `GEMINI_FIX_AGENTS` | `3` | Number of parallel agents in `orchestrate-fix` (2–6) |
| `ECO_ALLOW_DIRECT_COMPLEX_FIX` | `0` | Set to `1` to bypass Gemini planning for `fix-memory-router` |
| `ECO_FORCE_MEMORY_ROUTER_MISSING` | `0` | Testing: force the memory-router-missing alert to appear |

## Usage examples

```bash
# Full alert audit
~/.eco/bin/eco-alerts.sh doctor

# Repository health check
~/.eco/bin/eco-alerts.sh repo-health

# Diagnose Ollama count discrepancy
~/.eco/bin/eco-alerts.sh debug-ollama

# Run a fix with logging (opens Terminal)
~/.eco/bin/eco-alerts.sh run-logged repo-health

# Delegate a complex fix to Gemini Pro planning
~/.eco/bin/eco-alerts.sh delegate-fix GE-agents-memory:42

# Multi-agent evaluation
~/.eco/bin/eco-alerts.sh orchestrate-fix GC-mcp:17
```

## Related

- [Widget Health playbook](./widget-health.md) — full health playbook and 24/7 manager design
- [Snapshots](./snapshots.md) — produces the `state.json` this system reads
- [Troubleshooting guide](../getting-started/troubleshooting.md)
- [Architecture overview](../architecture.md)
- [Environment variables reference](../reference/environment-variables.md)
