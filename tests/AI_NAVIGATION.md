# AI Agent Navigation Guide — Tests Directory

> **Purpose**: Structured decision trees and conventions for AI agents working on eco-commander tests.
> This file is the FIRST thing an agent should read when assigned test-related work.

---

## Decision Tree: "I Changed Source Code — What Tests Do I Run?"

```
Start: What did you change?
│
├─ src/bin/eco → bats tests/bats/01_router.bats
│
├─ src/bin/eco-commander.15s.sh
│   ├─ Token display?     → bash tests/e2e/run_e2e.sh T050
│   ├─ Alert rendering?   → bash tests/e2e/run_e2e.sh T110
│   ├─ Status icon logic? → bash tests/e2e/run_e2e.sh T010
│   ├─ CLI mode?          → bats tests/bats/02_commander_cli.bats
│   ├─ State parsing?     → bats tests/bats/03_state_parsing.bats
│   └─ Full regression    → bash tests/e2e/run_e2e.sh
│
├─ src/bin/eco-alerts.sh → bats tests/bats/06_eco_alerts.bats
│
├─ src/poller/*.py
│   ├─ main.py       → python3 -m pytest tests/python/test_poller_main.py -v
│   ├─ claude.py     → python3 -m pytest tests/python/test_claude_multi_account.py tests/python/test_claude_oauth.py -v
│   ├─ codex.py      → python3 -m pytest tests/python/test_codex.py tests/python/test_codex_oauth.py -v
│   ├─ gemini.py     → python3 -m pytest tests/python/test_gemini.py -v
│   ├─ caps.py       → python3 -m pytest tests/python/test_caps.py -v
│   ├─ notify.py     → python3 -m pytest tests/python/test_notify.py -v
│   ├─ pace.py       → python3 -m pytest tests/python/test_pace.py -v
│   ├─ value.py      → python3 -m pytest tests/python/test_value.py -v
│   ├─ discovery.py  → python3 -m pytest tests/python/test_discovery.py -v
│   ├─ alternatives.py → python3 -m pytest tests/python/test_alternatives.py -v
│   ├─ comments.py   → python3 -m pytest tests/python/test_comments.py -v
│   ├─ accounts.py   → python3 -m pytest tests/python/test_accounts.py -v
│   ├─ claude_oauth.py → python3 -m pytest tests/python/test_claude_oauth.py -v
│   ├─ codex_oauth.py  → python3 -m pytest tests/python/test_codex_oauth.py -v
│   └─ time_utils.py   → covered indirectly via test_poller_main.py / test_gemini.py
│
├─ src/scheduler/*.py
│   ├─ cli.py        → python3 -m pytest tests/python/test_scheduler_cli.py -v
│   ├─ dispatcher.py → python3 -m pytest tests/python/test_dispatcher.py -v
│   ├─ queue.py      → python3 -m pytest tests/python/test_queue.py -v
│   ├─ routing.py    → python3 -m pytest tests/python/test_scheduler_routing.py -v
│   └─ adapters/*    → python3 -m pytest tests/python/test_adapters.py -v
│
├─ src/recipes/*.sh
│   ├─ ask.sh              → bats tests/bats/recipes/10_ask.bats
│   ├─ research.sh         → bats tests/bats/recipes/11_research.bats
│   ├─ arabic-proof.sh     → bats tests/bats/recipes/12_arabic_proof.bats
│   ├─ note.sh             → bats tests/bats/recipes/13_note.bats
│   ├─ swarm.sh            → bats tests/bats/recipes/14_swarm.bats
│   ├─ snapshot.sh         → bats tests/bats/recipes/15_snapshot.bats
│   ├─ dashboard.sh        → bats tests/bats/recipes/16_dashboard.bats
│   ├─ dashboard-refresh.sh → bats tests/bats/recipes/17_dashboard_refresh.bats
│   ├─ n8n-start.sh        → bats tests/bats/recipes/18_n8n_start.bats
│   ├─ hygiene.sh          → bats tests/bats/10_hygiene.bats
│   ├─ account-swap.sh     → bats tests/bats/09_account_swap.bats
│   └─ scheduler-seed.sh   → (no dedicated test yet — see AGENT_AUDIT_TASKLIST.md)
│
└─ Cross-cutting changes (JSON schema, security, permissions)
    → PYTHONPATH=src python3 -m pytest tests/python/test_security.py tests/python/test_integration.py -v
    → bash tests/e2e/run_e2e.sh
```

---

## File Naming Conventions

### BATS Tests
- **Pattern**: `NN_descriptive_name.bats` (zero-padded two-digit prefix)
- **Core / widget / alerts**: `00-08` in `tests/bats/`
- **Account, hygiene, ai-clear, lib helpers**: `09-12` in `tests/bats/` (note: `11` is shared by `11_ai_clear.bats` and `11_lib_common.bats`)
- **Recipe tests**: `10-18` in `tests/bats/recipes/`
- **Load pattern**: `load '../helpers/common.bash'` (or `'../../helpers/common.bash'` for recipes)
- **Setup/teardown**: Always use `eco_setup` / `eco_teardown`

### Python Tests
- **Pattern**: `test_<source_module_name>.py`
- **Framework**: `unittest.TestCase` (stdlib only — no pytest dependency required)
- **Path setup**: `sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "src"))`
- **Imports**: Always import from `src/` package names (`from poller.main import ...`)
- **Temp dirs**: `tempfile.mkdtemp(prefix="eco-<purpose>-test-")`

