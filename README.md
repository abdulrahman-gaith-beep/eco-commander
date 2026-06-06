# eco-commander

**Stop juggling AI CLI tools.** eco-commander puts Claude Code, Gemini CLI, Codex,
Ollama, and your MCP servers behind one command — with live quota monitoring, a
SwiftBar menu-bar widget, and repeatable recipes for research, swarm, and snapshot
workflows.

`v0.2.0 · beta · macOS`

[![CI](https://github.com/abdulrahman-gaith-beep/eco-commander/actions/workflows/ci.yml/badge.svg)](https://github.com/abdulrahman-gaith-beep/eco-commander/actions/workflows/ci.yml)
[![Tests: Bats](https://img.shields.io/badge/tests-bats-brightgreen)](./tests)
[![Shell: bash](https://img.shields.io/badge/shell-bash-89e051)](#requirements)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![Status: Beta](https://img.shields.io/badge/status-beta-f59e0b)](./CHANGELOG.md)
[![Docs: Wiki](https://img.shields.io/badge/docs-wiki-8a2be2)](https://github.com/abdulrahman-gaith-beep/eco-commander/wiki)

[Documentation](./docs/INDEX.md) · [Wiki](https://github.com/abdulrahman-gaith-beep/eco-commander/wiki) · [Changelog](./CHANGELOG.md) · [Discussions](https://github.com/abdulrahman-gaith-beep/eco-commander/discussions)

<p align="center">
  <img src="docs/assets/demo.gif" alt="eco-commander demo — eco status, eco list, eco doctor" width="720">
</p>

---

## What you get

- **CLI router** (`eco`) — one command to reach every tool, recipe, and subsystem
- **Live status panel** — SwiftBar menu-bar widget showing quota, RAM, and runtime health
- **Recipe library** — named, repeatable workflows: ask, research, swarm, snapshot, and more
- **Snapshot system** — immutable, timestamped ecosystem state under `~/.eco/snapshots/`

---

## Quick start

```bash
git clone https://github.com/abdulrahman-gaith-beep/eco-commander.git
cd eco-commander
make install                          # symlinks src/ into ~/.eco/
export PATH="$HOME/.eco/bin:$PATH"    # add to ~/.zshrc for persistence
eco status                            # see your ecosystem at a glance
```

> `make install` creates `~/.eco/bin` and `~/.eco/recipes`, then writes per-file
> symlinks back to `src/` so edits go live immediately.

---

## Table of contents

1. [Usage](#usage)
2. [Recipes](#recipes)
3. [Architecture](#architecture)
4. [Job scheduler (experimental)](#job-scheduler-experimental)
5. [Snapshots](#snapshots)
6. [Installation](#installation)
7. [Testing](#testing)
8. [Contributing & roadmap](#contributing--roadmap)
9. [License](#license)

---

## Usage

```bash
eco status                        # one-screen ecosystem state (CLI + SwiftBar)
eco list                          # list available recipes with descriptions
eco do <name> [args...]           # run a recipe by name
eco <name> [args...]              # shortcut — same as `eco do <name>`
eco snapshot                      # capture a timestamped ecosystem snapshot
eco dashboard                     # open the current HTML dashboard
eco map                           # open the current map.md
eco audit                         # open the configured audit directory
eco scheduler <sub>               # scheduler: status, add, run-once, tail, drain, seed, cancel
eco hygiene <sub>                 # hygiene watcher: watch, snapshot, stop, status, tail
eco account-swap <sub>            # rotate auth across Claude/Gemini/Codex accounts
eco doctor                        # self-test the installation
eco help                          # show help
```

Full command reference: [`docs/api/cli-reference.md`](./docs/api/cli-reference.md).
Exit codes and edge cases: [`docs/getting-started/usage.md`](./docs/getting-started/usage.md).

---

## Recipes

| Recipe              | Purpose                                                    |
|---------------------|------------------------------------------------------------|
| `ask`               | One-shot Q&A through the configured model router           |
| `note`              | Append a timestamped note to the daily journal             |
| `research`          | Single-pass research via Gemini (large context) with citations |
| `swarm`             | Dispatch a parallel agent swarm                            |
| `snapshot`          | Capture ecosystem state into `~/.eco/snapshots/`           |
| `arabic-proof`      | Arabic proofreading + dialect-aware rewrite                |
| `dashboard`         | Open the current HTML dashboard                            |
| `dashboard-refresh` | Refresh dashboard metrics from runtime state               |
| `scheduler-seed`    | Import mission YAML files into the scheduler queue         |
| `account-swap`      | Rotate CLI auth between registered local accounts          |
| `hygiene`           | Check local RAM, swap, MCP, and runtime health             |
| `n8n-start`         | Start local n8n through Docker Compose or `npx`            |

> `ask`, `research`, and `swarm` prefer `gem-smart` (or `ECO_GEM_SMART_BIN`)
> and fall back to plain `gemini`. `snapshot` needs Gemini CLI access and a
> prompt library — the install includes a public example; `ECO_AUDIT_ROOT` can
> point at a private one.

Full recipe catalog: [`docs/subsystems/recipes.md`](./docs/subsystems/recipes.md).

---

## Architecture

```
                ┌───────────────────────────────────────────────┐
                │                  eco-commander                │
                ├──────────────────────┬────────────────────────┤
   user ───►    │  CLI router (`eco`)  │  SwiftBar status panel │
                ├──────────────────────┴────────────────────────┤
                │                Recipe library                 │
                │   ask · note · research · swarm · snapshot    │
                │   arabic-proof · dashboard · dashboard-refresh│
                │   scheduler-seed · account-swap · hygiene     │
                │   n8n-start                                   │
                ├───────────────────────────────────────────────┤
                │  Runtime state at ~/.eco/                     │
                │  • snapshots/  • state/  • queue/  • logs/    │
                ├───────────────────────────────────────────────┤
                │  External integrations                        │
                │  Claude Code · Gemini CLI · Codex · Ollama    │
                │  Antigravity · configured MCP servers         │
                └───────────────────────────────────────────────┘
```

Full architecture docs: [`docs/architecture.md`](./docs/architecture.md).
14 Mermaid diagrams: [`docs/diagrams/`](./docs/diagrams/).
Repository file map: [`INDEX.md`](./INDEX.md).

---

## Job scheduler (experimental)

Quota-aware cross-project AI-job dispatcher. Reads meter state from the poller
and a federated job queue at `~/.eco/queue/jobs.yaml`. Each job carries a
`model_preference` ladder; the scheduler walks the ladder and fires via the
first adapter whose meter is open.

```bash
eco scheduler status                       # queue depth + meter availability
eco scheduler add --file examples/missions/seed-jobs.example.yaml
eco scheduler run-once                     # one dispatch tick (debug)
eco scheduler drain --max-ticks 20         # run until idle or fully gated
eco scheduler tail                         # most recent attempt log
```

The scheduler LaunchAgent is explicit opt-in:

```bash
ECO_SCHEDULER_AUTO_LOAD=1 bash scripts/install-launchagents.sh
```

Supported providers: `claude`, `codex`, `gemini`, and `ollama`. Add more in
`src/scheduler/adapters/`.

See [`src/scheduler/`](./src/scheduler/) and the seed file
[`examples/missions/seed-jobs.example.yaml`](./examples/missions/seed-jobs.example.yaml).

---

## Snapshots

Each invocation of `eco snapshot` creates a timestamped, immutable tree under
`~/.eco/snapshots/<timestamp>/`, then atomically updates `~/.eco/current` to
point at the new snapshot. Details:
[`docs/subsystems/snapshots.md`](./docs/subsystems/snapshots.md).

---

## Installation

```bash
make install        # create ~/.eco dirs; symlink src files
make uninstall      # remove symlinks (does not delete snapshots/data)
```

LaunchAgents are opt-in: `ECO_INSTALL_LAUNCHAGENTS=1 make install` or
`bash scripts/install-launchagents.sh`.

Full installation guide: [`docs/getting-started/installation.md`](./docs/getting-started/installation.md).

### Requirements

- **macOS** 13+
- **Python** 3.10–3.13 as `python3` (poller and scheduler)
- **Bash** — the core `eco` CLI runs on macOS default `/bin/bash` (3.2);
  recipes that use newer syntax need Bash 5+ (`brew install bash`)
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (optional — menu-bar widget)
- [Bats](https://bats-core.readthedocs.io/) (optional — tests)
- `jq`, `git`, `curl`, `make` (Xcode Command Line Tools provides git, curl, make)

---

## Testing

```bash
make test           # Bats + Python + E2E test suite
make test-fast      # Bats + Python only (skips E2E)
make lint           # shellcheck + ruff on src/ and scripts/
```

Test conventions: [`docs/contributing/testing.md`](./docs/contributing/testing.md).

---

## Contributing & roadmap

Contributions are welcome when they stay focused, tested, and tied to a real
operator workflow. Start with [`CONTRIBUTING.md`](./CONTRIBUTING.md), scan
[`ROADMAP.md`](./ROADMAP.md), and check
[good-first-issues](https://github.com/abdulrahman-gaith-beep/eco-commander/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
for labelled starter work.

If this is useful, a ⭐ helps others find it.

---

## License

MIT — see [`LICENSE`](./LICENSE).

---

<sub>
[Security](./SECURITY.md) · [Governance](./GOVERNANCE.md) · [Support](./SUPPORT.md) · [Authors](./AUTHORS.md) · [Citation](./CITATION.cff) · [Code of Conduct](./CODE_OF_CONDUCT.md)
</sub>
