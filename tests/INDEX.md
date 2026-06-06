# Tests — File Index

> Last updated: 2026-06-06 · Counts are intentionally runner-discovered; use the commands below for current totals.

## Quick Reference

| Engine | Runner | Scope |
|--------|--------|-------|
| BATS | `bash tests/run-all.sh bats` | Shell integration tests |
| Python | `PYTHONPATH=src python3 -m unittest discover -s tests/python` | Poller + scheduler unit tests |
| E2E | `bash tests/e2e/run_e2e.sh` | Widget end-to-end regression |
| **All** | `make test` (or `bash tests/run-all.sh`) | Full suite — BATS + Python + E2E |

---

## Top Level

| Path | Purpose | Engine |
|------|---------|--------|
| `run-all.sh` | Master runner — all engines (BATS + Python + E2E); accepts `bats`/`python`/`e2e`/`smoke`/… subsets | bash |
| `README.md` | Test architecture documentation | — |
| `INDEX.md` | This file — machine-readable test directory index | — |
| `COVERAGE_MAP.md` | Source module → test file traceability | — |
| `AI_NAVIGATION.md` | AI agent navigation guide and decision trees | — |
| `AGENT_AUDIT_TASKLIST.md` | Agent-assignable improvement tasks | — |

---

## `bats/` — Shell Integration Tests

| File | Source Module Covered | Tags |
|------|-----------------------|------|
| `00_smoke.bats` | sandbox, stubs | `smoke`, `foundation` |
| `01_router.bats` | `src/bin/eco` | `cli`, `routing` |
| `02_commander_cli.bats` | `src/bin/eco-commander.15s.sh` | `widget`, `cli-mode` |
| `03_state_parsing.bats` | `src/bin/eco-commander.15s.sh` | `state`, `json` |
| `04_switch_profile.bats` | profile switching | `mcp`, `profiles` |
| `05_usage_monitor.bats` | `src/bin/eco-commander.15s.sh` | `widget`, `usage` |
| `06_eco_alerts.bats` | `src/bin/eco-alerts.sh` | `alerts`, `doctor` |
| `07_pure_functions.bats` | pure functions in widget | `unit`, `pure` |
| `08_installers.bats` | `scripts/install.sh` | `install`, `uninstall` |
| `09_account_swap.bats` | `src/recipes/account-swap.sh` | `auth`, `security`, `keychain` |
| `10_hygiene.bats` | `src/recipes/hygiene.sh` | `recipes`, `launchd` |
| `11_ai_clear.bats` | `src/bin/ai-clear.sh` | `ollama`, `clear`, `swarm` |
| `11_lib_common.bats` | `tests/helpers/common.bash` | `helpers`, `assertions` |
| `12_lib_snapshot_helpers.bats` | snapshot helper functions | `helpers`, `snapshot` |

### `bats/recipes/` — Recipe Tests

| File | Source Module Covered | Tags |
|------|-----------------------|------|
| `10_ask.bats` | `src/recipes/ask.sh` | `recipes`, `llm` |
| `11_research.bats` | `src/recipes/research.sh` | `recipes`, `llm` |
| `12_arabic_proof.bats` | `src/recipes/arabic-proof.sh` | `recipes`, `i18n` |
| `13_note.bats` | `src/recipes/note.sh` | `recipes`, `journal` |
| `14_swarm.bats` | `src/recipes/swarm.sh` | `recipes`, `orchestration` |
| `15_snapshot.bats` | `src/recipes/snapshot.sh` | `recipes`, `snapshot` |
| `16_dashboard.bats` | `src/recipes/dashboard.sh` | `recipes`, `ui` |
| `17_dashboard_refresh.bats` | `src/recipes/dashboard-refresh.sh` | `recipes`, `ui` |
| `18_n8n_start.bats` | `src/recipes/n8n-start.sh` | `recipes`, `docker` |

> `src/recipes/account-swap.sh` and `src/recipes/hygiene.sh` are covered in core BATS (`09_account_swap.bats`, `10_hygiene.bats`). `src/recipes/scheduler-seed.sh` has no dedicated test yet — see [`AGENT_AUDIT_TASKLIST.md`](AGENT_AUDIT_TASKLIST.md).

---

## `python/` — Python Unit Tests

