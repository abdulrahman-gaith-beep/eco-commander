# Recipes Manifest — Task Pipelines

> **Directory**: `src/recipes/` · **Language**: Bash
> **Discovery**: Auto-discovered by `eco list` via `# DESC:` header scan

## Recipe Catalog

| Name | DESC | INPUTS | OUTPUT | USES | Status |
|---|---|---|---|---|---|
| `ask` | One-shot Q&A | `<question>` | stdout | Gemini/Ollama | ✅ Complete |
| `research` | Multi-source research | `<topic>` | `~/Documents/research/` | gem-smart or Gemini CLI | ✅ Complete |
| `swarm` | Dispatch parallel agents | `<task> [N=5]` | `~/Documents/research/_swarm/` | gem-smart or Gemini CLI | ✅ Complete |
| `note` | Append journal note | `<content>` / `$EDITOR` | `~/.ai-memory/spaces/` | filesystem | ✅ Complete |
| `snapshot` | Prompt-layer ecosystem scan | none | `~/.eco/snapshots/` | gem-smart or Gemini CLI | ✅ Complete |
| `arabic-proof` | Arabic proofreading | `<file>` / stdin | stdout | Ollama qwen3.6 default | ✅ Complete |
| `dashboard` | Open dashboard | none | browser | `open` | ✅ Complete |
| `dashboard-refresh` | Inject live metrics | none | `~/.eco/current/dashboard.html` | python3/sed | ✅ Complete |
| `account-swap` | Rotate CLI auth | `list` / `<tool> <slug>` | Keychain + filesystem | macOS Keychain | ✅ Complete |
| `hygiene` | Mac hygiene watcher | `watch\|snapshot\|stop\|status\|tail` | `~/.eco/hygiene/` | macOS monitors | ✅ Complete |
| `n8n-start` | Start n8n | none | Docker/npx | Docker Compose | ✅ Complete |
| `scheduler-seed` | Seed scheduler queue | `[directory]` | `~/.eco/queue/jobs.yaml` | scheduler CLI | ✅ Complete |

## Header Compliance

Required headers per recipe (scanned by `eco list`):
- `# DESC:` — one-line description (**required**)
- `# INPUTS:` — argument spec (optional)
- `# OUTPUT:` — where results go (recommended)
- `# USES:` — which model/tool (recommended)
- `# HUMAN:` — what human does vs AI (recommended)

| Recipe | DESC | INPUTS | OUTPUT | USES | HUMAN |
|---|---|---|---|---|---|
| `ask.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `research.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `swarm.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `note.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `snapshot.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `arabic-proof.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `dashboard.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `dashboard-refresh.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `account-swap.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `hygiene.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `n8n-start.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `scheduler-seed.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |

## External Dependencies

| Recipe | Required Tools | Available Check |
|---|---|---|
| `ask.sh` | `gem-smart` or `gemini`; `ollama` for private cues | `command -v gemini` / `command -v ollama` |
| `research.sh` | `gem-smart` or `gemini` | `command -v gemini` |
| `swarm.sh` | `gem-smart` or `gemini` | `command -v gemini` |
| `arabic-proof.sh` | `ollama` + current Arabic-capable model (`qwen3.6:latest` default, `ECO_ARABIC_PROOF_MODEL` or `ECO_ARABIC_MODEL` override) | `ollama list` |
| `snapshot.sh` | `gem-smart` or `gemini`, plus snapshot prompts from `examples/snapshot-prompts/` or `ECO_AUDIT_ROOT` | `command -v gemini` |
| `dashboard-refresh.sh` | `python3`, `sed` | `command -v python3` |
| `account-swap.sh` | `security` (macOS), `gemini`, `claude` | macOS native |
| `hygiene.sh` | `vm_stat`, `sysctl`, `pgrep` | macOS native |
| `n8n-start.sh` | `docker` or `npx` | `which docker` / `which npx` |
| `scheduler-seed.sh` | `python3`, `scheduler` module | Python in PATH |

## Design Principles (from README.md)

1. **Agents should not shop for tools.** The recipe pre-selects.
2. **Cost-aware by default.** Prefer lower-cost Gemini routes for broad work.
3. **Privacy is a routing cue.** Keywords like "private/secret/خاص" → local Ollama.
4. **Minimum ceremony.** One command, one result.
5. **Output goes somewhere findable.**

## Missing Recipes

| Gap | Description | Priority |
|---|---|---|
| `scheduler-status` | Quick `eco scheduler status` wrapper for menu bar | LOW |
