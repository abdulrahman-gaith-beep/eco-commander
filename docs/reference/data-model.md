# Data Model

JSON schemas and file formats used by eco-commander. All paths are relative
to `ECO_HOME` (default: `~/.eco`).

## Snapshot: `state.json`

Written by `src/recipes/snapshot.sh` under
`snapshots/<YYYY-MM-DDTHH-MMZ>/state.json`.
This is a snapshot audit document — a structured report from the Gemini-powered
ecosystem snapshot, not a simple config file.

```json
{
  "schema_version": "0.2",
  "snapshot_id": "2026-05-31T23-57Z",
  "generated_at": "2026-05-31T23:57:44+03:00",
  "alert_model": {
    "source": "layer-local issues",
    "classifier": "regex-v0 candidates"
  },
  "alert_count": 13,
  "gate_status": {
    "G1_layers_present": "pass",
    "G7_freshness": "pass"
  },
  "overall_verdict": "assembled-with-warnings",
  "layers": {
    "GA_hardware_llm": {
      "state": "ok",
      "path": "layers/GA-hardware-llm.md",
      "bytes": 1521,
      "lines": 46,
      "issues": [{"severity": "high", "id": "GA-hardware-llm:46", "desc": "..."}]
    }
  },
  "sources": {}
}
```

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Snapshot schema version (current: `"0.2"`) |
| `snapshot_id` | string | Timestamp directory name from `date +%Y-%m-%dT%H-%MZ` |
| `generated_at` | ISO 8601 string | Local timestamp when the snapshot was written |
| `alert_model` | object | Metadata about the alert classifier used |
| `alert_count` | integer | Total number of issues across all layers |
| `gate_status` | object | Named gate checks and their `pass`/`fail` result |
| `overall_verdict` | string | `assembled` or `assembled-with-warnings` |
| `layers` | object | Per-layer audit results, keyed by layer ID |
| `layers.<id>.state` | string | `ok`, `missing`, `warn`, or `deprecated-aggregate` |
| `layers.<id>.path` | string | Relative path to the layer Markdown report |
| `layers.<id>.issues` | object[] | Per-issue findings with `severity`, `id`, and `desc` |
| `sources` | object | Source attribution metadata |

`src/recipes/snapshot.sh` emits `assembled-with-warnings` when it detects
layer issues or log warnings; otherwise it emits `assembled`.

## Usage: `usage.json`

Written by `src/poller/main.py` to `current/usage.json` every 60 seconds
(atomic write). This is the merged view read by the widget. Scheduler routing
does not read `usage.json`; it reads `state/notify.json`.

