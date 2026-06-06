# File index

> Last updated: 2026-06-06.

## Top level
| Path | Purpose | Audience |
|---|---|---|
| `README.md` | Project overview, quick start, layout | Everyone |
| `INDEX.md` | This file — whole-repo file map | Everyone |
| `LICENSE` | MIT | Everyone |
| `VERSION` | Single-source semantic version string | Everyone |
| `CHANGELOG.md` | Keep-a-Changelog history | Everyone |
| `ROADMAP.md` | Planned milestones and direction | Everyone |
| `TODO.md` | Contributor-facing actionable task list (good-first-issues tagged) | Everyone |
| `CONTRIBUTING.md` | Contributor workflow and standards | Everyone |
| `GOVERNANCE.md` | Project governance and decision model | Operators |
| `CODE_OF_CONDUCT.md` | Contributor Covenant 2.1 | Everyone |
| `SECURITY.md` | Vulnerability disclosure | Operators |
| `SUPPORT.md` | Where to get help | Everyone |
| `AUTHORS.md` | Contributor list | Everyone |
| `Makefile` | install / test / lint / release | Contributors |
| `pyproject.toml` | Python package + tooling (ruff, mypy, pytest) config | Contributors |
| `.gitignore`, `.gitattributes`, `.editorconfig`, `.shellcheckrc` | Tooling config | Contributors |
| `.pre-commit-config.yaml`, `.yamllint.yml`, `.markdownlint.json`, `.gitleaks.toml`, `commitlint.config.cjs` | Local quality gates | Contributors |
| `.devcontainer/` | Reproducible dev container definition | Contributors |
| `.env.example` | Template of every environment variable the system reads | Operators |
| `config/` | Runtime config templates for `$ECO_HOME/config.json` and `$ECO_HOME/config/comments.json` | Operators |
| `Brewfile`, `requirements.txt`, `requirements-dev.txt` | Local and CI dependency manifests | Contributors |

## `src/bin/`
| Path | Purpose | Audience |
|---|---|---|
| `src/bin/eco` | CLI router — dispatches all subcommands | Developers |
| `src/bin/eco-commander.15s.sh` | SwiftBar plugin + `--cli` panel (refreshes every 15s) | Developers |
| `src/bin/eco-alerts.sh` | Alert doctor, repo health, debug-ollama, delegate-fix | Developers |
| `src/bin/ai-clear.sh` | Deprecated no-op retained for legacy callers | Developers |
| `src/bin/install-commander.sh` | Install the SwiftBar commander widget | Developers |
| `src/bin/ALERT_IDEAS.md` | Backlog of widget alert ideas | Developers |
| `src/bin/MANIFEST.md` | Bin directory file registry | Developers |

## `src/recipes/`
| Path | Purpose | Audience |
|---|---|---|
| `src/recipes/README.md` | Recipe design principles and catalog | Developers |
| `src/recipes/ask.sh` | One-shot Q&A | Developers |
| `src/recipes/note.sh` | Append journal note | Developers |
| `src/recipes/research.sh` | Multi-source research | Developers |
| `src/recipes/swarm.sh` | Dispatch parallel agent swarm | Developers |
| `src/recipes/snapshot.sh` | Capture ecosystem snapshot | Developers |
| `src/recipes/arabic-proof.sh` | Arabic proofreading | Developers |
| `src/recipes/dashboard.sh` | Render dashboard from snapshot | Developers |
| `src/recipes/account-swap.sh` | Rotate CLI auth between registered accounts | Developers |
| `src/recipes/hygiene.sh` | Mac hygiene watcher (RAM/swap/MCP/stuck processes) | Developers |
| `src/recipes/n8n-start.sh` | Start n8n via Docker Compose or npx | Developers |
| `src/recipes/dashboard-refresh.sh` | Inject live metrics into dashboard template | Developers |
| `src/recipes/scheduler-seed.sh` | Import mission YAML files into the scheduler queue | Developers |

