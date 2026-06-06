# Glossary

Domain terms used throughout eco-commander documentation and source code.
Entries are alphabetical. Each term links back to the subsystem or file where
the concept is defined or enforced.

| Term | Definition |
|------|-----------|
| **Adapter** | A Python module in `src/scheduler/adapters/` that implements the `Adapter` protocol. Each adapter knows how to fire a job on a specific provider (Claude, Codex, Gemini, Ollama). New adapters add a file to this directory and register it in `src/scheduler/adapters/__init__.py`. |
| **Alert** | A finding surfaced by a snapshot or live probe. Alerts pass through verification before the widget treats them as actionable. See [alerts.md](../subsystems/alerts.md) for the state machine. |
| **Alert doctor** | The `eco-alerts.sh doctor` subcommand that re-probes every snapshot finding and produces a verification report. |
| **Alternative** | A fallback AI provider tracked in `usage.json` under the `alternatives` key. Categories are `local_llm`, `metered_alternative`, and `editor`. Status is `always_available` (no quota) or `stub` (metered but not yet polled). |
| **Attempt** | One execution trial within a job. Stored in `jobs.yaml` under `attempts[]`. Fields include `provider`, `model`, `meter`, `ok`, `error_kind`, and `duration_s`. A failed attempt increments the retry count; a `hard_wall` failure does not count against the retry max. |
| **CLI router** | The `eco` script at `src/bin/eco` — a bash dispatcher that routes subcommands to recipes, the widget, or the scheduler. |
| **Collector** | A per-tool module (`claude.py`, `gemini.py`, `codex.py`) that fetches raw quota data from local files or OAuth APIs and returns a normalized dict. Collectors are composed by `main.py`. |
| **Cycle** | One quota billing period. Claude uses 5-hour sessions and 7-day weeks. Gemini uses 24-hour daily resets. Codex uses 5-hour sessions and 7-day weeks. The poller tracks `reset_epoch` for each window. |
| **Debounce** | Per-meter, per-notification-kind cooldown that prevents notification spam. Durations are in `src/poller/pace.py:DEBOUNCE_HOURS`. |
| **Delegate fix** | Routing a complex alert fix to Gemini Pro for planning before applying code changes. Creates a workspace under `~/.eco/fix-plans/`. |
| **Discovery** | `src/poller/discovery.py` — detects the current user, home paths, account counts, and plan configuration. The OSS-readiness foundation: no hardcoded usernames. |
| **Fix tier** | Classification of a remediation action by risk: safe/idempotent, bounded operations, or complex code fixes. See [widget-health.md](../subsystems/widget-health.md). |
| **Gate** | A named validation check in the snapshot's `gate_status` object (e.g., `G1_layers_present`, `G7_freshness`). Gate failures contribute findings; the snapshot verdict is still limited to `assembled` or `assembled-with-warnings`. |
| **Hard wall** | A meter state indicating quota exhaustion (≥ 95%). The scheduler skips the ladder rung and does not count the attempt against the job's retry max. Corresponds to `current_kind: "hard_wall"` in `notify.json`. |
| **Job** | A unit of work in the scheduler queue. Defined in YAML with an `id`, `model_preference` ladder, `priority`, and `timeout_s`. See [data-model.md](./data-model.md) for the full schema. |
| **JSONL mode** | Local token estimation from Anthropic / OpenAI JSONL conversation logs. Less accurate than server-truth but requires no OAuth credentials. Selected when `server_truth_enabled()` returns `false`. |
| **Ladder** | The `model_preference` list on a job. The scheduler walks the ladder top-to-bottom, firing via the first provider whose meter is `use_it_or_lose_it`, `on-pace`, or `healthy`. |
| **LaunchAgent** | A macOS `launchd` plist that runs a program on a schedule or at login. eco-commander uses three: usage poller, scheduler, SwiftBar autostart. |
| **Layer** | A section of the ecosystem snapshot audit document (e.g., `GA_hardware_llm`, `GC_mcp`). Each layer produces issues with severity. The special `Linf_wiring` layer is a deprecated compatibility aggregate. |
| **Log-only mode** | Default operating mode for the notify module (`ECO_NOTIFY_LOG_ONLY=1`). Notification decisions are logged but `osascript` is never called. Flip to `0` when ready to receive desktop notifications. |
| **Meter** | A quota tracker keyed in `~/.eco/state/notify.json`. Each meter represents one provider/tier's quota window (e.g., `gemini.tiers.flash`, `codex.session`). Seven meters are tracked: two Claude, two Codex, three Gemini. |
| **Meter kind** | Current quota state of a meter: `use_it_or_lose_it` (early in cycle, headroom remaining), `throttle` (high utilization, slow down), `hard_wall` (quota exhausted), `healthy` (nominal). |
| **Multiplier** | The ratio of API-equivalent USD value to monthly subscription cost. Computed by `src/poller/value.py` only when `ECO_VALUE_MODEL_JSON` points at a canonical external financial-model export. Values above `1.0` mean estimated API-equivalent value exceeds the configured subscription cost. |
| **OAuth mode** | Server-truth polling via the provider's OAuth API. Enabled per-tool via `~/.eco/config.json:server_truth.<tool>: true`. More accurate than JSONL; requires credentials. |
| **Pace** | A time-normalized assessment of quota consumption rate, computed by `src/poller/pace.py`. A meter is `on-pace` if actual consumption matches the expected fraction of the window elapsed. |
| **Pace delta (pp)** | Percentage-points difference between actual consumption and expected pace (`pace_delta_pp` in meter objects). Negative means behind pace; positive means ahead. |
| **Pace glyph** | Colorblind-safe emoji that summarizes pace: `🟢` on-pace, `🐢` behind, `🐎` ahead, `💤` idle, `⚠️` hard-wall imminent. |
| **Per-account breakdown** | The `per_account[]` array in Claude and Gemini payloads. Each entry has `slug`, `plan`, `source`, and per-window token/pct data for one credential lane. |
| **Poller** | The Python module at `src/poller/` that collects plan-quota data from Claude, Gemini, and Codex every 60 seconds via a LaunchAgent. |
| **Probe** | A live check performed by the widget or alert doctor — reads process state, HTTP endpoints, or file timestamps to verify a finding. |
| **Recipe** | A standalone bash script under `src/recipes/` that performs a repeatable workflow. Invoked via `eco do <name>`. |
| **Recipe contract** | The rules every recipe must follow: `set -euo pipefail`, `# DESC:` header, output under `_outputs/<recipe>/<ts>/`, exit 0 on success. |
| **Repo health** | The `eco-alerts.sh repo-health` check that audits docs, changelog, runtime links, expected commands, and widget renderability. |
| **Reset epoch** | Unix timestamp when a quota window resets. Stored as `reset_epoch` on meter objects. Used by the notify module for cycle-reset detection. |
| **Rung** | A single entry in a job's `model_preference` ladder: `{provider, model, meter}`. |
| **Scheduler** | The Python module at `src/scheduler/` that dispatches queued jobs to AI providers based on quota availability from `notify.json`. |
| **Server truth** | Quota data sourced from the provider's own API (OAuth). Authoritative for percentages and reset windows. Contrasts with JSONL-estimate mode. |
| **Snapshot** | An immutable, timestamped audit of ecosystem state written under `~/.eco/snapshots/<UTC ISO>/`. Contains `state.json` and layer Markdown reports. |
| **Stale** | A meter payload recycled from the prior poll cycle when a transient OAuth failure occurs (e.g., `http_429`, `network`). Marked with `stale: true` and `stale_reason`. |
| **SwiftBar** | A macOS menu-bar app that runs shell plugins at a cadence set by the filename suffix (e.g., `.15s.sh` = every 15 seconds). |
| **Tick** | One pass of the scheduler dispatcher. Reads the queue, checks meters, fires up to `ECO_MAX_JOBS_PER_TICK` jobs, persists results. |
| **Toggle-precise** | `scripts/toggle-precise.sh` — flips `server_truth` in `config.json` for a single tool. Requires `ECO_ALLOW_LIVE_CREDENTIAL_PROBE=1` to proceed. |
| **Value block** | The `value` key in `usage.json`, computed by `src/poller/value.py`. Reports API-equivalent USD value by tool and model, Codex credit estimates, and the subscription multiplier. |
| **Verdict** | The `overall_verdict` field in `state.json`. One of `assembled` or `assembled-with-warnings`. Determines the widget's top-level status color. |
| **Wake guard** | A skip-evaluation rule in the notify module: if more than 5 minutes elapsed since the last poll (laptop sleep), skip notifications for that cycle to prevent a flood of stale alerts. |
| **Widget** | The SwiftBar plugin (`src/bin/eco-commander.15s.sh`) that renders ecosystem status in the macOS menu bar every 15 seconds. |

## Related

- [data-model.md](./data-model.md) — JSON schemas referenced by many terms above
- [configuration.md](./configuration.md) — Config files that control server-truth and caps
- [environment-variables.md](./environment-variables.md) — Variables that enable/disable features referenced here
- [../subsystems/scheduler.md](../subsystems/scheduler.md) — Job, ladder, rung, adapter, meter in action
- [../subsystems/alerts.md](../subsystems/alerts.md) — Alert, probe, fix tier, delegate fix lifecycle
- [../subsystems/usage-monitor.md](../subsystems/usage-monitor.md) — Collector, pace, JSONL mode, OAuth mode
