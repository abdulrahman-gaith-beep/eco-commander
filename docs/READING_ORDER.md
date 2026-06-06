# Reading Order

Task-based recommended reading paths for navigating eco-commander documentation.
Each path lists docs in dependency order — read them top to bottom.

## By Task

### 🚀 First-time setup
| Step | Doc | What you'll learn |
|------|-----|-------------------|
| 1 | [tutorials/first-run.md](./tutorials/first-run.md) | Guided end-to-end first run (start here) |
| 2 | [concepts/mental-model.md](./concepts/mental-model.md) | How to think about the system |
| 3 | [architecture.md](./architecture.md) | System overview — 5 subsystems, data flow |
| 4 | [getting-started/installation.md](./getting-started/installation.md) | Install and configure |
| 5 | [getting-started/usage.md](./getting-started/usage.md) | CLI commands and flags |
| 6 | [reference/glossary.md](./reference/glossary.md) | Project-specific terms |

### 🐛 Debug the usage poller
| Step | Doc | What you'll learn |
|------|-----|-------------------|
| 1 | [architecture.md §7](./architecture.md) | Poller overview and module layout |
| 2 | [subsystems/usage-monitor.md](./subsystems/usage-monitor.md) | Per-tool sources, calibration, troubleshooting |
| 3 | [reference/data-model.md §usage.json](./reference/data-model.md) | JSON schema for `usage.json` and per-tool files |
| 4 | [operations/runbook.md §2](./operations/runbook.md) | Step-by-step: "Usage poller is not updating" |
| 5 | [reference/configuration.md §Poller](./reference/configuration.md) | Poller config, caps.py, OAuth credentials |

### ⏱️ Debug the job scheduler
| Step | Doc | What you'll learn |
|------|-----|-------------------|
| 1 | [architecture.md §8](./architecture.md) | Scheduler overview |
| 2 | [subsystems/scheduler.md](./subsystems/scheduler.md) | Full reference: CLI, job YAML, meters, adapters |
| 3 | [reference/data-model.md §jobs.yaml](./reference/data-model.md) | Job queue schema |
| 4 | [reference/data-model.md §notify.json](./reference/data-model.md) | Meter state schema |
| 5 | [operations/runbook.md §3](./operations/runbook.md) | Step-by-step: "Scheduler is stuck" |

### 📝 Add a new recipe
| Step | Doc | What you'll learn |
|------|-----|-------------------|
| 1 | [subsystems/recipes.md](./subsystems/recipes.md) | Recipe contract, catalog, header annotations |
| 2 | [architecture.md §5](./architecture.md) | How recipes fit in the system |
| 3 | [subsystems/snapshots.md](./subsystems/snapshots.md) | Snapshot format (if your recipe creates snapshots) |
| 4 | [contributing/testing.md](./contributing/testing.md) | How to write Bats tests for recipes |
| 5 | [contributing/CONTRIBUTING-DOCS.md](./contributing/CONTRIBUTING-DOCS.md) | Doc update requirements |

### 🔌 Add a new scheduler adapter
| Step | Doc | What you'll learn |
|------|-----|-------------------|
| 1 | [subsystems/scheduler.md §Adapters](./subsystems/scheduler.md) | Adapter protocol, `fire()` signature, error kinds |
| 2 | [reference/data-model.md §jobs.yaml](./reference/data-model.md) | Job schema: `model_preference` ladder |
| 3 | [reference/glossary.md](./reference/glossary.md) | Terms: adapter, rung, ladder, meter, hard wall |
| 4 | [contributing/testing.md](./contributing/testing.md) | Python test conventions for adapters |

### 🔔 Investigate alert issues
| Step | Doc | What you'll learn |
|------|-----|-------------------|
| 1 | [subsystems/alerts.md](./subsystems/alerts.md) | Alert subcommands and lifecycle |
| 2 | [subsystems/widget-health.md](./subsystems/widget-health.md) | Fix tiers, alert truth, 24/7 manager |
| 3 | [architecture.md §4.2](./architecture.md) | How the widget reads alerts |
| 4 | [operations/runbook.md §1](./operations/runbook.md) | General recovery procedure |

### 🔐 Security review / audit
| Step | Doc | What you'll learn |
|------|-----|-------------------|
| 1 | [operations/security-model.md](./operations/security-model.md) | Trust boundaries, credential handling, attack surface |
| 2 | [reference/configuration.md §OAuth](./reference/configuration.md) | OAuth credential stores (read-only) |
| 3 | [reference/environment-variables.md](./reference/environment-variables.md) | Env var overrides (potential injection points) |
| 4 | [subsystems/launchd-best-practices.md](./subsystems/launchd-best-practices.md) | LaunchAgent security considerations |

### 🤝 First-time contributor
| Step | Doc | What you'll learn |
|------|-----|-------------------|
| 1 | [architecture.md](./architecture.md) | System overview |
| 2 | [contributing/developer-hygiene.md](./contributing/developer-hygiene.md) | Commit conventions, pre-commit hooks |
| 3 | [contributing/testing.md](./contributing/testing.md) | Test architecture and how to run tests |
| 4 | [contributing/CONTRIBUTING-DOCS.md](./contributing/CONTRIBUTING-DOCS.md) | When and how to update docs |
| 5 | [contributing/repository-governance.md](./contributing/repository-governance.md) | Branch rules and release gates |

### ⚡ launchd / energy tuning
| Step | Doc | What you'll learn |
|------|-----|-------------------|
| 1 | [subsystems/launchd-best-practices.md](./subsystems/launchd-best-practices.md) | Energy-efficient background scheduling |
| 2 | [reference/configuration.md §LaunchAgent](./reference/configuration.md) | Plist templates and settings |
| 3 | [architecture.md §10](./architecture.md) | Three LaunchAgents and their cadences |

---

## Agent-Specific Paths

### 🤖 "I need to understand everything about a JSON file"
`MANIFEST.json` → find the doc with `"tags"` matching your JSON file → read that doc's `"sections"` list → use `scripts/extract-section.sh` to pull just the section you need.

### 🤖 "I need to find where a concept is defined"
`reference/glossary.md` → find the term → follow the cross-reference link → read the target section.

### 🤖 "I need to know which docs are relevant to my task"
Parse `MANIFEST.json` → filter by `"subsystems"` or `"tags"` → sort by `"depends_on"` (read dependencies first) → read in dependency order.

### 🤖 "I need to understand the agent audit boundary"
`operations/security-model.md §Product vs. audit behavior` → `operations/security-model.md §Credential handling` — these define what agents may and may not access.
