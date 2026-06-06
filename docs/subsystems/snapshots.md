# Snapshots

Immutable point-in-time captures of the full AI ecosystem state. Each
snapshot is a directory of Gemini-generated layer reports, assembled by a
Python assembler into `state.json`, `map.md`, and `dashboard.html`. The
`~/.eco/current` symlink always points to the latest snapshot.

**Related docs:**
- [Snapshot Lifecycle diagram](../diagrams/snapshot-lifecycle.md)
- [Recipes](./recipes.md) — the `snapshot` recipe triggers a new capture
- [Alert System](./alerts.md) — reads `state.json` to classify findings
- [ADR 0003 — Snapshot immutability](../adr/0003-snapshot-immutability.md)

## Lifecycle

1. `src/recipes/snapshot.sh` acquires a `mkdir`-based lock at
   `~/.eco/.snapshot.lock` (with stale-lock recovery).
2. It creates a fresh directory `~/.eco/snapshots/<YYYY-MM-DDTHH-MMZ>/`.
3. Prompt-layer runs execute in parallel, each with a
   `GEMINI_LAYER_TIMEOUT_SEC` (default 180s) timeout. The recipe prefers
   `gem-smart 3.5f -p <prompt> -y --allowed-mcp-server-names none`; when the
   configured/default wrapper path does not resolve and plain `gemini` is on
   `PATH`, it falls back to `gemini -p <prompt>`. If neither backend is
   available, the recipe exits non-zero with an installation hint.

   A canonical prompt library may define these seven domain layers:

   | Layer | Domain |
   |-------|--------|
   | `GA-hardware-llm` | Local hardware and LLMs |
   | `GB-ai-clients` | AI client applications |
   | `GC-mcp` | MCP server wiring |
   | `GD-hooks-plugins` | Hooks and plugins |
   | `GE-agents-memory` | Agents and memory |
   | `GF-toolkit-projects-external` | Toolkit, projects, external services |
   | `GG-wiring-behavior` | Cross-system wiring and behavior |

4. A Python assembler reads the layer outputs and produces:
   - `state.json` — structured finding list with per-layer metadata
   - `map.md` — human-readable summary of layer states and issues
   - `dashboard.html` — self-contained HTML dashboard
5. `~/.eco/current` is atomically updated as a symlink pointing at the new
   snapshot via a temporary symlink + `mv`.
6. Older snapshots are never modified.

## Directory layout

```text
~/.eco/snapshots/
├── 2026-05-11T14-30Z/
│   ├── layers/
│   │   ├── GA-hardware-llm.md
│   │   ├── GA-hardware-llm.log
│   │   ├── GB-ai-clients.md
│   │   ├── GB-ai-clients.log
│   │   └── ...  (one .md/.log pair per prompt layer)
│   ├── state.json
│   ├── map.md
│   └── dashboard.html
├── 2026-04-24T00-55Z/
│   └── ...
└── 2026-04-17T22-11Z/
    └── ...
~/.eco/current  ──►  ~/.eco/snapshots/2026-05-11T14-30Z/
```

## `state.json` schema (v0.2)

```json
{
  "schema_version": "0.2",
  "snapshot_id": "2026-05-11T14-30Z",
  "generated_at": "2026-05-11T14:30:45+03:00",
  "alert_model": {
    "source": "layer-local issues with Linf_wiring compatibility aggregate",
    "classifier": "regex-v0 candidates; widget/eco-alerts performs live verification where available"
  },
  "alert_count": 1,
  "gate_status": {
    "G1_layers_present": "pass",
    "G7_freshness": "pass"
  },
  "overall_verdict": "assembled-with-warnings",
  "layers": {
    "GA_hardware_llm": {
      "state": "ok",
      "path": "layers/GA-hardware-llm.md",
      "bytes": 4200,
      "lines": 87,
      "issues": [
        {
          "severity": "med",
          "id": "GA-hardware-llm:23",
          "desc": "bge-m3 model not found in ollama list",
          "source_layer": "GA-hardware-llm",
          "source_path": "layers/GA-hardware-llm.md",
          "classifier": "regex-v0",
          "status": "candidate"
        }
      ]
    }
  },
  "sources": {
    "raw_layers": ["layers/GA-hardware-llm.md", "..."],
    "logs_with_warnings": []
  }
}
```

