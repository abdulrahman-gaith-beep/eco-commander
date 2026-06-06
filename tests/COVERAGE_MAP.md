# Coverage Map — Source Module → Test Traceability

> Last updated: 2026-06-04 · Tracks every `src/` module and its test coverage.

## Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Has dedicated test file(s) |
| ⚠️ | Partially covered (embedded in broader test) |
| ❌ | **No dedicated tests** |

---

## `src/bin/` — CLI Executables

| Source Module | Size | Test File(s) | Status | Notes |
|---------------|------|-------------|--------|-------|
| `eco` | 3.1KB | `bats/01_router.bats` (22 tests) | ✅ | Full CLI routing coverage |
| `eco-commander.15s.sh` | 37KB | `bats/02_commander_cli.bats` (21), `bats/03_state_parsing.bats` (10), `bats/05_usage_monitor.bats` (8), `e2e/run_e2e.sh` (85), `python/test_integration.py` (4) | ✅ | Best covered module — 128 tests |
| `eco-alerts.sh` | 29KB | `bats/06_eco_alerts.bats` (18) | ⚠️ | 18 tests for 29KB script — needs deeper edge case testing |
| `ai-clear.sh` | <1KB | `bats/11_ai_clear.bats` (7) | ✅ | Deprecated no-op compatibility behavior |
| `install-commander.sh` | 2.2KB | `bats/08_installers.bats` (13) | ⚠️ | Install script tests exist but may not cover this file specifically |

---

## `src/poller/` — Python Poller Modules

| Source Module | Size | Test File(s) | Tests | Status |
|---------------|------|-------------|-------|--------|
| `main.py` | 11.7KB | `test_poller_main.py` | 26 | ✅ |
| `claude.py` | 16.3KB | `test_claude_multi_account.py` | 8 | ⚠️ Low count for largest module |
| `claude_oauth.py` | 7.4KB | `test_claude_oauth.py` | 15 | ✅ |
| `codex.py` | 8.8KB | `test_codex.py` | 13 | ✅ |
| `codex_oauth.py` | 6.9KB | `test_codex_oauth.py` | 18 | ✅ |
| `gemini.py` | 15.5KB | `test_gemini.py` | 11 | ⚠️ Low for 15.5KB module |
| `caps.py` | 4.2KB | `test_caps.py` | 18 | ✅ |
| `notify.py` | 11.1KB | `test_notify.py` | 12 | ⚠️ Low for 11KB module |
| `pace.py` | 6.5KB | `test_pace.py` | 7 | ✅ |
| `value.py` | 10.4KB | `test_value.py` | 9 | ⚠️ Low for 10.4KB module |
| `discovery.py` | 4.8KB | `test_discovery.py` | 12 | ✅ |
| `alternatives.py` | 3.0KB | `test_alternatives.py` | 4 | ✅ |
| `comments.py` | 4.2KB | `test_comments.py` | 10 | ✅ |
| `accounts.py` | 7.0KB | `test_accounts.py` | 33 | ✅ |
| `time_utils.py` | — | — | — | ❌ No tests — utility module used by claude/codex/gemini/notify but not directly tested |

---

## `src/scheduler/` — Job Scheduler

| Source Module | Size | Test File(s) | Tests | Status |
|---------------|------|-------------|-------|--------|
| `cli.py` | 7.5KB | `test_scheduler_cli.py` | 13 | ✅ |
| `dispatcher.py` | 9.0KB | `test_dispatcher.py` | 13 | ✅ |
| `queue.py` | 12.7KB | `test_queue.py` | 31 | ✅ |
| `routing.py` | 4.7KB | `test_scheduler_routing.py` | 13 | ✅ |
| `adapters/__init__.py` | 0.7KB | `test_adapters.py` | 29 | ✅ |
| `adapters/base.py` | 4.0KB | `test_adapters.py` | — | ✅ (covered via adapter tests) |
| `adapters/gemini.py` | 7.1KB | `test_adapters.py` | — | ✅ |
| `adapters/codex.py` | 7.4KB | `test_adapters.py` | — | ✅ |
| `adapters/ollama.py` | 3.9KB | `test_adapters.py` | — | ✅ |
| `adapters/claude.py` | — | — | — | ❌ No tests — Claude adapter added but not yet covered by `test_adapters.py` |

---

## `src/common/` — Shared Utilities

| Source Module | Size | Test File(s) | Tests | Status |
|---------------|------|-------------|-------|--------|
| `config.py` | — | — | — | ❌ No tests — shared config loader has no dedicated test file |

