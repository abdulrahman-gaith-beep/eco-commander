# Eco Recipes
**One-click objectives. Human triggers, AI executes, you review.**

## What these are
Pre-wired task pipelines so you do not have to remember which tool does what. Each recipe:
- Has ONE purpose stated in plain language
- Picks the right model/tool/profile automatically
- Accepts the minimum input to proceed
- Writes output to a known location
- Respects privacy, language, cost, and RAM constraints

## How to call

```bash
eco                 # list all recipes
eco do <name> [args]   # run one
eco status          # current ecosystem state
```

Or via the menu-bar commander (SwiftBar): click the menu icon → "Do Task" submenu.

## Current recipes

| Name | What | Tool | Inputs |
|---|---|---|---|
| `research` | Research a topic with Gemini | gem-smart or Gemini CLI | `<topic>` |
| `ask` | Ask a question fast (routes to Gemini or Ollama by privacy cue) | mixed | `<question>` |
| `swarm` | Dispatch N parallel Gemini agents on a task + synthesize | gem-smart or Gemini CLI | `<task> [N=5]` |
| `note` | Capture a note to long-term memory in right space by CWD | filesystem + memory router | `<content>` or `$EDITOR` |
| `snapshot` | Re-run the prompt-layer ecosystem snapshot | gem-smart or Gemini CLI | none |
| `arabic-proof` | Arabic proofreading privately on local Ollama (`qwen3.6:latest` default) | Ollama | `<file>` or stdin |
| `dashboard` | Open the current Eco dashboard | browser | none |
| `account-swap` | Rotate Claude/Gemini/Codex CLI auth between registered accounts (no re-OAuth) | macOS Keychain + filesystem | `list` \| `<tool> <slug>` \| `<tool> --register <slug>` |

## Adding a new recipe

1. Create `~/.eco/recipes/<name>.sh`
2. Required headers (scanned by `eco list`):
   - `# DESC: one-line what this does`
   - `# INPUTS: <args spec>` (optional)
   - `# OUTPUT: where results go`
   - `# USES: which model/tool`
   - `# HUMAN: what human does vs what AI does`
3. `chmod +x ~/.eco/recipes/<name>.sh`
4. It appears automatically in `eco list` and the menu bar's "Do Task" submenu.

## Design principles

- **Agents should not shop for tools.** The recipe pre-selects.
- **Cost-aware by default.** Prefer lower-cost Gemini routes for broad work.
- **Privacy is a routing cue.** Keywords like "private/secret/internal/خاص" → local Ollama, always.
- **Minimum ceremony.** One command, one result. Don't explain — just do.
- **Output goes somewhere findable.** `~/Documents/research/*` for research, `~/.ai-memory/spaces/*` for memory, `~/.eco/snapshots/*` for snapshots.
