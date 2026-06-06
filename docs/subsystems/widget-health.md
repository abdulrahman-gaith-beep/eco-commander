# Widget Health Playbook

Eco Commander is healthy when the widget renders quickly, every alert is
traceable to evidence, fix actions are logged, and complex changes are planned
before any code is touched.

**Related docs:**
- [Widget Rendering diagram](../diagrams/widget-rendering.md)
- [Alert System](./alerts.md)

## Health contract

- The menu bar icon must remain lightweight: a single color-coded emoji
  (🟢/🟡/🔴) reflecting the worst signal across all meters, RAM, snapshot
  freshness, and active alerts.
- Live probes (Ollama, n8n, OpenClaw, Cortex, RAM) read local HTTP endpoints
  and process state but must never start services.
- Snapshot alerts are candidates until `eco-alerts.sh doctor` or a widget
  verifier confirms them.
- Every alert row must expose evidence before it exposes a fix action.
- Every fix launched from SwiftBar must run through `eco-alerts.sh run-logged`,
  unless it is a simple `open` action.
- Complex or cross-repository fixes must route to Gemini 3.1 Pro planning
  first. Implementation is left to Codex or Claude Code after the plan is
  reviewed by a human.

## Icon logic

The menu bar icon is set by `eco-commander.15s.sh` based on the worst of:

| Signal | Red 🔴 | Yellow 🟡 | Green 🟢 |
|--------|--------|-----------|---------|
| Quota (any meter) | ≥ 95% | 80–94% | < 80% |
| Available RAM | < 1 GB | < 4 GB | ≥ 4 GB |
| Snapshot age | ≥ 3 days | ≥ 1 day | < 1 day |
| Poller staleness | > 180s | — | ≤ 180s |
| Active alerts | (not applicable) | ≥ 1 active | 0 active |

## Alert states

| State | Meaning | Widget behavior |
|---|---|---|
| `active` | A live verifier confirms the issue is real right now | Show the fix action |
| `evidence` | Snapshot/log evidence shows a likely failure; a bounded rerun is the safest first step | Offer a bounded rerun |
| `triage` | No live verifier exists yet | Offer "Plan with Gemini Pro", not a blind patch |
| `resolved` | The live system now passes or a mitigation is present | Collapse under the cleared count unless `ECO_ALERT_SHOW_CLEARED=1` |

## Fix tiers

| Tier | Examples | Allowed action |
|---|---|---|
| Safe / idempotent | Add a detectable banner, open evidence, open logs | Direct command or `open` action |
| Bounded operations | Rerun snapshot, start n8n, refresh dashboard metrics, rebuild memory indexes | `run-logged` with verification and logs |
| Complex code fixes | Toolkit imports, cross-project router changes, missing packages, broad refactors | Gemini 3.1 Pro plan/orchestration first; Codex/Claude Code applies after review |

## Ollama count

The Ollama display is `loaded/installed`, not "models available to run."
`0/4` means Ollama has four installed models but none are currently resident.
That is normal when Ollama is idle.

If the count is always `0/0` while models are installed, check:

1. SwiftBar PATH includes `/opt/homebrew/bin` and `/usr/local/bin`.
2. Ollama daemon responds: `curl -s http://127.0.0.1:11434/`.
3. `ollama list` works in the same user account as SwiftBar.

Run `eco-alerts.sh debug-ollama` or use the widget's "Debug Ollama count"
action to print the exact binary path, daemon reachability, `ollama ps`,
and `ollama list`.

Models tagged `bge-m3` or `nomic-embed` are embedding-only (T0); they
are labelled "auto-loads" and cannot be pre-warmed.
Models ≥ `PREWARM_GB_LIMIT` GB (default 10) are labelled "heavy" and
do not offer a pre-warm action.

## Required health surface

The widget must always expose:

- README, docs index, architecture, usage, troubleshooting, this playbook, and changelog.
- Alert doctor and repo health check.
- Alert run logs (`~/.eco/alert-runs`) and AI fix workspaces (`~/.eco/fix-plans`).
- Snapshot rerun and dashboard refresh actions.

`eco-alerts.sh repo-health` is the authoritative health check: it verifies
all required files, expected CLIs, runtime symlinks, `state.json` validity,
widget renderability under restricted PATH, and lint when `shellcheck` is
available.

## Live runtime probes

The widget probes these local endpoints at each 15-second render cycle:

| Service | Probe | Port |
|---------|-------|------|
| Ollama | `http://127.0.0.1:11434/` | 11434 |
| OpenClaw | `http://127.0.0.1:18789/status` | 18789 |
| Cortex | `http://127.0.0.1:3000/` | 3000 |
| n8n | `http://127.0.0.1:5678/` | 5678 |

All probes use `-m 1` (1-second timeout) and do not start services on failure.

## MCP profile switcher

The widget enumerates `~/.ai-ecosystem/profiles/*.mcpServers.json` and
lets you switch profiles via `~/.ai-ecosystem/switch-profile.sh`. Current
profile is read from `~/.ai-ecosystem/.current-profile`.

## Data freshness thresholds

| Signal | Threshold | Action |
|--------|-----------|--------|
| `usage.json` stale | > 180s since `ts` | Show ⚠ STALE badge; kickstart poller |
| `state.json` age | > 1 day | Yellow icon |
| `state.json` age | > 3 days | Red icon; prompt snapshot rerun |

## 24/7 manager design

A 24/7 manager is possible, but must be a bounded operator, not an
autonomous patcher.

Recommended design:

1. A `launchd` job runs `snapshot.sh`, `eco-alerts.sh doctor`, and
   `eco-alerts.sh repo-health` on a schedule.
2. Results append to `~/.eco/alert-runs` and update a small status file
   for the widget.
3. Safe/idempotent and bounded fixes may run only when an allowlist says
   they are safe for that finding category.
4. Complex fixes create Gemini 3.1 Pro orchestration workspaces and stop
   there — a human decides whether to apply.
5. Codex or Claude Code applies code changes only in an interactive session
   with tests.
6. The manager never edits outside approved repositories and never deletes
   user data.

Acceptance criteria for a future manager:

- No duplicate overlapping runs; use lock files with stale-lock recovery.
- Every action has a log, exit code, start/end time, and evidence link.
- Alert counts distinguish live, evidence, triage, and resolved.
- Costly model calls have a throttle and a daily budget.
- Failed fixes produce a rollback note and a next-action recommendation.

## Related

- [Alert System](./alerts.md) — classification, fix tiers, environment variables
- [Usage Monitor](./usage-monitor.md) — produces `usage.json` the widget reads
- [Snapshots](./snapshots.md) — produces `state.json` the widget reads
- [Troubleshooting guide](../getting-started/troubleshooting.md)
- [Architecture overview](../architecture.md)
- [LaunchAgent best practices](./launchd-best-practices.md)
