# File index

> Last updated: 2026-06-06.

## Top level
| Path | Purpose |
|---|---|
| `README.md` | Project overview, quick start, layout |
| `INDEX.md` | This file — whole-repo file map |
| `LICENSE` | MIT |
| `VERSION` | Single-source semantic version string |
| `CHANGELOG.md` | Keep-a-Changelog history |
| `ROADMAP.md` | Planned milestones and direction |
| `TODO.md` | Contributor-facing actionable task list (good-first-issues tagged) |
| `CONTRIBUTING.md` | Contributor workflow and standards |
| `GOVERNANCE.md` | Project governance and decision model |
| `CODE_OF_CONDUCT.md` | Contributor Covenant 2.1 |
| `SECURITY.md` | Vulnerability disclosure |
| `SUPPORT.md` | Where to get help |
| `AUTHORS.md` | Contributor list |
| `Makefile` | install / test / lint / release |
| `pyproject.toml` | Python package + tooling (ruff, mypy, pytest) config |
| `.gitignore`, `.gitattributes`, `.editorconfig`, `.shellcheckrc` | Tooling config |
| `.pre-commit-config.yaml`, `.yamllint.yml`, `.markdownlint.json`, `.gitleaks.toml`, `commitlint.config.cjs` | Local quality gates |
| `.devcontainer/` | Reproducible dev container definition |
| `.env.example` | Template of every environment variable the system reads |
| `config/` | Runtime config templates for `$ECO_HOME/config.json` and `$ECO_HOME/config/comments.json` |
| `Brewfile`, `requirements.txt`, `requirements-dev.txt` | Local and CI dependency manifests |

## `src/bin/`
| Path | Purpose |
|---|---|
| `src/bin/eco` | CLI router — dispatches all subcommands |
| `src/bin/eco-commander.15s.sh` | SwiftBar plugin + `--cli` panel (refreshes every 15s) |
| `src/bin/eco-alerts.sh` | Alert doctor, repo health, debug-ollama, delegate-fix |
| `src/bin/ai-clear.sh` | Deprecated no-op retained for legacy callers |
| `src/bin/install-commander.sh` | Install the SwiftBar commander widget |
| `src/bin/ALERT_IDEAS.md` | Backlog of widget alert ideas |
| `src/bin/MANIFEST.md` | Bin directory file registry |

## `src/recipes/`
| Path | Purpose |
|---|---|
| `src/recipes/README.md` | Recipe design principles and catalog |
| `src/recipes/ask.sh` | One-shot Q&A |
| `src/recipes/note.sh` | Append journal note |
| `src/recipes/research.sh` | Multi-source research |
| `src/recipes/swarm.sh` | Dispatch parallel agent swarm |
| `src/recipes/snapshot.sh` | Capture ecosystem snapshot |
| `src/recipes/arabic-proof.sh` | Arabic proofreading |
| `src/recipes/dashboard.sh` | Render dashboard from snapshot |
| `src/recipes/account-swap.sh` | Rotate CLI auth between registered accounts |
| `src/recipes/hygiene.sh` | Mac hygiene watcher (RAM/swap/MCP/stuck processes) |
| `src/recipes/n8n-start.sh` | Start n8n via Docker Compose or npx |
| `src/recipes/dashboard-refresh.sh` | Inject live metrics into dashboard template |
| `src/recipes/scheduler-seed.sh` | Import mission YAML files into the scheduler queue |

## `src/poller/`
| Path | Purpose |
|---|---|
| `src/poller/main.py` | Poller entry point — merges per-tool data into `usage.json` |
| `src/poller/claude.py` | Claude Code JSONL token parser |
| `src/poller/gemini.py` | Gemini `retrieveUserQuota` API replay |
| `src/poller/codex.py` | Codex CLI JSONL token parser |
| `src/poller/caps.py` | Calibrated token caps for Claude/Codex |
| `src/poller/notify.py` | macOS notifications + meter state for scheduler |
| `src/poller/pace.py` | Rate/pace tracking |
| `src/poller/value.py` | Value computation module |
| `src/poller/discovery.py` | Tool discovery and configuration loading |
| `src/poller/alternatives.py` | Alternative model suggestions |
| `src/poller/comments.py` | Usage commentary generation |
| `src/poller/claude_oauth.py` | Claude OAuth token refresh |
| `src/poller/codex_oauth.py` | Codex OAuth token refresh |
| `src/poller/accounts.py` | Multi-account registry + USD-equivalent value rollup |
| `src/poller/time_utils.py` | ISO parsing, reset-countdown formatting, dot-path resolution |
| `src/poller/MANIFEST.md` | Poller module dependency DAG + public API surface |

