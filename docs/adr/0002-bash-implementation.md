# ADR 0002 — Implement Core in Bash, Not Python

| Field  | Value |
|--------|-------|
| Status | Accepted (amended by [ADR 0004](./0004-usage-monitor-python-carveout.md)) |
| Date   | 2026-04-27 |

## Context

`eco-commander` glues together CLIs (Claude Code, Gemini CLI, Ollama, docker,
jq, git) and runs as a SwiftBar menu-bar plugin. SwiftBar plugins must execute
quickly and have no install step — any virtualenv setup or package download
would block the menu bar on first run.

## Decision

Implement the router (`src/bin/eco-commander.15s.sh`), SwiftBar plugin, and all
recipes (`src/recipes/*.sh`) in Bash 5. Use Python only when a recipe
genuinely needs structured data manipulation that `jq` cannot express.

```text
src/
├── bin/
│   └── eco-commander.15s.sh   # Bash — SwiftBar renderer
└── recipes/
    └── *.sh                   # Bash — all recipe scripts
```

## Consequences

**Positive:**
- Zero install overhead on macOS (Bash 5 ships via Homebrew on all supported
  systems; `jq` is declared in `Brewfile`).
- Fast cold start — essential for a 15-second SwiftBar refresh cycle.
- Trivial SwiftBar integration: the plugin is a plain executable.
- No virtualenv to manage for the hot path.

**Negative:**
- Harder to write large-scale logic; weaker type safety.
- Mitigated with `shellcheck`, `set -euo pipefail` in every script, and a
  Bats test suite (`tests/bats/`).

**Constraint:** all shell scripts must be `shellcheck`-clean (enforced in CI).

## Related

- Amended by [ADR 0004](./0004-usage-monitor-python-carveout.md) which adds a
  Python carve-out for `src/poller/` and (via ADR 0005) `src/scheduler/`.