| File | Source Module Covered | Tags |
|------|-----------------------|------|
| `test_accounts.py` | `poller.accounts` | `poller`, `metadata`, `context` |
| `test_adapters.py` | `scheduler.adapters.*` | `scheduler`, `adapters`, `security` |
| `test_alternatives.py` | `poller.alternatives` | `poller`, `suggestions` |
| `test_caps.py` | `poller.caps` | `poller`, `calibration` |
| `test_claude_multi_account.py` | `poller.claude` (multi-account) | `poller`, `claude`, `auth` |
| `test_claude_oauth.py` | `poller.claude_oauth` | `poller`, `claude`, `oauth` |
| `test_codex.py` | `poller.codex` | `poller`, `codex`, `jsonl` |
| `test_codex_oauth.py` | `poller.codex_oauth` | `poller`, `codex`, `oauth` |
| `test_comments.py` | `poller.comments` | `poller`, `commentary` |
| `test_discovery.py` | `poller.discovery` | `poller`, `config` |
| `test_dispatcher.py` | `scheduler.dispatcher` | `scheduler`, `dispatch` |
| `test_gemini.py` | `poller.gemini` | `poller`, `gemini`, `api` |
| `test_integration.py` | poller→widget pipeline | `integration`, `cross-engine` |
| `test_notify.py` | `poller.notify` | `poller`, `macos`, `notifications` |
| `test_pace.py` | `poller.pace` | `poller`, `rate-tracking` |
| `test_poller_main.py` | `poller.main` | `poller`, `entry-point`, `security` |
| `test_queue.py` | `scheduler.queue` | `scheduler`, `yaml`, `flock` |
| `test_routing.py` | `scheduler.routing` (defensive `meter_status`) | `scheduler`, `routing`, `defensive` |
| `test_runtime_config_templates.py` | `common.config` + `config/*.example.json` contract | `config`, `templates`, `contract` |
| `test_scheduler_cli.py` | `scheduler.cli` | `scheduler`, `cli` |
| `test_scheduler_routing.py` | `scheduler.routing` | `scheduler`, `routing`, `meters` |
| `test_security.py` | cross-cutting security | `security`, `hardening`, `audit` |
| `test_value.py` | `poller.value` | `poller`, `economics` |

---

## `e2e/` — End-to-End Widget Tests

| Tier | ID Range | What It Covers |
|------|----------|----------------|
| 1 | T001-T004 | Core output format (SwiftBar separator, icon, pipes) |
| 2 | T010-T014 | Status icon logic (green/yellow/red, staleness) |
| 3 | T020-T024 | Missing dependencies (no jq, no data files) |
| 4 | T030-T038 | Corrupt/malformed data (invalid JSON, nulls, types) |
| 5 | T040-T046 | Boundary/edge cases (0%, 100%, thresholds, skew) |
| 6 | T050-T054 | Section existence |
| 7 | T060-T064 | Stress/performance fixtures, recipes, and concurrency |
| 8 | T070-T072 | Provider error states |
| 9 | T080-T081 | Suggestion engine |
| 10 | T090-T091 | humanize() function |
| 11 | T100-T101 | Action parameters |
| 12 | T110-T112 | Alert rendering |
| 13 | T120-T121 | Output stability/determinism |
| 14 | T130-T132 | Suggestion priorities |
| 15 | T140-T141 | Alternative tool display |
| 16 | T150 | Domain coverage |
| 17 | T160-T161 | Footer rendering |
| 18 | T170-T172 | Live alert verification |
| 19 | T180-T189 | Permissions & environment |
| 20 | T190-T191 | Output size regression |
| 21 | T200-T201 | Recipe edge cases |
| 22 | T210 | Provider source branches |
| 23 | T220 | Ollama edge cases |
| 24 | T230-T231 | Alert layer parsing |
| 25 | T240-T241 | Snapshot age/stale warnings |

---

## `helpers/` — Shared Test Infrastructure

| File | Purpose |
|------|---------|
| `common.bash` | Sandbox `$HOME` setup/teardown, assertion helpers |
| `stubs/claude` | Claude CLI stub |
| `stubs/curl` | curl stub (controllable exit/output) |
| `stubs/gemini` | Gemini CLI stub (configurable output/sleep/exit) |
| `stubs/ollama` | Ollama stub (ps/list/run/stop simulation) |
| `stubs/open` | macOS `open` stub (logs calls) |
| `stubs/osascript` | AppleScript stub |
| `stubs/perplexity` | Perplexity stub |
| `stubs/python3` | Python3 stub |
| `stubs/sysctl` | sysctl stub (deterministic RAM values) |
| `stubs/tavily` | Tavily search stub |
| `stubs/vm_stat` | vm_stat stub (deterministic page counts) |

---

## `fixtures/` — Static Test Data

> Paths are relative to `tests/fixtures/` unless noted.

| File | Used By |
|------|---------|
| `state.json.good` | BATS `common.bash` setup |
| `state.json.malformed` | State parsing error tests |
| `state.json.no_issues` | Clean state tests |
| `config.json.example` | Runtime config template contract tests |
| `jobs.yaml.good` | Scheduler queue load tests |
| `notify.json.good` | Meter-state parsing tests |
| `usage.json.healthy` | Poller/widget usage fixtures |
| `tests/e2e/fixtures/usage_healthy.json` | All E2E tests requiring healthy usage (lives under `tests/e2e/fixtures/`, not `tests/fixtures/`) |