## `src/poller/`
| Path | Purpose | Audience |
|---|---|---|
| `src/poller/main.py` | Poller entry point — merges per-tool data into `usage.json` | Developers |
| `src/poller/claude.py` | Claude Code JSONL token parser | Developers |
| `src/poller/gemini.py` | Gemini `retrieveUserQuota` API replay | Developers |
| `src/poller/codex.py` | Codex CLI JSONL token parser | Developers |
| `src/poller/caps.py` | Calibrated token caps for Claude/Codex | Developers |
| `src/poller/notify.py` | macOS notifications + meter state for scheduler | Developers |
| `src/poller/pace.py` | Rate/pace tracking | Developers |
| `src/poller/value.py` | Value computation module | Developers |
| `src/poller/discovery.py` | Tool discovery and configuration loading | Developers |
| `src/poller/alternatives.py` | Alternative model suggestions | Developers |
| `src/poller/comments.py` | Usage commentary generation | Developers |
| `src/poller/claude_oauth.py` | Claude OAuth token refresh | Developers |
| `src/poller/codex_oauth.py` | Codex OAuth token refresh | Developers |
| `src/poller/accounts.py` | Multi-account registry + USD-equivalent value rollup | Developers |
| `src/poller/time_utils.py` | ISO parsing, reset-countdown formatting, dot-path resolution | Developers |
| `src/poller/MANIFEST.md` | Poller module dependency DAG + public API surface | Developers |

## `src/scheduler/`
| Path | Purpose | Audience |
|---|---|---|
| `src/scheduler/__init__.py` | Package init, version | Developers |
| `src/scheduler/cli.py` | CLI surface: status, add, run-once, drain, tail | Developers |
| `src/scheduler/dispatcher.py` | Single-tick dispatch loop with crash recovery | Developers |
| `src/scheduler/queue.py` | YAML-backed job queue with flock + atomic writes | Developers |
| `src/scheduler/routing.py` | Meter availability + model-preference ladder walk | Developers |
| `src/scheduler/adapters/__init__.py` | Adapter registry | Developers |
| `src/scheduler/adapters/base.py` | Adapter protocol + AdapterResult dataclass | Developers |
| `src/scheduler/adapters/claude.py` | Claude CLI adapter | Developers |
| `src/scheduler/adapters/codex.py` | Codex CLI adapter | Developers |
| `src/scheduler/adapters/gemini.py` | Gemini CLI adapter | Developers |
| `src/scheduler/adapters/ollama.py` | Ollama adapter | Developers |

## `src/common/`
| Path | Purpose | Audience |
|---|---|---|
| `src/common/config.py` | Shared configuration loader for Python subsystems | Developers |

## `src/tools/`
| Path | Purpose | Audience |
|---|---|---|
| `src/tools/dep_graph.py` | Generate module dependency graph (feeds `docs/diagrams/module-deps.md`) | Developers |

## `src/` navigation aids
| Path | Purpose | Audience |
|---|---|---|
| `src/AI_NAV.md` | AI navigation index for the source tree | Developers |
| `src/AGENT_AUDIT_TASKLIST.md` | Categorized source-audit tasks for AI agents | Developers |

## `docs/`
| Path | Purpose | Audience |
|---|---|---|
| `docs/INDEX.md` | Documentation map with multi-dimensional navigation | Everyone |
| `docs/MANIFEST.json` | Machine-readable doc metadata for AI agents | Everyone |
| `docs/READING_ORDER.md` | Task-based recommended reading paths | Everyone |
| `docs/architecture.md` | System architecture (5 subsystems) | Developers |
| `docs/.ai-context.yaml` | Agent context protocol — scoped summaries | Everyone |

### `docs/getting-started/`
| Path | Purpose | Audience |
|---|---|---|
| `docs/getting-started/installation.md` | Install + SwiftBar wiring | Operators |
| `docs/getting-started/usage.md` | Every command, flag, exit code | Operators |
| `docs/getting-started/troubleshooting.md` | Known issues and fixes | Operators |

### `docs/reference/`
| Path | Purpose | Audience |
|---|---|---|
| `docs/reference/data-model.md` | JSON schemas and file formats | Operators / Developers |
| `docs/reference/configuration.md` | Configuration files reference | Operators / Developers |
| `docs/reference/environment-variables.md` | Environment variables reference | Operators / Developers |
| `docs/reference/glossary.md` | Term definitions | Operators / Developers |

### `docs/subsystems/`
| Path | Purpose | Audience |
|---|---|---|
| `docs/subsystems/scheduler.md` | Job scheduler reference | Developers |
| `docs/subsystems/usage-monitor.md` | Usage monitor user guide | Developers |
| `docs/subsystems/usage-monitor-integration.md` | Usage monitor integration plan (historical) | Developers |
| `docs/subsystems/alerts.md` | Alert system reference | Developers |
| `docs/subsystems/widget-health.md` | Widget health playbook | Developers |
| `docs/subsystems/recipes.md` | Recipe catalog and contracts | Developers |
| `docs/subsystems/snapshots.md` | Snapshot format and lifecycle | Developers |
| `docs/subsystems/launchd-best-practices.md` | launchd energy/reliability practices | Developers |