---

## `src/tools/` — Developer Tools

| Source Module | Size | Test File(s) | Tests | Status |
|---------------|------|-------------|-------|--------|
| `dep_graph.py` | — | — | — | ❌ No tests — dependency graph tool has no dedicated test file |

---

## `src/recipes/` — Bash Recipes

| Source Module | Size | Test File(s) | Tests | Status |
|---------------|------|-------------|-------|--------|
| `ask.sh` | 1.2KB | `bats/recipes/10_ask.bats` | 6 | ✅ |
| `note.sh` | 2.0KB | `bats/recipes/13_note.bats` | 6 | ✅ |
| `research.sh` | 1.9KB | `bats/recipes/11_research.bats` | 5 | ✅ |
| `swarm.sh` | 2.4KB | `bats/recipes/14_swarm.bats` | 7 | ✅ |
| `snapshot.sh` | 10.9KB | `bats/recipes/15_snapshot.bats` | 8 | ⚠️ Low for 10.9KB |
| `arabic-proof.sh` | 1.8KB | `bats/recipes/12_arabic_proof.bats` | 7 | ✅ |
| `dashboard.sh` | 0.3KB | `bats/recipes/16_dashboard.bats` | 3 | ✅ |
| `dashboard-refresh.sh` | 6.3KB | `bats/recipes/17_dashboard_refresh.bats` | 8 | ✅ |
| `n8n-start.sh` | 4.6KB | `bats/recipes/18_n8n_start.bats` | 5 | ✅ |
| `hygiene.sh` | 12.0KB | `bats/10_hygiene.bats` | 9 | ⚠️ Low for 12KB |
| `account-swap.sh` | 14.6KB | `bats/09_account_swap.bats` | 20 | ✅ |

---

## Cross-Cutting Test Coverage

| Concern | Test File(s) | Status |
|---------|-------------|--------|
| Security hardening | `test_security.py` (10), `test_adapters.py` (secret redaction) | ✅ |
| Poller→widget integration | `test_integration.py` (4) | ⚠️ Only 4 tests |
| Concurrent writes | `test_security.py` (2) | ✅ |
| File permissions (0o600/0o700) | `test_security.py`, `test_adapters.py`, `account-swap.bats` | ✅ |
| Sandbox isolation | `bats/00_smoke.bats` (10), `e2e/run_e2e.sh` (all) | ✅ |
| macOS notifications | `test_notify.py` | ✅ |

---

## Uncovered Modules Summary

| Module | Size | Priority | Recommended Action |
|--------|------|----------|-------------------|
| ~~`src/poller/accounts.py`~~ | ~~7.0KB~~ | ~~🔴~~ | ✅ Fixed: `test_accounts.py` (33 tests) |
| ~~`src/bin/ai-clear.sh`~~ | ~~1.6KB~~ | ~~🟡~~ | ✅ Fixed: `11_ai_clear.bats` (7 tests) |
| `src/bin/install-commander.sh` | 2.2KB | 🟡 MEDIUM | Verify `08_installers.bats` covers it |
| `src/common/config.py` | — | 🟡 MEDIUM | Create `test_config.py` for shared config loader |
| `src/tools/dep_graph.py` | — | 🟢 LOW | Create `test_dep_graph.py` for dependency graph tool |
| `src/scheduler/adapters/claude.py` | — | 🔴 HIGH | Add Claude adapter tests to `test_adapters.py` (other adapters are covered) |
| `src/poller/time_utils.py` | — | 🟡 MEDIUM | Create `test_time_utils.py`; module is imported by 4 pollers but never directly tested |

## Under-Tested Modules (test count < source KB)

| Module | Size | Tests | Ratio | Recommended |
|--------|------|-------|-------|-------------|
| `poller/codex.py` | 8.8KB | 13 | 1.5 | ✅ Fixed (was 3 tests) |
| `poller/claude.py` | 16.3KB | 8 | 0.5 | Add 10+ more tests |
| `poller/gemini.py` | 15.5KB | 11 | 0.7 | Add 5-8 more tests |
| `poller/notify.py` | 11.1KB | 11 | 1.0 | Add edge case tests |
| `poller/value.py` | 10.4KB | 9 | 0.9 | Add boundary tests |
| `recipes/snapshot.sh` | 10.9KB | 8 | 0.7 | Add error path tests |
| `recipes/hygiene.sh` | 12.0KB | 9 | 0.8 | Add subcommand tests |