```json
{
  "ts": 1780600116,
  "duration_ms": 144,
  "version": 1,
  "claude": {
    "ok": true,
    "tool": "claude",
    "source": "jsonl",
    "plan": "Unknown",
    "accounts": 1,
    "configured_accounts": 0,
    "account_inventory": [],
    "session": {
      "pct": 0.0,
      "tokens": 0,
      "input_tokens": 0,
      "output_tokens": 0,
      "cache_creation_tokens": 0,
      "cache_read_tokens": 0,
      "by_model": {"opus": 0, "sonnet": 0, "haiku": 0, "other": 0},
      "cap": 1,
      "pace_glyph": "💤",
      "pace_label": "idle",
      "pace_delta_pp": 0.0,
      "target_pct": 0.0,
      "reset_epoch": 0,
      "resets_in": "—"
    },
    "weekly": {
      "pct": 0.0,
      "pct_all": 0.0,
      "pct_sonnet": 0.0,
      "tokens": 0,
      "input_tokens": 0,
      "output_tokens": 0,
      "cache_creation_tokens": 0,
      "cache_read_tokens": 0,
      "by_model": {"opus": 0, "sonnet": 0, "haiku": 0, "other": 0},
      "cap": 1,
      "cap_sonnet": 1,
      "pace_glyph": "💤",
      "pace_label": "idle",
      "pace_delta_pp": 0.0,
      "target_pct": 0.0,
      "reset_epoch": 0,
      "resets_in": "—"
    },
    "per_account": [
      {
        "slug": "primary",
        "plan": "Unknown",
        "source": "jsonl",
        "ok": true,
        "session": {"pct": 0.0, "tokens": 0, "cap": 1, "sessions": 0},
        "weekly": {"pct": 0.0, "tokens": 0, "cap": 1, "cap_sonnet": 1}
      }
    ]
  },
  "gemini": {
    "ok": false,
    "source": "jsonl",
    "plan": "Unknown",
    "accounts": 1,
    "configured_accounts": 0,
    "tiers": {
      "flash": {
        "model_id": "gemini-3-flash-preview",
        "pct": 0.0,
        "pace_glyph": "💤",
        "pace_label": "idle",
        "pace_delta_pp": 0.0,
        "target_pct": 0.0,
        "reset_epoch": 0,
        "resets_in": "—"
      },
      "flash_lite": {"model_id": "gemini-3.1-flash-lite-preview", "pct": 0.0},
      "pro": {"model_id": "gemini-3.1-pro-preview", "pct": 0.0}
    },
    "per_account": [
      {"slug": "primary", "ok": false, "plan": "Unknown", "source": "jsonl"}
    ],
    "per_account_note": "gemini-cli stores only the active account's OAuth on disk"
  },
  "codex": {
    "ok": false,
    "source": "jsonl",
    "plan": "Unknown",
    "accounts": 1,
    "configured_accounts": 0,
    "session": {
      "pct": 0.0,
      "tokens": 0,
      "input_tokens": 0,
      "cached_input_tokens": 0,
      "output_tokens": 0,
      "reasoning_output_tokens": 0,
      "cap": 1,
      "pace_glyph": "💤",
      "pace_label": "idle",
      "reset_epoch": 0,
      "resets_in": "—"
    },
    "weekly": {
      "pct": 0.0,
      "tokens": 0,
      "input_tokens": 0,
      "cached_input_tokens": 0,
      "output_tokens": 0,
      "reasoning_output_tokens": 0,
      "cap": 1,
      "by_model": {}
    },
    "auth": {"account_id_present": false}
  },
  "alternatives": {
    "ollama": {
      "ok": true,
      "category": "local_llm",
      "status": "always_available",
      "models": []
    },
    "cursor": {"ok": true, "category": "metered_alternative", "status": "stub"},
    "antigravity": {"ok": true, "category": "metered_alternative", "status": "stub"},
    "vs_code": {"ok": true, "category": "editor", "status": "always_available"}
  },
  "value": {
    "total_usd_7d": 0.0,
    "total_usd_30d": 0.0,
    "codex_credits_7d": 0.0,
    "multiplier": 0.0,
    "subscription_cost_monthly": null,
    "by_tool": {"claude": "no data", "codex": "no data", "gemini": "no data"},
    "by_model": {},
    "codex_credit_rates": {},
    "note": "Financial value unavailable until ECO_VALUE_MODEL_JSON points at a canonical financial model export."
  },
  "comment": "optional burn-rate commentary string — only present when ECO_COMMENTS=1"
}
```

### Top-level fields

| Field | Type | Description |
|-------|------|-------------|
| `ts` | integer | Unix epoch seconds when the poll cycle started |
| `duration_ms` | integer | Total poll duration in milliseconds |
| `version` | integer | Schema version (always `1`) |
| `claude` | object | Claude usage payload (see below) |
| `gemini` | object | Gemini usage payload (see below) |
| `codex` | object | Codex usage payload (see below) |
| `alternatives` | object | Available alternative providers (Ollama, Cursor, Antigravity) |
| `value` | object | USD-equivalent value block computed by `src/poller/value.py` |
| `comment` | string | Optional burn-rate commentary; only present when `ECO_COMMENTS=1` |

### Tool payload common fields

Each tool payload (`claude`, `gemini`, `codex`) shares these fields:

