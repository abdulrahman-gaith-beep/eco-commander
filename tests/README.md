# Eco Commander — Test Suite Documentation

> **Last updated:** 2026-06-06 · Three engines: **E2E** (widget), **Python** (poller + scheduler), **BATS** (shell).
> Test counts grow with the suite — get current totals from the runner rather than this doc:
> `make test` (full), or per engine see [Quick Start](#quick-start) below.
>
> See also: [INDEX.md](INDEX.md) · [COVERAGE_MAP.md](COVERAGE_MAP.md) · [AI_NAVIGATION.md](AI_NAVIGATION.md)

## Quick Start

```bash
# Run all three test suites
make test
# — OR individually —
bash tests/e2e/run_e2e.sh                  # E2E widget tests
PYTHONPATH=src python3 -m unittest discover -s tests/python -p "test_*.py"  # Python
bats tests/bats/                            # BATS (if bats installed)
```

## Test Architecture

```
tests/
├── e2e/                     # End-to-end widget tests (bash)
│   ├── run_e2e.sh           # Test runner — tiers T001–T240 (25 tiers)
│   ├── fixtures/            # JSON test fixtures
│   │   └── usage_healthy.json
│   └── results/             # Auto-generated reports + failure artifacts
│       ├── report-*.md
│       ├── run.log
│       └── failures/T*/     # Saved sandbox state on failure
├── python/                  # Python unit tests (unittest + pytest)
│   ├── conftest.py           # Shared path setup + test factories
│   ├── pytest.ini            # Pytest discovery + markers config
│   ├── test_accounts.py      # Poller accounts
│   ├── test_adapters.py      # Scheduler adapters
│   ├── test_alternatives.py  # Poller alternatives
│   ├── test_caps.py          # Token caps calibration
│   ├── test_claude_multi_account.py  # Claude multi-account
│   ├── test_claude_oauth.py  # Claude OAuth
│   ├── test_codex.py         # Codex JSONL accounting
│   ├── test_codex_oauth.py   # Codex OAuth
│   ├── test_comments.py      # Usage commentary
│   ├── test_discovery.py     # Tool discovery
│   ├── test_dispatcher.py    # Scheduler dispatcher
│   ├── test_gemini.py        # Gemini poller
│   ├── test_integration.py   # Poller→widget integration
│   ├── test_notify.py        # macOS notifications
│   ├── test_pace.py          # Rate tracking
│   ├── test_poller_main.py   # Poller entry point
│   ├── test_queue.py         # Scheduler queue
│   ├── test_routing.py       # Scheduler routing helpers
│   ├── test_runtime_config_templates.py  # Runtime config fixtures
│   ├── test_scheduler_cli.py # Scheduler CLI
│   ├── test_scheduler_routing.py  # Scheduler routing
│   ├── test_security.py      # Security hardening
│   └── test_value.py         # Value computation
├── bats/                    # BATS integration tests
│   ├── 00_smoke.bats        # Sandbox gate
│   ├── 01_router.bats       # eco CLI router
│   ├── 02_commander_cli.bats # Widget CLI mode
│   ├── 03_state_parsing.bats # State JSON
│   ├── 04_switch_profile.bats # Profile switching
│   ├── 05_usage_monitor.bats # Usage monitor widget
│   ├── 06_eco_alerts.bats   # Alert system
│   ├── 07_pure_functions.bats # Pure function units
│   ├── 08_installers.bats   # Install/uninstall
│   ├── 09_account_swap.bats # Account rotation
│   ├── 10_hygiene.bats      # Mac hygiene recipe
│   ├── 11_ai_clear.bats     # ai-clear no-op shim
│   ├── 11_lib_common.bats   # Test helper assertions
│   ├── 12_lib_snapshot_helpers.bats  # Snapshot helpers
│   └── recipes/             # Per-recipe tests
├── helpers/
│   ├── common.bash          # Shared test setup/teardown + assertions
│   └── stubs/               # 11 stub executables for external tools
└── run-all.sh               # Master runner (BATS + Python + E2E)
```

## E2E Test Suite (`tests/e2e/run_e2e.sh`)

### How It Works

Each test runs in a **fully isolated sandbox** (`/tmp/eco-e2e.XXXXXX/`) with:
- Fake `~/.eco/` with stubbed files
- Fake `~/.ai-ecosystem/` with profiles
- Controlled `usage.json` from fixtures
- Controlled `state.json` with configurable alert count
- `HOME`, `ECO_HOME`, and `ECO_COMMANDER_REPO` overridden

The widget **never touches your real `~/.eco/`** during testing.

### Test Tiers

| Tier | Tests | What It Covers |
|------|-------|----------------|
| 1. Core Format | T001-T004 | SwiftBar `---` separator, compact icon, pipe params |
| 2. Status Icon | T010-T014 | Green/yellow/red logic, staleness thresholds |
| 3. Missing Deps | T020-T024 | No jq, no usage.json, no state.json, no profiles, no recipes |
| 4. Corrupt Data | T030-T038 | Invalid JSON, empty files, arrays, nulls, negatives, >100%, type mismatches |
| 5. Boundaries | T040-T046 | 0%, 100%, exact 80%/95% thresholds, clock skew, epoch zero |
| 6. Sections | T050-T054 | All 7 sections exist, Claude/Gemini/Codex content correct |
| 7. Stress | T060-T064 | 50 alerts, 20 recipes, 10 profiles, <5s perf, 3 concurrent |
| 8. Errors | T070-T072 | Provider errors, all-error state, stale cache |
| 9. Suggestions | T080-T081 | P1 at 96%, no false-positive at 12% |
| 10. humanize() | T090-T091 | 0 tokens, trillion tokens |
| 11. Actions | T100-T101 | terminal=/refresh= params, bash= format |
| 12. Alerts | T110-T112 | 0 alerts green, multi-alert count, long desc truncation |
| 13. Stability | T120-T121 | Deterministic output, no blank lines |
| 14. Suggestion Priorities | T130-T132 | P2 LAST CALL, P4 SPRINT, P5 burn-fast |
| 15. Alternatives | T140-T141 | All 4 tools shown, hidden when absent |
| 16. Domains | T150 | 11 domains D1-D11 listed |
| 17. Footer | T160-T161 | Snapshot ID, refresh button, absent without state |
| 18. Live Alerts | T170-T172 | n8n verified live, timeout evidence, unknown triage |
| 19. Permissions | T180-T189 | Unreadable files, bad env vars, comments, probes, profiles, recipes |
| 20. Regression | T190-T191 | ≥50 lines output, zero SwiftBar params in CLI mode |
| 21. Recipe Edge Cases | T200-T201 | Recipe error handling and boundary conditions |
| 22. Provider Source Branch | T210 | Provider source branch detection |
| 23. Ollama Edge Cases | T220 | Ollama availability and degradation |
| 24. Alert Layer Parsing | T230-T231 | Alert layer extraction from state |
| 25. Snapshot Age | T240-T241 | Snapshot age formatting and stale warnings |

### Running Single Tests

```bash
bash tests/e2e/run_e2e.sh T042    # Run only test T042
bash tests/e2e/run_e2e.sh --verbose  # Show output on pass
```

### Adding New Tests

1. Create a function `test_TXXX()` that takes a sandbox path
2. Use `install_usage`, `install_state`, `run_widget` helpers
3. Assert with `assert_exit`, `assert_stdout_contains`, `assert_stdout_regex`, etc.
4. Register it with `run_test TXXX "description" test_TXXX` in the runner section

### Harness Features

- **Sandbox isolation**: Each test gets a fresh `/tmp/` directory
- **Trap cleanup**: `SIGINT` cleans all sandboxes (no orphans)
- **30s timeout**: Widget hangs are caught
- **CI-ready**: No colors when not a TTY, non-zero exit on failure
- **Failure artifacts**: Saved to `results/failures/T*/` for post-mortem
- **Markdown report**: Auto-generated at `results/report-*.md`

## Python Test Suite (`tests/python/`)

Covers the poller and scheduler subsystems (run the discover command below for the current count):

| Module | Test File | Coverage |
|--------|-----------|----------|
| `poller.alternatives` | `test_alternatives.py` | ✅ |
| `poller.claude` | `test_claude_multi_account.py`, `test_claude_oauth.py` | ✅ |
| `poller.codex` | `test_codex_oauth.py` | ✅ |
| `poller.comments` | `test_comments.py` | ✅ |
| `poller.discovery` | `test_discovery.py` | ✅ |
| `poller.gemini` | `test_gemini.py` | ✅ |
| `poller.notify` | `test_notify.py` | ✅ |
| `poller.pace` | `test_pace.py` | ✅ |
| `poller.value` | `test_value.py` | ✅ |
| `poller.main` | `test_poller_main.py` | ✅ |
| `poller.caps` | `test_caps.py` | ✅ |
| `scheduler.routing` | `test_scheduler_routing.py`, `test_routing.py` | ✅ |
| `scheduler.queue` | `test_queue.py` | ✅ |
| `scheduler.dispatcher` | `test_dispatcher.py` | ✅ |
| `scheduler.adapters.*` | `test_adapters.py` | ✅ |
| `scheduler.cli` | `test_scheduler_cli.py` | ✅ |
| `common.config` + config templates | `test_runtime_config_templates.py` | ✅ |
| Security hardening | `test_security.py` | ✅ |
| Poller→widget integration | `test_integration.py` | ✅ |

### Running

```bash
PYTHONPATH=src python3 -m unittest discover -s tests/python -p "test_*.py" -v
```

## Dependencies

| Tool | Required By | Install |
|------|-------------|---------|
| `jq` | E2E tests, widget | `brew install jq` |
| `python3` | Python tests, widget | Python 3.10-3.13 |
| `bats` | BATS tests | `brew install bats-core` |
| `timeout` | E2E harness | `brew install coreutils` (provides `gtimeout`) |

## Known Limitations

1. **macOS-only**: `sed -i ''`, `date -v`, `stat -f %m` are BSD-specific
2. **Manual widget probes are live**: E2E tests stub probes, but manual widget runs may hit localhost services
3. **BATS tests**: Require `bats-core` which is not always installed