### `docs/operations/`
| Path | Purpose | Audience |
|---|---|---|
| `docs/operations/runbook.md` | Operational runbook | Operators |
| `docs/operations/security-model.md` | Expanded threat model | Operators |

### `docs/contributing/`
| Path | Purpose | Audience |
|---|---|---|
| `docs/contributing/CONTRIBUTING-DOCS.md` | Contributing to docs | Contributors |
| `docs/contributing/developer-hygiene.md` | Local Git hygiene and quality gates | Contributors |
| `docs/contributing/repository-governance.md` | Branch protection, labels, and release gates | Contributors |
| `docs/contributing/testing.md` | Bats + Python test conventions | Contributors |

### `docs/adr/`
| Path | Purpose | Audience |
|---|---|---|
| `docs/adr/0001-record-architecture-decisions.md` | ADR meta | Developers |
| `docs/adr/0002-bash-implementation.md` | Why bash, not Python | Developers |
| `docs/adr/0003-snapshot-immutability.md` | Snapshot guarantees | Developers |
| `docs/adr/0004-usage-monitor-python-carveout.md` | Python carve-out for poller | Developers |
| `docs/adr/0005-job-scheduler.md` | Job scheduler architecture | Developers |

### `docs/diagrams/`
| Path | Purpose | Audience |
|---|---|---|
| `docs/diagrams/` | 14 Mermaid diagrams (architecture, data-flow, scheduler-flow, alert-pipeline, poller-pipeline, module-deps, meter-state-machine, account-swap-flow, widget-rendering, filesystem-layout, install-lifecycle, ci-pipeline, snapshot-lifecycle, test-architecture) | Developers |

### `docs/api/`
| Path | Purpose | Audience |
|---|---|---|
| `docs/api/cli-reference.md` | Generated reference for every `eco` subcommand | Developers |
| `docs/api/generate-cli-reference.sh` | Regenerates the CLI reference from source | Developers |

### `docs/scripts/`
| Path | Purpose | Audience |
|---|---|---|
| `docs/scripts/validate-links.sh` | Internal link + orphan + INDEX-coverage checker | Contributors |
| `docs/scripts/doc-stats.sh`, `extract-glossary.sh`, `extract-section.sh`, `search-docs.sh` | Doc maintenance utilities | Contributors |

### `docs/migration/`, `docs/rfcs/`
| Path | Purpose | Audience |
|---|---|---|
| `docs/migration/README.md` | Version migration notes | Everyone |
| `docs/rfcs/README.md` | Request-for-comments design proposals | Everyone |
| `docs/FAQ.md` | Frequently asked questions | Operators |

## `scripts/`
> Machine-readable index: [`scripts/MANIFEST.yaml`](./scripts/MANIFEST.yaml) · audit tasks: [`scripts/AGENT_AUDIT_TASKLIST.md`](./scripts/AGENT_AUDIT_TASKLIST.md)

| Path | Purpose | Audience |
|---|---|---|
| `scripts/bootstrap.sh` | One-command dev environment setup (Brew, venv, hooks, install, smoke) | Contributors |
| `scripts/setup-venv.sh` | Create Python venv and install dev dependencies (3.10–3.13) | Contributors |
| `scripts/install.sh` | Deploy src → ~/.eco via symlinks | Contributors |
| `scripts/uninstall.sh` | Remove deployed symlinks | Contributors |
| `scripts/install-launchagents.sh` | Render + install LaunchAgent plists | Contributors |
| `scripts/uninstall-launchagents.sh` | Unload and remove LaunchAgents | Contributors |
| `scripts/install-hooks.sh` | Install pre-commit + commit-msg Git hooks | Contributors |
| `scripts/install-log-rotation.sh` | Install newsyslog rotation config (requires sudo) | Contributors |
| `scripts/uninstall-log-rotation.sh` | Remove the eco-commander newsyslog drop-in | Contributors |
| `scripts/healthcheck.sh` | End-to-end system health verification | Contributors |
| `scripts/doctor.sh` | Diagnose and repair installation (symlinks, config, logs) | Contributors |
| `scripts/lint.sh` | Run shellcheck across src/ and scripts/ | Contributors |
| `scripts/release.sh` | Tag and push a release | Contributors |
| `scripts/run-poller.sh` | Manual poller invocation wrapper | Contributors |
| `scripts/run-scheduler.sh` | Manual scheduler dispatcher wrapper | Contributors |
| `scripts/run-alerts.sh` | Manual eco-alerts wrapper | Contributors |
| `scripts/toggle-precise.sh` | Toggle precise (server-truth) polling mode | Contributors |
| `scripts/usage-snapshot.sh` | Usage data snapshot utility | Contributors |
| `scripts/validate-commit-message.sh` | Validate commit subject against Conventional Commits | Contributors |
| `scripts/verify-manifest.sh` | Verify MANIFEST.yaml against the filesystem | Contributors |
| `scripts/lib/` | Shared script libraries (common.sh, snapshot-helpers.sh) | Contributors |
| `scripts/log-rotate.conf` | newsyslog configuration template | Contributors |
| `scripts/launchagents/` | LaunchAgent plist templates | Contributors |