| Field | Type | Description |
|-------|------|-------------|
| `ok` | boolean | Whether the collector succeeded |
| `source` | string | `"api"` (OAuth/server-truth) or `"jsonl"` (local JSONL estimate) or `"error"` |
| `tool` | string | Tool name (`"claude"`, `"gemini"`, `"codex"`) |
| `error` | string | Exception class name only (no message — prevents token/URL leakage) |
| `stale` | boolean | Present and `true` when OAuth result is reused from prior cycle on transient failure |
| `stale_reason` | string | Error code that triggered staleness (`"http_429"`, `"network"`, etc.) |
| `oauth_fallback_reason` | string | Present on JSONL payloads when OAuth failed and fell back |

### Meter fields (session / weekly / tiers)

| Field | Type | Description |
|-------|------|-------------|
| `pct` | float | Percentage of cap consumed (0–100+; can exceed 100 for weekly JSONL) |
| `input_tokens` | integer | Input token count in the window |
| `output_tokens` | integer | Output token count in the window |
| `by_model` | object | Token breakdown by model family (`opus`, `sonnet`, `haiku`, `other`) |
| `pace_glyph` | string | Emoji pace indicator: `🟢` on-pace, `🐢` behind, `🐎` ahead, `💤` idle |
| `pace_label` | string | Text pace label: `on-pace`, `behind`, `ahead`, `idle`, `hard_wall` |
| `pace_delta_pp` | float | Percentage-points difference from expected pace (negative = behind) |
| `target_pct` | float | Expected percentage consumed at this point in the cycle |
| `reset_epoch` | integer | Unix epoch when this window resets |
| `resets_in` | string | Human-readable time until reset (e.g., `"4h 51m"`) or `"—"` if unknown |
| `cap` | integer | Token cap used for this window (present on JSONL payloads; neutral source default is `1`) |

### Account and plan metadata

Each tool payload includes configured account context stamped by
`src/poller/accounts.py`. Without `$ECO_HOME/accounts.json`, shipped account
inventory remains neutral and empty.

| Field | Type | Description |
|-------|------|-------------|
| `accounts` | integer | Account count used by the widget headline |
| `configured_accounts` | integer | Expected account count from `accounts.py` |
| `detected_accounts` | integer | Collector-detected count when it differs from configured count |
| `account_inventory` | object[] | Descriptive account lanes: `slug`, `plan`, `lane`, `priority` |
| `plan_events` | object[] | Dated subscription events with `effective_date`, `label`, `days_until`, `expired`, `imminent` |

### Per-tool files

| File | Producer | Contents |
|------|----------|----------|
| `current/usage-claude.json` | `src/poller/claude.py` + `claude_oauth.py` | Claude session/weekly meter data; per-account JSONL breakdown |
| `current/usage-gemini.json` | `src/poller/gemini.py` | Gemini Flash / Flash Lite / Pro tier fractions from `retrieveUserQuota`; per-account data |
| `current/usage-codex.json` | `src/poller/codex.py` + `codex_oauth.py` | Codex session/weekly token sums; token-type breakdown |

## Meter state: `notify.json`

Written by `src/poller/notify.py` to `state/notify.json`. Read by the
scheduler to determine provider availability for job dispatch.

```json
{
  "version": 1,
  "last_poll_ts": 1780600130,
  "meters": {
    "claude.session": {
      "current_kind": "healthy",
      "current_seen_ts": 1780600130,
      "last_kind": "unknown",
      "last_fired_ts": 1780599555,
      "last_fired_by_kind": {"use_it_or_lose_it": 1780599555},
      "last_reset_epoch": 1780599601
    },
    "claude.weekly": {
      "current_kind": "healthy",
      "current_seen_ts": 1780600130,
      "last_kind": "unknown"
    },
    "codex.session": {"current_kind": "healthy", "current_seen_ts": 1780600130, "last_kind": "unknown"},
    "codex.weekly":  {"current_kind": "healthy", "current_seen_ts": 1780600130, "last_kind": "unknown"},
    "gemini.tiers.flash":      {"current_kind": "healthy", "current_seen_ts": 1780600130, "last_kind": "unknown"},
    "gemini.tiers.flash_lite": {"current_kind": "healthy", "current_seen_ts": 1780600130, "last_kind": "unknown"},
    "gemini.tiers.pro":        {
      "current_kind": "hard_wall",
      "current_seen_ts": 1780600130,
      "last_kind": "hard_wall",
      "last_fired_ts": 1780600130,
      "last_fired_by_kind": {"hard_wall": 1780600130},
      "last_reset_epoch": 1780686518
    }
  },
  "last_comment_ts": {
    "gentle": 0.0,
    "bold": 0.0,
    "alarmed": 0.0
  }
}
```

