# eco-commander

> A unified CLI + SwiftBar control surface for a multi-tool AI ecosystem on macOS.

[![CI](https://github.com/abdulrahman-gaith-beep/eco-commander/actions/workflows/ci.yml/badge.svg)](./.github/workflows/ci.yml)
[![Tests: Bats](https://img.shields.io/badge/tests-bats-brightgreen)](./tests)
[![Shell: bash](https://img.shields.io/badge/shell-bash-89e051)](#requirements)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![Status: Beta](https://img.shields.io/badge/status-beta-f59e0b)](./CHANGELOG.md)
[![Docs: Wiki](https://img.shields.io/badge/docs-wiki-8a2be2)](https://github.com/abdulrahman-gaith-beep/eco-commander/wiki)

`eco-commander` is the operator console for an AI ecosystem that spans Claude Code, Cursor,
Antigravity, Gemini CLI, Ollama, and a fleet of MCP servers. It provides:

- a **CLI router** (`eco`) for ecosystem-wide operations,
- a **SwiftBar status panel** (`eco-commander.15s.sh`) that visualises live state,
- a **recipe library** (`src/recipes/*.sh`) for repeatable workflows (research, swarm, snapshot, …),
- a **snapshot system** for finalized ecosystem state under `~/.eco/snapshots/`,
- a **test suite** covering router, panel, recipe, and scheduler behavior.

## Why eco-commander?

Running several AI tools on one Mac means juggling usage windows, local model
state, background agents, and one-off shell workflows. `eco-commander` keeps
that operational layer visible and repeatable:

- `eco status` and the SwiftBar panel put Claude, Gemini, Codex, Ollama,
  runtime, and snapshot signals in one place.
- Recipes turn repeated actions such as ask, research, swarm, and snapshot into
  named commands instead of ad hoc shell history.
- Finalized snapshots preserve timestamped ecosystem state under
  `~/.eco/snapshots/` so changes can be reviewed instead of reconstructed from
  memory.

---

## Table of contents

1. [Why eco-commander?](#why-eco-commander)
2. [Quick start](#quick-start)
3. [See it work](#see-it-work)
4. [Documentation map](#documentation-map)
5. [Architecture](#architecture)
6. [Repository layout](#repository-layout)
7. [Installation](#installation)
8. [Usage](#usage)
9. [Recipes](#recipes)
10. [Job scheduler (experimental)](#job-scheduler-experimental)
11. [Snapshots](#snapshots)
12. [Testing](#testing)
13. [Contributing & roadmap](#contributing--roadmap)
14. [Navigation index](./INDEX.md)
15. [Documentation index](./docs/INDEX.md)
16. [Roadmap](./ROADMAP.md)
17. [Governance](./GOVERNANCE.md)
18. [Contributing](./CONTRIBUTING.md)
19. [Security policy](./SECURITY.md)
20. [License](#license)

---

## Quick start

```bash
git clone https://github.com/abdulrahman-gaith-beep/eco-commander.git
cd eco-commander
make install         # create real ~/.eco dirs; link individual src files
export PATH="$HOME/.eco/bin:$PATH"
eco status           # render the live status panel in the terminal
eco list             # list available recipes
```

> The repo is the source of truth. `~/.eco/` is the runtime: `make install`
> creates real `~/.eco/bin` and `~/.eco/recipes` directories, then writes
> per-file symlinks back to `src/bin/*` and `src/recipes/*.sh` so edits to a
> tracked file go live immediately. Add
> `export PATH="$HOME/.eco/bin:$PATH"` to your shell rc file, such as
> `~/.zshrc`, so new terminals can find `eco`.

---

## See it work

After `make install` and the PATH update above, these commands exercise the
public CLI surface without running model-backed recipes:

```bash
eco status
eco list
eco doctor
```

Expected shape:

- `eco status` prints the same one-screen status that SwiftBar renders,
  including quota, RAM, runtime, and snapshot signals when state is available.
- `eco list` prints recipe names plus their `# DESC:` and `# INPUTS:` metadata.
- `eco doctor` runs installation checks and reports anything that needs
  attention.

`ask`, `research`, and `swarm` prefer `gem-smart` when it is available, but
fall back to the plain `gemini` CLI. `snapshot` also needs Gemini CLI access
and ships a public example prompt library for a runnable capture path; see
[`docs/subsystems/snapshots.md`](./docs/subsystems/snapshots.md).

---


## Documentation map

eco-commander documentation is organized along the [Diátaxis](https://diataxis.fr/) framework:

* **[Tutorials](./docs/INDEX.md#tutorials)**: Guided learning (e.g., [First-run walkthrough](./docs/tutorials/first-run.md))
* **[How-to guides](./docs/INDEX.md#getting-started)**: Step-by-step tasks (e.g., [Installation](./docs/getting-started/installation.md), [Recipes](./docs/subsystems/recipes.md))
* **[Reference](./docs/INDEX.md#reference)**: Technical details (e.g., [CLI API](./docs/api/cli-reference.md), [Data model](./docs/reference/data-model.md))
* **[Explanation](./docs/INDEX.md#concepts)**: System concepts (e.g., [Architecture](./docs/architecture.md), [Snapshots](./docs/subsystems/snapshots.md))

For a complete list of all documentation files, see the [Documentation index](./docs/INDEX.md).

The project also has a navigable **[GitHub Wiki](https://github.com/abdulrahman-gaith-beep/eco-commander/wiki)** companion (Getting Started, CLI Reference, Scheduler, Usage Monitor, and more). The repository and its in-repo `docs/` tree remain the version-pinned source of truth.

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
                │   arabic-proof · dashboard                    │
                ├───────────────────────────────────────────────┤
                │  Runtime state at ~/.eco/                     │
                │  • snapshots/  • reasons/  • reports/         │
                ├───────────────────────────────────────────────┤
                │  External integrations                        │
                │  Claude Code · Gemini CLI · Cursor · Ollama   │
                │  Antigravity · configured MCP servers         │
                └───────────────────────────────────────────────┘
```

Full details: [`docs/diagrams/architecture.md`](./docs/diagrams/architecture.md).

---

## Repository layout

```
eco-commander/
├── README.md                     ← you are here
├── INDEX.md                      ← repo-wide navigation index
├── LICENSE                       ← MIT
├── CHANGELOG.md                  ← Keep a Changelog
├── CONTRIBUTING.md               ← how to contribute
├── CODE_OF_CONDUCT.md            ← Contributor Covenant 2.1
├── SECURITY.md                   ← vulnerability disclosure
├── SUPPORT.md                    ← getting help
├── AUTHORS.md                    ← contributors
├── GOVERNANCE.md                 ← decision-making process
├── ROADMAP.md                    ← public roadmap
├── TODO.md                       ← contributor-facing task list
├── CITATION.cff                  ← citation metadata
├── VERSION                       ← single-source version string
├── Makefile                      ← install / test / lint / release
├── pyproject.toml                ← Python project metadata & tool config
├── Brewfile                      ← Homebrew dependency manifest
├── commitlint.config.cjs         ← Conventional Commits rule config
├── requirements.txt / requirements-dev.txt
├── config/                       ← runtime config templates (`~/.eco`)
├── .editorconfig
├── .gitignore / .gitattributes
├── .shellcheckrc / .yamllint.yml / .markdownlint.json
├── .env.example                  ← documented environment variables
├── .pre-commit-config.yaml       ← pre-commit hook config
├── .devcontainer/                ← VS Code / GitHub Codespaces config
├── .github/
│   ├── workflows/                ← CI/CD workflows
│   │   ├── ci.yml                ← lint + typecheck + test (matrix)
│   │   ├── release.yml           ← tag-based GitHub release
│   │   ├── security.yml          ← secret scan + dep audit
│   │   ├── codeql.yml            ← CodeQL SAST
│   │   ├── hygiene.yml           ← pre-commit + actionlint
│   │   ├── commitlint.yml        ← Conventional Commits
│   │   ├── dependency-review.yml ← dependency review on PRs
│   │   ├── dependabot-automerge.yml
│   │   ├── labeler.yml
│   │   └── stale.yml
│   ├── ISSUE_TEMPLATE/           ← bug, feature, docs, release templates (.yml)
│   ├── DISCUSSION_TEMPLATE/      ← general, ideas
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── CODEOWNERS
│   ├── dependabot.yml
│   ├── labeler.yml
│   └── settings.yml              ← Probot repo settings
├── docs/
│   ├── INDEX.md / MANIFEST.json / READING_ORDER.md / FAQ.md
│   ├── architecture.md
│   ├── tutorials/                ← guided first-run walkthrough (Diátaxis: learning)
│   ├── concepts/                 ← mental model (Diátaxis: explanation)
│   ├── examples/                 ← task cookbook (Diátaxis: how-to)
│   ├── getting-started/          ← installation, usage, troubleshooting
│   ├── reference/                ← config, data model, env vars, glossary
│   ├── subsystems/               ← alerts, scheduler, poller, recipes, …
│   ├── operations/               ← runbook, security model
│   ├── api/                      ← CLI reference & generation script
│   ├── adr/                      ← Architecture Decision Records
│   ├── contributing/             ← dev hygiene, governance, testing
│   ├── diagrams/                 ← system architecture diagrams
│   ├── migration/                ← migration guides
│   ├── rfcs/                     ← Request for Comments
│   └── scripts/                  ← doc validation & search utilities
├── src/
│   ├── bin/
│   │   ├── eco                   ← CLI router (bash)
│   │   ├── eco-commander.15s.sh  ← SwiftBar plugin (also `--cli`)
│   │   ├── eco-alerts.sh         ← alert doctor & repo health
│   │   ├── install-commander.sh  ← SwiftBar registration helper
│   │   └── ai-clear.sh
│   ├── common/                   ← shared Python config (config.py)
│   ├── poller/                   ← usage monitor (Python, launchd 60s)
│   │   ├── main.py               ← aggregator entry point
│   │   ├── claude.py / gemini.py / codex.py
│   │   ├── notify.py / pace.py / value.py
│   │   └── claude_oauth.py / codex_oauth.py ← OAuth token refresh
│   ├── scheduler/                ← quota-aware job dispatcher (Python)
│   │   ├── cli.py / dispatcher.py / queue.py / routing.py
│   │   └── adapters/             ← base, claude, codex, gemini, ollama
│   ├── recipes/                  ← shell recipes (ask, research, swarm, …)
│   └── tools/                    ← utilities (dep_graph.py)
├── scripts/                      ← shell and Python helper scripts
│   ├── install.sh / uninstall.sh ← install per-file links into ~/.eco
│   ├── install-launchagents.sh / uninstall-launchagents.sh
│   ├── install-hooks.sh / install-log-rotation.sh / uninstall-log-rotation.sh
│   ├── lint.sh / doctor.sh / healthcheck.sh
│   ├── setup-venv.sh / bootstrap.sh
│   ├── release.sh / usage-snapshot.sh
│   ├── run-poller.sh / run-scheduler.sh / run-alerts.sh
│   ├── toggle-precise.sh / validate-commit-message.sh / verify-manifest.sh
│   ├── lib/                      ← shared shell functions
│   └── launchagents/             ← macOS LaunchAgent plists
├── tests/
│   ├── bats/                     ← Bats suites for core and recipe behavior
│   ├── python/                   ← Python unit tests
│   ├── e2e/                      ← end-to-end tests across multiple tiers
│   ├── fixtures/ / helpers/
│   └── run-all.sh
└── examples/                     ← runnable example configs
    ├── missions/                 ← scheduler seed-job examples
    └── snapshot-prompts/         ← public snapshot prompt library
```

---

## Installation

```bash
make install        # create real ~/.eco dirs; link individual src files
make uninstall      # remove symlinks (does not delete snapshots/data)
```

Manual installation, requirements, and SwiftBar wiring are documented in
[`docs/getting-started/installation.md`](./docs/getting-started/installation.md).

LaunchAgents are opt-in for safety: run `ECO_INSTALL_LAUNCHAGENTS=1 make install`
or `bash scripts/install-launchagents.sh` when you want background poller/autostart.

### Requirements

- macOS 13+
- Python 3.10-3.13 available as `python3` (the installer and scheduler use it)
- Bash: macOS default `/bin/bash` works for the core CLI; `brew install bash`
  is recommended for recipes that use newer Bash behavior.
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (optional — for the menu-bar widget)
- [Bats](https://bats-core.readthedocs.io/) (optional — for running tests)
- `jq`, `git`, `curl`, `make`

---

## Usage

```bash
eco status                      # full ecosystem status (CLI rendering of widget)
eco do <name> [args...]         # run a recipe
eco list                        # list available recipes
eco snapshot                    # capture a timestamped ecosystem snapshot
eco dashboard                   # open the current HTML dashboard
eco doctor                      # self-test installation
eco help                        # show help
```

See [`docs/getting-started/usage.md`](./docs/getting-started/usage.md) for
command syntax. `eco` returns `0` for successful commands. Syntactically valid
but missing recipes or commands return `1`; invalid recipe/command name syntax
returns `2`. Delegated recipes and subsystems keep their own status codes:
scheduler argument validation, queue load, and `add --file` YAML/job-shape
errors return `2`, while `eco scheduler run-once` returns `1` when the dispatch
summary reports errors or failed attempts.

---

## Recipes

| Recipe              | Purpose                                                    |
|---------------------|------------------------------------------------------------|
| `ask`               | One-shot Q&A through the configured model router           |
| `note`              | Append a timestamped note to the daily journal             |
| `research`          | Single-pass research via Gemini (large context), markdown output with citations |
| `swarm`             | Dispatch a parallel agent swarm                            |
| `snapshot`          | Capture ecosystem state into `~/.eco/snapshots/`           |
| `arabic-proof`      | Arabic proofreading + dialect-aware rewrite                |
| `dashboard`         | Open the current HTML dashboard in your browser            |
| `scheduler-seed`    | Import mission YAML files into the scheduler queue         |
| `account-swap`      | Rotate CLI auth between registered local accounts          |
| `hygiene`           | Check local RAM, swap, MCP, and runtime health             |
| `n8n-start`         | Start local n8n through Docker Compose or `npx`            |
| `dashboard-refresh` | Refresh dashboard metrics from runtime state               |

Catalog: [`docs/subsystems/recipes.md`](./docs/subsystems/recipes.md).

> The `ask`, `research`, and `swarm` recipes require the Gemini CLI
> authenticated. They prefer `gem-smart` on your PATH, or the binary set in
> `ECO_GEM_SMART_BIN`, and fall back to plain `gemini` when `gem-smart` is
> absent. `snapshot` also needs Gemini CLI access and a prompt library; the
> public install includes an example library, and `ECO_AUDIT_ROOT` can point
> at a private one.

---

## Job scheduler (experimental)

Quota-aware cross-project AI-job dispatcher. Reads meter state from
`~/.eco/state/notify.json` (written by the poller) and a federated job queue at
`~/.eco/queue/jobs.yaml`. Each job carries a `model_preference` ladder; the
scheduler walks the ladder and fires via the first adapter whose meter is open.

```bash
eco scheduler status                       # queue depth + meter availability
eco scheduler add --file examples/missions/seed-jobs.example.yaml
eco scheduler run-once                     # one dispatch tick (debug)
eco scheduler drain --max-ticks 20         # run until idle or fully gated
eco scheduler tail                         # most recent attempt log
```

The scheduler LaunchAgent is explicit opt-in. Persist + auto-load it with:

```bash
ECO_SCHEDULER_AUTO_LOAD=1 bash scripts/install-launchagents.sh
```

Supported providers: `claude`, `codex`, `gemini`, and `ollama`. Add more in
`src/scheduler/adapters/`.

See [`src/scheduler/`](./src/scheduler/) and the seed file
[`examples/missions/seed-jobs.example.yaml`](./examples/missions/seed-jobs.example.yaml).

---

## Snapshots

Each invocation of `eco snapshot` creates a timestamped tree under
`~/.eco/snapshots/<YYYY-MM-DDTHH-MMZ>/` using the timestamp format from
`date +%Y-%m-%dT%H-%MZ`, then atomically updates `~/.eco/current` to point at
the new snapshot. Snapshots are immutable once finalized; the current snapshot
can still receive poller writes while it is the active runtime view. See
[`docs/subsystems/snapshots.md`](./docs/subsystems/snapshots.md).

---

## Testing

```bash
make test           # Bats + Python + E2E test suite
make test-fast      # Bats + Python only (skips E2E)
make lint           # shellcheck + ruff on src/ and scripts/
```

Test architecture and conventions: [`docs/contributing/testing.md`](./docs/contributing/testing.md).

---

## Contributing & roadmap

Contributions are welcome when they stay focused, tested, and tied to a real
operator workflow. Start with [`CONTRIBUTING.md`](./CONTRIBUTING.md), scan
[`ROADMAP.md`](./ROADMAP.md), and check
[good-first-issues](https://github.com/abdulrahman-gaith-beep/eco-commander/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
when labelled starter work is available.

If this is useful, a star helps others find it.

---

## License

MIT — see [`LICENSE`](./LICENSE).