> Scheduler mission examples live under [`examples/missions/`](./examples/missions/). Public snapshot prompts live under [`examples/snapshot-prompts/`](./examples/snapshot-prompts/).

## `tests/`
| Path | Purpose | Audience |
|---|---|---|
| `tests/run-all.sh` | Master runner (BATS + Python + E2E tests) | Contributors |
| `tests/README.md` | Test architecture documentation | Contributors |
| `tests/INDEX.md` | Machine-readable file inventory with test counts | Contributors |
| `tests/COVERAGE_MAP.md` | Source module → test file traceability matrix | Contributors |
| `tests/AI_NAVIGATION.md` | AI agent navigation guide and decision trees | Contributors |
| `tests/AGENT_AUDIT_TASKLIST.md` | Categorized improvement tasks for AI agents | Contributors |
| `tests/bats/` | BATS integration tests (files + recipes/) | Contributors |
| `tests/e2e/` | End-to-end widget tests | Contributors |
| `tests/python/` | Python unit tests (files + conftest.py) | Contributors |
| `tests/python/conftest.py` | Shared path setup + test data factories | Contributors |
| `tests/python/pytest.ini` | Pytest discovery and marker configuration | Contributors |
| `tests/fixtures/` | Static test fixtures (state.json variants) | Contributors |
| `tests/helpers/` | Shared bash helpers + 11 stub executables | Contributors |

## `.github/`
| Path | Purpose | Audience |
|---|---|---|
| `.github/workflows/ci.yml` | shellcheck + bats on push | Contributors |
| `.github/workflows/hygiene.yml` | pre-commit, actionlint, and whitespace checks | Contributors |
| `.github/workflows/security.yml` | secret scan and Python dependency audit | Contributors |
| `.github/workflows/codeql.yml` | CodeQL Python analysis | Contributors |
| `.github/workflows/labeler.yml` | PR auto-labeling | Contributors |
| `.github/workflows/commitlint.yml` | Conventional Commit validation | Contributors |
| `.github/workflows/release.yml` | GitHub Release publishing | Contributors |
| `.github/workflows/stale.yml` | Stale issue/PR housekeeping | Contributors |
| `.github/workflows/dependabot-automerge.yml` | Auto-merge passing Dependabot PRs | Contributors |
| `.github/workflows/dependency-review.yml` | Dependency diff review on PRs | Contributors |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Bug report form | Contributors |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | Feature request form | Contributors |
| `.github/ISSUE_TEMPLATE/docs_issue.yml` | Documentation issue form | Contributors |
| `.github/ISSUE_TEMPLATE/release_checklist.yml` | Release checklist form | Contributors |
| `.github/ISSUE_TEMPLATE/config.yml` | Issue chooser policy and contact links | Contributors |
| `.github/DISCUSSION_TEMPLATE/` | Discussion forms (general, ideas) | Contributors |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR template | Contributors |
| `.github/CODEOWNERS` | Default reviewers | Contributors |
| `.github/dependabot.yml` | Update policy | Contributors |
| `.github/labeler.yml` | Path-based PR label rules | Contributors |
| `.github/settings.yml` | Declarative repository policy | Contributors |
| `.github/FUNDING.yml` | Sponsorship links | Contributors |

## `examples/`
| Path | Purpose | Audience |
|---|---|---|
| `examples/missions/` | Generic scheduler mission examples | Operators |
| `examples/snapshot-prompts/` | Public prompt library for `eco snapshot` | Operators |