## `src/scheduler/`
| Path | Purpose |
|---|---|
| `src/scheduler/__init__.py` | Package init, version |
| `src/scheduler/cli.py` | CLI surface: status, add, run-once, drain, tail |
| `src/scheduler/dispatcher.py` | Single-tick dispatch loop with crash recovery |
| `src/scheduler/queue.py` | YAML-backed job queue with flock + atomic writes |
| `src/scheduler/routing.py` | Meter availability + model-preference ladder walk |
| `src/scheduler/adapters/__init__.py` | Adapter registry |
| `src/scheduler/adapters/base.py` | Adapter protocol + AdapterResult dataclass |
| `src/scheduler/adapters/claude.py` | Claude CLI adapter |
| `src/scheduler/adapters/codex.py` | Codex CLI adapter |
| `src/scheduler/adapters/gemini.py` | Gemini CLI adapter |
| `src/scheduler/adapters/ollama.py` | Ollama adapter |

## `src/common/`
| Path | Purpose |
|---|---|
| `src/common/config.py` | Shared configuration loader for Python subsystems |

## `src/tools/`
| Path | Purpose |
|---|---|
| `src/tools/dep_graph.py` | Generate module dependency graph (feeds `docs/diagrams/module-deps.md`) |

## `src/` navigation aids
| Path | Purpose |
|---|---|
| `src/AI_NAV.md` | AI navigation index for the source tree |
| `src/AGENT_AUDIT_TASKLIST.md` | Categorized source-audit tasks for AI agents |

## `docs/`
| Path | Purpose |
|---|---|
| `docs/INDEX.md` | Documentation map with multi-dimensional navigation |
| `docs/MANIFEST.json` | Machine-readable doc metadata for AI agents |
| `docs/READING_ORDER.md` | Task-based recommended reading paths |
| `docs/architecture.md` | System architecture (5 subsystems) |
| `docs/.ai-context.yaml` | Agent context protocol — scoped summaries |

### `docs/getting-started/`
| Path | Purpose |
|---|---|
| `docs/getting-started/installation.md` | Install + SwiftBar wiring |
| `docs/getting-started/usage.md` | Every command, flag, exit code |
| `docs/getting-started/troubleshooting.md` | Known issues and fixes |

### `docs/reference/`
| Path | Purpose |
|---|---|
| `docs/reference/data-model.md` | JSON schemas and file formats |
| `docs/reference/configuration.md` | Configuration files reference |
| `docs/reference/environment-variables.md` | Environment variables reference |
| `docs/reference/glossary.md` | Term definitions |

### `docs/subsystems/`
| Path | Purpose |
|---|---|
| `docs/subsystems/scheduler.md` | Job scheduler reference |
| `docs/subsystems/usage-monitor.md` | Usage monitor user guide |
| `docs/subsystems/usage-monitor-integration.md` | Usage monitor integration plan (historical) |
| `docs/subsystems/alerts.md` | Alert system reference |
| `docs/subsystems/widget-health.md` | Widget health playbook |
| `docs/subsystems/recipes.md` | Recipe catalog and contracts |
| `docs/subsystems/snapshots.md` | Snapshot format and lifecycle |
| `docs/subsystems/launchd-best-practices.md` | launchd energy/reliability practices |

### `docs/operations/`
| Path | Purpose |
|---|---|
| `docs/operations/runbook.md` | Operational runbook |
| `docs/operations/security-model.md` | Expanded threat model |

### `docs/contributing/`
| Path | Purpose |
|---|---|
| `docs/contributing/CONTRIBUTING-DOCS.md` | Contributing to docs |
| `docs/contributing/developer-hygiene.md` | Local Git hygiene and quality gates |
| `docs/contributing/repository-governance.md` | Branch protection, labels, and release gates |
| `docs/contributing/testing.md` | Bats + Python test conventions |

### `docs/adr/`
| Path | Purpose |
|---|---|
| `docs/adr/0001-record-architecture-decisions.md` | ADR meta |
| `docs/adr/0002-bash-implementation.md` | Why bash, not Python |
| `docs/adr/0003-snapshot-immutability.md` | Snapshot guarantees |
| `docs/adr/0004-usage-monitor-python-carveout.md` | Python carve-out for poller |
| `docs/adr/0005-job-scheduler.md` | Job scheduler architecture |

### `docs/diagrams/`
| Path | Purpose |
|---|---|
| `docs/diagrams/` | 14 Mermaid diagrams (architecture, data-flow, scheduler-flow, alert-pipeline, poller-pipeline, module-deps, meter-state-machine, account-swap-flow, widget-rendering, filesystem-layout, install-lifecycle, ci-pipeline, snapshot-lifecycle, test-architecture) |

### `docs/api/`
| Path | Purpose |
|---|---|
| `docs/api/cli-reference.md` | Generated reference for every `eco` subcommand |
| `docs/api/generate-cli-reference.sh` | Regenerates the CLI reference from source |

### `docs/scripts/`
| Path | Purpose |
|---|---|
| `docs/scripts/validate-links.sh` | Internal link + orphan + INDEX-coverage checker |
| `docs/scripts/doc-stats.sh`, `extract-glossary.sh`, `extract-section.sh`, `search-docs.sh` | Doc maintenance utilities |

### `docs/migration/`, `docs/rfcs/`
| Path | Purpose |
|---|---|
| `docs/migration/README.md` | Version migration notes |
| `docs/rfcs/README.md` | Request-for-comments design proposals |
| `docs/FAQ.md` | Frequently asked questions |