### Top-level fields

| Field | Type | Description |
|-------|------|-------------|
| `version` | integer | Schema version (always `1`) |
| `last_poll_ts` | integer | Unix epoch when the notify module last ran; used for wake-from-sleep guard |

### Meter keys

The seven tracked meters correspond to notify.py's `METERS` list:

| Key | Tool | Window |
|-----|------|--------|
| `claude.session` | Claude | 5-hour rolling session |
| `claude.weekly` | Claude | 7-day rolling week |
| `codex.session` | Codex | 5-hour rolling session |
| `codex.weekly` | Codex | 7-day rolling week |
| `gemini.tiers.flash` | Gemini | Flash daily quota |
| `gemini.tiers.flash_lite` | Gemini | Flash Lite daily quota |
| `gemini.tiers.pro` | Gemini | Pro daily quota |

### Per-meter fields

| Field | Type | Description |
|-------|------|-------------|
| `current_kind` | string | Current state: `healthy`, `use_it_or_lose_it`, `throttle`, `hard_wall` |
| `current_seen_ts` | integer | Unix epoch when this state was last confirmed |
| `last_kind` | string | State from the previous cycle; `unknown` on first observation |
| `last_fired_ts` | integer | Unix epoch when any notification was last fired for this meter |
| `last_fired_by_kind` | object | Per-notification-type last-fired timestamps (keyed by kind) |
| `last_reset_epoch` | integer | Quota reset time from the most recent cycle; used for cycle-reset detection |

### Comment cooldown: `last_comment_ts`

When `ECO_COMMENTS=1`, `src/poller/comments.py` writes `last_comment_ts` to the
same `state/notify.json` file. This tracks per-tier cooldown timestamps for
burn-rate commentary so the same comment tier is not repeated too frequently.

| Field | Type | Description |
|-------|------|-------------|
| `last_comment_ts.gentle` | float | Unix epoch of the last gentle-tier comment |
| `last_comment_ts.bold` | float | Unix epoch of the last bold-tier comment |
| `last_comment_ts.alarmed` | float | Unix epoch of the last alarmed-tier comment |

## Job queue: `jobs.yaml`

Written by `src/scheduler/queue.py` to `queue/jobs.yaml`. The persisted queue
schema is a mapping with a `jobs` list root. `eco scheduler add --file` accepts
either a root list or `{jobs: [...]}` as import input, but `load_queue()` requires
the stored queue file to use the `{jobs: [...]}` root.

```yaml
version: 1
jobs:
  - id: "audit-snapshot-module"
    project: "eco-commander"
    workdir: "/path/to/your/repo"
    template: "raw_prompt"
    template_vars:
      prompt: "Audit the snapshot module"
    model_preference:
      - provider: codex
        model: gpt-5.5
        meter: codex.session
      - provider: gemini
        model: gemini-3-flash-preview
        meter: gemini.tiers.flash
    priority: P1
    timeout_s: 600
    retry:
      max: 3
      backoff_s: [60, 300, 1800]
    status: pending
    created_iso: "2026-05-11T08:00:00+03:00"
    requires_confirm: false
    depends_on_jobs: []
    notes: ""
```