Layer `state` values are emitted by `src/recipes/snapshot.sh`:

- `ok` — the layer markdown exists and is non-empty.
- `missing` — the layer has no markdown output.
- `warn` — the layer log matches the issue classifier regex.
- `deprecated-aggregate` — used only for the compatibility
  `layers.Linf_wiring` aggregate.

`overall_verdict` is `assembled` when no layer issues or warning logs are
detected, otherwise `assembled-with-warnings`.

Issues carry `status: "candidate"` — they are snapshot-derived and unverified.
The alert system (`eco-alerts.sh`) runs live verifiers at query time to promote
candidates to `active`, `evidence`, `triage`, or `resolved`.

The `Linf_wiring` compatibility aggregate key is present for backward
compatibility with older widget code that expected a flat issue list at the top
level. New code should iterate `layers.<key>.issues`.

## Issue classifier

The regex-based classifier (`regex-v0`) flags lines containing:
`error`, `fail`, `failed`, `missing`, `not found`, `unreachable`,
`stale`, `warning`, `warn`, `todo`, `incomplete`, or `manual` (case-insensitive).

Lines shorter than 12 characters or matching only whitespace are skipped.
A maximum of 50 issues are collected per snapshot to keep `state.json`
manageable.

High-severity issues contain: `error`, `fail`, `missing`, `not found`, or
`unreachable`. All others are `med` severity.

## Retention

Snapshots accumulate indefinitely. To prune old snapshots:

```bash
# Preview snapshots older than 90 days
find ~/.eco/snapshots -mindepth 1 -maxdepth 1 -type d -mtime +90 -print

# After reviewing the list, remove individual directories
# (do not use -delete or -exec rm on the find output without reviewing)
```

Never delete `~/.eco/current` directly. If it is missing or broken,
recreate it by running a new snapshot: `src/recipes/snapshot.sh`.

## Triggering a snapshot

Prompt resolution:

- If `ECO_AUDIT_ROOT` is set, the recipe reads prompts from
  `$ECO_AUDIT_ROOT/prompts`.
- If `ECO_AUDIT_ROOT` is unset and `~/.eco/ecosystem-audit/prompts` contains
  layer prompts, the recipe uses that local runtime library.
- Otherwise, source-tree and symlinked installs fall back to the public example
  library at `examples/snapshot-prompts`.

The public example library has two generic prompt layers. If the selected
library contains any canonical prompt file, the recipe treats it as canonical:
the manifest uses the seven domain-layer names listed above, present canonical
files are run, and missing canonical files are skipped during execution. If no
canonical prompt file is present, every `*.md` prompt except `README.md` and
`_SHARED.md` is run by filename. `_SHARED.md` is optional and is prepended to
each layer prompt when present.

Backend resolution:

- Uses `${ECO_GEM_SMART_BIN:-$HOME/bin/gem-smart}` when it resolves to an
  executable wrapper.
- If that configured/default wrapper path does not resolve, falls back to
  plain `gemini` on `PATH`.
- If neither `gem-smart` nor plain `gemini` is available, exits with an
  actionable installation/configuration error.

```bash
# Direct
src/recipes/snapshot.sh

# Via eco-alerts.sh (runs in background with logging)
~/.eco/bin/eco-alerts.sh run-logged fix-snapshot-timeout

# Via widget Quick Actions menu
# "Run snapshot now"
```

## Related

- [Recipes](./recipes.md) — full snapshot recipe contract and other recipes
- [Alert System](./alerts.md) — reads `state.json` and classifies findings
- [Widget Health](./widget-health.md) — snapshot age thresholds for icon color
- [Architecture overview](../architecture.md)