## `scripts/`
> Machine-readable index: [`scripts/MANIFEST.yaml`](./scripts/MANIFEST.yaml) · audit tasks: [`scripts/AGENT_AUDIT_TASKLIST.md`](./scripts/AGENT_AUDIT_TASKLIST.md)

| Path | Purpose |
|---|---|
| `scripts/bootstrap.sh` | One-command dev environment setup (Brew, venv, hooks, install, smoke) |
| `scripts/setup-venv.sh` | Create Python venv and install dev dependencies (3.10–3.13) |
| `scripts/install.sh` | Deploy src → ~/.eco via symlinks |
| `scripts/uninstall.sh` | Remove deployed symlinks |
| `scripts/install-launchagents.sh` | Render + install LaunchAgent plists |
| `scripts/uninstall-launchagents.sh` | Unload and remove LaunchAgents |
| `scripts/install-hooks.sh` | Install pre-commit + commit-msg Git hooks |
| `scripts/install-log-rotation.sh` | Install newsyslog rotation config (requires sudo) |
| `scripts/uninstall-log-rotation.sh` | Remove the eco-commander newsyslog drop-in |
| `scripts/healthcheck.sh` | End-to-end system health verification |
| `scripts/doctor.sh` | Diagnose and repair installation (symlinks, config, logs) |
| `scripts/lint.sh` | Run shellcheck across src/ and scripts/ |
| `scripts/release.sh` | Tag and push a release |
| `scripts/run-poller.sh` | Manual poller invocation wrapper |
| `scripts/run-scheduler.sh` | Manual scheduler dispatcher wrapper |
| `scripts/run-alerts.sh` | Manual eco-alerts wrapper |
| `scripts/toggle-precise.sh` | Toggle precise (server-truth) polling mode |
| `scripts/usage-snapshot.sh` | Usage data snapshot utility |
| `scripts/validate-commit-message.sh` | Validate commit subject against Conventional Commits |
| `scripts/verify-manifest.sh` | Verify MANIFEST.yaml against the filesystem |
| `scripts/lib/` | Shared script libraries (common.sh, snapshot-helpers.sh) |
| `scripts/log-rotate.conf` | newsyslog configuration template |
| `scripts/launchagents/` | LaunchAgent plist templates |

> Scheduler mission examples live under [`examples/missions/`](./examples/missions/). Public snapshot prompts live under [`examples/snapshot-prompts/`](./examples/snapshot-prompts/).

## `tests/`
| Path | Purpose |
|---|---|
| `tests/run-all.sh` | Master runner (BATS + Python + E2E tests) |
| `tests/README.md` | Test architecture documentation |
| `tests/INDEX.md` | Machine-readable file inventory with test counts |
| `tests/COVERAGE_MAP.md` | Source module → test file traceability matrix |
| `tests/AI_NAVIGATION.md` | AI agent navigation guide and decision trees |
| `tests/AGENT_AUDIT_TASKLIST.md` | Categorized improvement tasks for AI agents |
| `tests/bats/` | BATS integration tests (files + recipes/) |
| `tests/e2e/` | End-to-end widget tests |
| `tests/python/` | Python unit tests (files + conftest.py) |
| `tests/python/conftest.py` | Shared path setup + test data factories |
| `tests/python/pytest.ini` | Pytest discovery and marker configuration |
| `tests/fixtures/` | Static test fixtures (state.json variants) |
| `tests/helpers/` | Shared bash helpers + 11 stub executables |

## `.github/`
| Path | Purpose |
|---|---|
| `.github/workflows/ci.yml` | shellcheck + bats on push |
| `.github/workflows/hygiene.yml` | pre-commit, actionlint, and whitespace checks |
| `.github/workflows/security.yml` | secret scan and Python dependency audit |
| `.github/workflows/codeql.yml` | CodeQL Python analysis |
| `.github/workflows/labeler.yml` | PR auto-labeling |
| `.github/workflows/commitlint.yml` | Conventional Commit validation |
| `.github/workflows/release.yml` | GitHub Release publishing |
| `.github/workflows/stale.yml` | Stale issue/PR housekeeping |
| `.github/workflows/dependabot-automerge.yml` | Auto-merge passing Dependabot PRs |
| `.github/workflows/dependency-review.yml` | Dependency diff review on PRs |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Bug report form |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | Feature request form |
| `.github/ISSUE_TEMPLATE/docs_issue.yml` | Documentation issue form |
| `.github/ISSUE_TEMPLATE/release_checklist.yml` | Release checklist form |
| `.github/ISSUE_TEMPLATE/config.yml` | Issue chooser policy and contact links |
| `.github/DISCUSSION_TEMPLATE/` | Discussion forms (general, ideas) |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR template |
| `.github/CODEOWNERS` | Default reviewers |
| `.github/dependabot.yml` | Update policy |
| `.github/labeler.yml` | Path-based PR label rules |
| `.github/settings.yml` | Declarative repository policy |
| `.github/FUNDING.yml` | Sponsorship links |

## `examples/`
| Path | Purpose |
|---|---|
| `examples/missions/` | Generic scheduler mission examples |
| `examples/snapshot-prompts/` | Public prompt library for `eco snapshot` |