### E2E Tests
- **Pattern**: `test_TXXX()` function inside `run_e2e.sh`
- **Registration**: `run_test TXXX "description" test_TXXX`
- **Sandbox**: Use `setup_sandbox` / `teardown_sandbox`
- **Helpers**: `install_usage`, `install_state`, `run_widget`
- **Assertions**: `assert_exit`, `assert_stdout_contains`, `assert_stdout_regex`, `assert_stdout_not_contains`

---

## How to Add New Tests

### Adding a BATS Test
1. Create `tests/bats/NN_name.bats` (next available number)
2. Add header: `#!/usr/bin/env bats`
3. Add: `load '../helpers/common.bash'`
4. Add: `setup() { eco_setup; }` and `teardown() { eco_teardown; }`
5. Write `@test "description" { ... }` blocks
6. Tests auto-discovered by `run-all.sh` (scans `bats/` directory)

### Adding a Python Test
1. Create `tests/python/test_<module>.py`
2. Add path setup boilerplate (see conventions above)
3. Import target module from `src/`
4. Write `class TestX(unittest.TestCase)` with `test_*` methods
5. Tests auto-discovered by `python3 -m unittest discover`

### Adding an E2E Test
1. Open `tests/e2e/run_e2e.sh`
2. Create function `test_TXXX()` in the appropriate tier section
3. Register with `run_test TXXX "description" test_TXXX` in the runner section
4. Use the sandbox pattern: receive `$1` as sandbox path

---

## Stub System Reference

All stubs live in `tests/helpers/stubs/` and are prepended to `$PATH` during BATS setup.

| Stub | Controls (env vars) | Behavior |
|------|---------------------|----------|
| `gemini` | `STUB_GEMINI_OUTPUT`, `STUB_GEMINI_EXIT`, `STUB_GEMINI_SLEEP`, `STUB_GEMINI_STDERR` | Logs to `$HOME/.stub-gemini.log` |
| `ollama` | `STUB_OLLAMA_RUNNING` (0/1), `STUB_OLLAMA_LOADED` (csv), `STUB_OLLAMA_LIST`, `STUB_OLLAMA_OUTPUT` | Simulates ps/list/run/stop |
| `claude` | — | Logs to `$HOME/.stub-claude.log` |
| `curl` | `STUB_CURL_EXIT` | Controllable exit code |
| `vm_stat` | `STUB_PAGE_SIZE`, `STUB_PAGES_FREE`, `STUB_PAGES_INACTIVE`, `STUB_PAGES_PURGEABLE`, `STUB_PAGES_SPECULATIVE` | Deterministic RAM values |
| `sysctl` | `STUB_PAGE_SIZE` | Page size query |
| `open` | — | Logs URLs to `$HOME/.stub-open.log` |
| `osascript` | — | No-op |
| `python3` | — | Configurable stub |
| `perplexity` | — | Logs calls |
| `tavily` | — | Logs calls |

### Assertion Helpers (common.bash)

| Function | Purpose |
|----------|---------|
| `assert_success` | Exit status == 0 |
| `assert_failure [code]` | Exit status != 0, optionally specific code |
| `assert_output_contains "needle"` | `$output` contains string |
| `assert_output_not_contains "needle"` | `$output` does NOT contain string |
| `assert_stub_called "name"` | Stub log file is non-empty |
| `assert_stub_args_contain "name" "args"` | Stub log contains argument string |

---

## Quick Commands Reference

```bash
# === Full Suite ===
make test                    # Full suite (BATS + Python + E2E)
make test-fast               # BATS + Python only (skip E2E)

# === Individual Engines ===
make test-bats               # BATS suite
make test-python             # Python suite
make test-e2e                # E2E suite

# === Single Files ===
bats tests/bats/00_smoke.bats
PYTHONPATH=src python3 -m unittest tests/python/test_security.py -v
bash tests/e2e/run_e2e.sh T042

# === Targeted Python ===
PYTHONPATH=src python3 -m unittest tests.python.test_adapters.TestGeminiAdapter.test_dry_run_mode -v

# === Smoke Only ===
bash tests/run-all.sh smoke
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    make test                             │
│  ┌──────────────┬────────────────┬──────────────────┐   │
│  │  test-bats   │  test-python   │    test-e2e      │   │
│  │  run-all.sh  │  unittest      │  run_e2e.sh      │   │
│  │              │  discover      │                  │   │
│  │              │                │                  │   │
│  ├──────────────┼────────────────┼──────────────────┤   │
│  │ helpers/     │ sys.path hack  │ sandbox harness   │   │
│  │ common.bash  │ per-file       │ setup_sandbox()   │   │
│  │ stubs/       │                │ run_widget()      │   │
│  └──────┬───────┴───────┬────────┴────────┬─────────┘   │
│         │               │                 │              │
│  ┌──────▼───────┐ ┌─────▼──────┐  ┌──────▼─────────┐   │
│  │ fixtures/    │ │ src/poller/ │  │ src/bin/        │   │
│  │ state.json.* │ │ src/scheduler/│  │ eco-commander   │   │
│  └──────────────┘ └────────────┘  └────────────────┘   │
└─────────────────────────────────────────────────────────┘
```