### Job fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | string | required | Unique job identifier matching `[A-Za-z0-9][A-Za-z0-9._-]{0,127}` |
| `project` | string | `""` | Human-readable project label |
| `workdir` | string | `""` | Working directory for the job; must resolve to an existing directory, and privacy-sensitive paths are blocked |
| `template` | string | `"raw_prompt"` | Prompt template name (`raw_prompt`, `codegen-swift`, `research`, `audit`, etc.) |
| `template_vars` | object | `{}` | Template variable substitutions (including `prompt`) |
| `model_preference` | object[] | `[]` | Ordered ladder of `{provider, model, meter}` dicts |
| `earliest_iso` | string | `""` | ISO 8601 timestamp; job is held until this time |
| `priority` | string | `"P2"` | `P0` \| `P1` \| `P2` \| `P3` (P0 highest) |
| `timeout_s` | integer | `600` | Execution timeout in seconds (1–21600) |
| `retry` | object | `{max: 3, backoff_s: [60, 300, 1800]}` | Retry policy |
| `status` | string | `"pending"` | `pending` \| `running` \| `completed` \| `failed` \| `gated_by_quota` \| `cancelled` |
| `attempts` | object[] | `[]` | Attempt history with `iso`, `provider`, `model`, `meter`, `ok`, `error_kind`, `duration_s`, `log_path` |
| `created_iso` | string | now | ISO 8601 creation timestamp |
| `started_iso` | string | `""` | Set when first attempt begins |
| `completed_iso` | string | `""` | Set when the dispatcher marks a job `completed` or `failed` |
| `last_error` | string | `""` | Error kind from the most recent failed attempt |
| `requires_confirm` | boolean | `false` | If `true`, job waits for user confirmation before dispatch |
| `depends_on_jobs` | string[] | `[]` | Job IDs that must be `completed` before this job is ready |
| `notes` | string | `""` | Free-form operator notes |

## Directory structure summary

```text
~/.eco/
├── current -> snapshots/<YYYY-MM-DDTHH-MMZ>/  # symlink published by snapshot.sh
│   ├── state.json              # audit state document (schema v0.2)
│   ├── map.md                  # snapshot map
│   ├── dashboard.html          # rendered dashboard
│   ├── usage.json              # merged poller output, written through symlink
│   ├── usage-claude.json       # Claude usage detail, written through symlink
│   ├── usage-gemini.json       # Gemini usage detail, written through symlink
│   └── usage-codex.json        # Codex usage detail, written through symlink
├── snapshots/                  # immutable timestamped audit snapshots
│   └── <YYYY-MM-DDTHH-MMZ>/
│       ├── state.json          # audit state document (schema v0.2)
│       ├── map.md
│       ├── dashboard.html
│       └── layers/             # per-layer Markdown reports
├── state/
│   └── notify.json             # meter state; read by scheduler for routing
├── queue/
│   ├── jobs.yaml               # job queue (flock-protected atomic writes)
│   └── logs/                   # per-job execution logs (mode 0700)
├── logs/                       # LaunchAgent stdout/stderr logs (mode 0600)
│   ├── poller.log              # poller private error log (sanitized tracebacks)
│   ├── usage-poller.{out,err}.log
│   ├── scheduler.{out,err}.log
│   └── swiftbar-autostart.{out,err}.log
├── config/                     # optional user overrides
│   └── comments.json           # burn-rate comment catalog override
├── alert-runs/                 # alert action logs
├── fix-plans/                  # AI fix-planning workspaces
├── bin/                        # symlinks → src/bin/
├── recipes/                    # symlinks → src/recipes/
│   └── _outputs/<recipe>/<ts>/ # recipe output directories
└── config.json                 # optional poller configuration
```

> `current` is a symlink to the latest snapshot directory. The snapshot recipe
> publishes it via a temporary symlink swap; the poller writes live
> `usage*.json` files through that symlink.

## Related

- [configuration.md](./configuration.md) — Config files, neutral cap constants, and LaunchAgent plists
- [environment-variables.md](./environment-variables.md) — Variables that control poller and scheduler behavior
- [../subsystems/scheduler.md](../subsystems/scheduler.md) — Job dispatch, meter routing, and the adapter protocol
- [../subsystems/alerts.md](../subsystems/alerts.md) — Alert system that reads notify.json meter state
- [../subsystems/usage-monitor.md](../subsystems/usage-monitor.md) — Poller architecture and OAuth vs JSONL modes
