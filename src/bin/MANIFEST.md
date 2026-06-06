# Bin Manifest — Shell CLI Layer

> **Directory**: `src/bin/` · **Language**: Bash · **Shell guards**: `set -u` (varies)

## CLI Dispatch Table (`eco` router)

| Command | Routes To | Description |
|---|---|---|
| `eco` / `eco list` | inline | List all recipes |
| `eco do <name> [args]` | `~/.eco/recipes/<name>.sh` | Run a recipe |
| `eco status` | `eco-commander.15s.sh --cli` | One-screen ecosystem state |
| `eco dashboard` | `open ~/.eco/current/dashboard.html` | Open dashboard |
| `eco map` | `open ~/.eco/current/map.md` | Open map |
| `eco audit` | `open ${ECO_AUDIT_DIR:-~/.eco/ecosystem-audit}` | Open configured audit root; set `ECO_AUDIT_DIR` if missing |
| `eco scheduler <sub>` | `python -m scheduler.cli` | Scheduler CLI |
| `eco hygiene <sub>` | `recipes/hygiene.sh` | Mac hygiene watcher |
| `eco account-swap <sub>` | `recipes/account-swap.sh` | Rotate auth |
| `eco help` | inline | Show help |
| `eco <name>` (fallback) | `recipes/<name>.sh` | Shortcut for `do` |

## Script Inventory

| Script | Size | Shell Guards | ShellCheck | Purpose |
|---|---|---|---|---|
| `eco` | 3.1K | `set -u` | ⚠️ Needs audit | CLI router |
| `eco-commander.15s.sh` | 37.3K | `set -euo pipefail` | ⚠️ Large, needs audit | SwiftBar plugin |
| `eco-alerts.sh` | 29.2K | varies | ⚠️ Needs audit | Alert subsystem |
| `ai-clear.sh` | <1K | `set -u` | ✅ Deprecated no-op | Legacy compatibility only |
| `install-commander.sh` | 2.2K | `set -euo pipefail` | ⚠️ Needs audit | Deploy symlinks |
| `ALERT_IDEAS.md` | 2.5K | — | — | Backlog doc |

## Known Issues

- **E9**: `install-commander.sh` doesn't verify SwiftBar plugin directory
- `eco-commander.15s.sh` at 37K is the largest source file — may benefit from function extraction
- `eco-alerts.sh` at 29K is the second largest — similar concern
