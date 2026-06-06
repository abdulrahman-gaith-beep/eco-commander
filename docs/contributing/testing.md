# Testing

> Authoritative guide to eco-commander's test suite: how to run it, what is
> tested, and where fixtures and helpers live.

## Stack

| Engine | Framework | Scope |
|--------|-----------|-------|
| Bash (Bats) | [bats-core](https://bats-core.readthedocs.io/) | Shell scripts, recipes, installers, and CLI routing |
| Python | `unittest` + `pytest` | `src/poller/` and `src/scheduler/` units and integration boundaries |
| End-to-end | Custom shell harness | Live widget flows in isolated sandboxes |

- **Bats** covers all shell scripts, recipes, and the eco CLI.
- **Python** covers `src/poller/` and `src/scheduler/` via `unittest discover`
  (the same runner as CI); `pytest` markers are also wired for selective runs.
- **E2E** drives the live widget binary (`src/bin/eco-commander.15s.sh`) across
  named tiers in fully isolated `/tmp` sandboxes.
- **shellcheck** static analysis runs as a pre-commit hook and in CI.
- A sandboxed `$HOME` per test is created by the helpers in
  `tests/helpers/common.bash` so the user's real `~/.eco/` is never touched.

## Layout

```text
tests/
├── run-all.sh                    # master runner (Bats + Python + E2E)
├── README.md                     # detailed narrative
├── INDEX.md                      # machine-readable file inventory
├── COVERAGE_MAP.md               # source module → test traceability
├── AI_NAVIGATION.md              # AI agent navigation guide
├── AGENT_AUDIT_TASKLIST.md       # improvement tasks for AI agents
│
├── helpers/
│   ├── common.bash               # shared setup/teardown + assertion helpers
│   └── stubs/                    # stub executables for external commands
│
├── fixtures/                     # shared canned snapshots and mock states
│   ├── state.json.good
│   ├── state.json.malformed
│   └── state.json.no_issues
│
├── bats/                         # Bats suites
│   ├── 00_smoke.bats             # sandbox gate
│   ├── 01_router.bats            # eco CLI router
│   ├── 02_commander_cli.bats     # widget CLI mode
│   ├── 03_state_parsing.bats     # state JSON parsing
│   ├── 04_switch_profile.bats    # profile switching
│   ├── 05_usage_monitor.bats     # usage monitor widget
│   ├── 06_eco_alerts.bats        # alert system
│   ├── 07_pure_functions.bats    # pure function units
│   ├── 08_installers.bats        # install/uninstall
│   ├── 09_account_swap.bats      # account rotation
│   ├── 10_hygiene.bats           # Mac hygiene recipe
│   ├── 11_ai_clear.bats          # ai-clear command
│   ├── 11_lib_common.bats        # lib/common helpers
│   ├── 12_lib_snapshot_helpers.bats  # snapshot helpers
│   └── recipes/                  # per-recipe suites
│       ├── 10_ask.bats  11_research.bats  12_arabic_proof.bats
│       ├── 13_note.bats 14_swarm.bats     15_snapshot.bats
│       ├── 16_dashboard.bats  17_dashboard_refresh.bats
│       └── 18_n8n_start.bats
│
├── python/                       # Python unit tests
│   ├── conftest.py               # shared path setup + test factories
│   ├── pytest.ini                # pytest discovery, markers, addopts
│   └── test_*.py                 # discovered unit test files
│
└── e2e/                          # E2E harness
    ├── run_e2e.sh                # E2E runner
    ├── fixtures/                 # E2E-specific fixtures (usage_healthy.json)
    └── results/                  # auto-generated reports (gitignored)
```

## Running the suites

### Full suite (all engines)

```bash
make test
# or equivalently:
bash tests/run-all.sh
```

### Fast local loop (Bats + Python, skip E2E)

```bash
make test-fast
```

### Individual engines

```bash
# Bats only
make test-bats
bash tests/run-all.sh bats

# Python — unittest (primary runner, matches CI)
make test-python
PYTHONPATH=src python3 -m unittest discover -s tests/python -p "test_*.py"

# Python — pytest (if installed; supports markers and -k filtering)
python3 -m pytest tests/python/
python3 -m pytest tests/python/ -m poller
python3 -m pytest tests/python/ -m "security or integration"

# E2E
make test-e2e
bash tests/e2e/run_e2e.sh
bash tests/e2e/run_e2e.sh T042   # single test by ID
```

### Single Bats suites

```bash
bats tests/bats/00_smoke.bats       # smoke gate only
bats tests/bats/                    # all non-recipe suites
bats tests/bats/recipes/            # all recipe suites

bash tests/run-all.sh smoke         # smoke subset via run-all.sh
bash tests/run-all.sh recipes       # recipes subset via run-all.sh
bash tests/run-all.sh --pretty      # pretty formatter
bash tests/run-all.sh --parallel    # parallel execution (requires GNU parallel)
```

## pytest markers

Markers are declared in `tests/python/pytest.ini`:

| Marker | Meaning |
|--------|---------|
| `poller` | Tests for `src/poller/` |
| `scheduler` | Tests for `src/scheduler/` |
| `integration` | Cross-subsystem integration tests |
| `security` | Security and hardening tests |
| `slow` | Tests that take > 2 seconds |

## Conventions

### Bats tests

1. Every file begins with `load ../helpers/common` (or `load ../../helpers/common`
   for recipes).
2. `setup()` calls `eco_setup`, which builds a sandboxed `$HOME` and copies the
   real `eco` binary and recipes into it. Tests operate on `$HOME/.eco/`, never
   the user's install.
3. Use `run <command>` so failures attach stdout, stderr, and exit code.
4. Every recipe gets at least: a happy path, an invalid-args path, and an
   external-failure path (network mocked via stubs).
5. File naming: `NN_descriptive_name.bats` (two-digit zero-padded prefix).

### Python tests

1. Tests live under `tests/python/` and target `src/poller/` and
   `src/scheduler/`.
2. Use `unittest.TestCase` subclasses; `pytest` can discover them too.
3. Mock all external API calls and file I/O — never hit real OAuth endpoints.
4. Inject fake `usage.json`, `notify.json`, and `jobs.yaml` for deterministic
   results.
5. Shared utilities (path setup, data factories) are in `conftest.py`.

### E2E tests

1. Each test runs in a fully isolated sandbox under `/tmp/eco-e2e.XXXXXX/`.
2. Use `setup_sandbox`, `run_widget`, `install_usage`, `install_state` helpers
   defined in `run_e2e.sh`.
3. Assert with `assert_exit`, `assert_stdout_contains`, `assert_stdout_regex`.
4. Reports auto-generated to `results/` (gitignored).
5. Tiers use `T###` ids; run a single tier with a command such as `run_e2e.sh T042`.

## Fixtures and helpers

| Path | Purpose |
|------|---------|
| `tests/helpers/common.bash` | Sandboxed-HOME helpers, assertion library |
| `tests/helpers/stubs/` | Stub executables for external commands (`claude`, `curl`, `gemini`, `ollama`, `open`, `osascript`, `python3`, and related tools) |
| `tests/fixtures/state.json.*` | Canned state: healthy, malformed, no-issues |
| `tests/fixtures/` | Shared fixtures for Bats and unit tests |
| `tests/e2e/fixtures/usage_healthy.json` | E2E baseline usage snapshot |
| `tests/python/conftest.py` | Path setup + data factory functions |

## CI

`.github/workflows/ci.yml` runs install smoke, `make lint`, actionlint, mypy,
Bats, E2E, and Python unit tests with coverage on every push and PR against
`main` for Python 3.10 and 3.13. The `Repository Hygiene` workflow runs
`pre-commit --all-files`, which also triggers `shellcheck`.

## Related

- [developer-hygiene.md](./developer-hygiene.md) — pre-commit hooks and quality
  gates that run on every commit
- [repository-governance.md](./repository-governance.md) — required CI checks
  for merging to `main`
- [tests/AI_NAVIGATION.md](../../tests/AI_NAVIGATION.md) — decision trees for
  finding the right tests
- [tests/COVERAGE_MAP.md](../../tests/COVERAGE_MAP.md) — source-to-test
  traceability
- [tests/AGENT_AUDIT_TASKLIST.md](../../tests/AGENT_AUDIT_TASKLIST.md) —
  improvement tasks
