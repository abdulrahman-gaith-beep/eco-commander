# Agent Audit Tasklist — Tests Directory

> **Purpose**: Structured improvement tasks for AI agents to enhance the eco-commander test suite.
> Each task is tagged with priority, estimated complexity, and the agent role best suited for it.
>
> **Last audited**: 2026-06-06 · **756 tests across 3 engines** (302 BATS · 369 Python · 85 E2E)

---

## Legend

| Tag | Meaning |
|-----|---------|
| 🔴 P0 | Critical — blocks quality confidence |
| 🟡 P1 | High — significant improvement |
| 🟢 P2 | Medium — nice to have |
| 🔵 P3 | Low — polish |
| `[S]` | Small (< 1 hour) |
| `[M]` | Medium (1-3 hours) |
| `[L]` | Large (3+ hours) |

---

## 🔴 P0 — Critical Coverage Gaps

### ~~T-001: Create `test_accounts.py` for `src/poller/accounts.py`~~ ✅ DONE
- **Agent**: Coverage Hunter 🎯
- **Effort**: `[M]`
- **Result**: Created `test_accounts.py` with 33 tests covering `_days_until`, `tool_context`, `stamp`, and data integrity.
- **What to test**:
  - Account registration and storage
  - Account listing and enumeration
  - Active account tracking
  - Edge cases: duplicate slugs, invalid characters, missing dirs
  - File permission enforcement (0o600 for auth files)

### ~~T-002: Expand `test_codex.py` — only 3 tests for 8.4KB module~~ ✅ DONE
- **Agent**: Coverage Hunter 🎯
- **Effort**: `[M]`
- **Result**: Expanded from 3 to 13 tests. Added: empty files, malformed lines, multi-session aggregation, subdirectory discovery, overflow protection, output shape validation, error shape validation.
- **Missing tests**:
  - Empty JSONL session file
  - Corrupted/malformed JSONL lines
  - Multiple concurrent sessions
  - Timezone edge cases
  - Very large token counts (overflow protection)
  - Session with only cached/reasoning tokens

### T-003: Expand `test_claude_multi_account.py` — 10 tests for the 15.6KB `src/poller/claude.py` multi-account path
- **Agent**: Coverage Hunter 🎯
- **Effort**: `[L]`
- **Current**: 10 tests
- **Missing tests**:
  - JSONL parsing edge cases (malformed lines, empty files)
  - Token counting accuracy under different plans
  - Multi-org account configurations
  - Rate limit detection and reporting
  - Session boundary detection
  - Error recovery when JSONL is partially written

---

## 🟡 P1 — High Priority Improvements

### ~~T-010: Create BATS tests for `src/bin/ai-clear.sh`~~ ✅ DONE
- **Agent**: Coverage Hunter 🎯
- **Effort**: `[S]`
- **Result**: Created `11_ai_clear.bats` with 7 tests covering: unload, embedding preservation, Ollama down, missing curl, custom URL, empty models, malformed JSON.
- **What to test**:
  - Ollama unload behavior
  - Zombie process detection and killing
  - Dry-run mode
  - Error when no processes found

### T-011: Deepen `06_eco_alerts.bats` — 18 tests for 35KB script
- **Agent**: Coverage Hunter 🎯
- **Effort**: `[M]`
- **Current**: 18 tests for a 35KB script
- **Missing areas**:
  - `debug-ollama` subcommand edge cases
  - `delegate-fix` flow
  - Alert escalation logic
  - Concurrent alert processing
  - Alert deduplication

### T-012: Expand integration tests (`test_integration.py`)
- **Agent**: Coverage Hunter 🎯
- **Effort**: `[M]`
- **Current**: Only 4 tests for the critical poller→widget pipeline
- **Missing tests**:
  - Partial provider data (only Claude ok, others error)
  - Schema version mismatch handling
  - Widget CLI vs SwiftBar mode differences
  - Large usage.json (many accounts)

### T-013: Expand Gemini poller tests — 15 tests for 16.4KB
- **Agent**: Coverage Hunter 🎯
- **Effort**: `[M]`
- **Missing tests**:
  - Multi-account scenarios
  - API error response handling
  - Rate limit tier calculation
  - Stale cache detection
  - Malformed API response

### T-014: Expand value computation tests — 6 tests for 10.6KB
- **Agent**: Coverage Hunter 🎯
- **Effort**: `[S]`
- **Missing tests**:
  - Zero-value edge cases
  - Negative value handling
  - Very large value overflow
  - Missing required fields

### T-015: Expand notify tests — 12 tests for 11.7KB
- **Agent**: Coverage Hunter 🎯
- **Effort**: `[S]`
- **Missing tests**:
  - Notification suppression rules
  - Cooldown timer logic
  - macOS notification permission denied
  - Meter state transitions

---

## 🟢 P2 — Structural & Infrastructure

### T-020: Split E2E monolith into per-tier modules
- **Agent**: Infrastructure Modernizer ⚙️
- **Effort**: `[L]`
- **Problem**: `run_e2e.sh` is 1,703 lines / 64KB — largest single file
- **Proposal**: Extract harness functions into `e2e/lib/harness.sh`, then split test tiers into `e2e/tiers/tier_01_core.sh` through `e2e/tiers/tier_25_stale.sh`
- **Risk**: High — need to preserve all 85 tests exactly

### T-021: Add coverage measurement
- **Agent**: Infrastructure Modernizer ⚙️
- **Effort**: `[M]`
- **What**:
  - Add `coverage.py` to `requirements-dev.txt`
  - Add `make test-coverage` target
  - Generate HTML coverage report
  - Set coverage threshold (target: 80%+)

### T-022: Consolidate fixtures
- **Agent**: Structural Auditor 🏗️
- **Effort**: `[S]`
- **Problem**: Fixtures split between `tests/fixtures/` and `tests/e2e/fixtures/`
- **What**: Document the split rationale or consolidate into one location
- **Consideration**: BATS fixtures use `tests/fixtures/`, E2E has its own — may be intentional for isolation

### T-023: Verify `08_installers.bats` covers `install-commander.sh`
- **Agent**: Quality Auditor 🔒
- **Effort**: `[S]`
- **What**: Check if the 13 installer tests actually exercise `src/bin/install-commander.sh` or only `scripts/install.sh`

### T-024: Add snapshot.sh deeper testing
- **Agent**: Coverage Hunter 🎯
- **Effort**: `[M]`
- **Current**: 9 tests for 15KB
- **Missing**: Error paths, disk-full simulation, concurrent snapshots, snapshot ID format validation

### T-025: Add hygiene.sh deeper testing
- **Agent**: Coverage Hunter 🎯
- **Effort**: `[M]`
- **Current**: 9 tests for 13KB
- **Missing**: All subcommands exercised, launchd plist validation, RAM threshold edge cases

---

## 🔵 P3 — Polish & Quality

### T-030: Audit stub usage — find orphans
- **Agent**: Quality Auditor 🔒
- **Effort**: `[S]`
- **What**: For each of the 11 stubs, verify at least 1 test uses it
- **Stubs to check**: claude, curl, gemini, ollama, open, osascript, perplexity, python3, sysctl, tavily, vm_stat
- **Action**: Remove unused stubs or document why they exist

### T-031: Audit for timing-dependent flakiness
- **Agent**: Quality Auditor 🔒
- **Effort**: `[M]`
- **What**: Find tests that depend on wall-clock time or sleeps
- **Known risks**:
  - `T013` uses `touch -t $(date -v-4d ...)` — macOS-specific
  - `T014` uses stale timestamp (300s ago) — could flake at day boundary
  - `T063` measures elapsed time with 1-second granularity
  - `T045` future timestamp assumes clock accuracy
  - Concurrent tests (T064) depend on process scheduling

### T-032: Verify sandbox isolation completeness
- **Agent**: Quality Auditor 🔒
- **Effort**: `[S]`
- **What**: Grep for hardcoded paths in tests that might leak outside sandbox
- **Forbidden patterns**: `$HOME/`, `$ORIG_HOME` outside common.bash, any real `~/.eco`

### T-033: Add test for `conftest.py` path setup
- **Agent**: Infrastructure Modernizer ⚙️
- **Effort**: `[S]`
- **What**: A meta-test that verifies `conftest.py`'s path setup works and all imports resolve

### T-034: Standardize Python test boilerplate
- **Agent**: Infrastructure Modernizer ⚙️
- **Effort**: `[M]`
- **What**: Migrate existing test files to use `conftest.py` imports instead of inline `sys.path.insert`
- **Scope**: All 20 test files
- **Note**: Non-breaking — old pattern still works, this is cleanup

### T-035: Add test runner CI integration docs
- **Agent**: Indexer 🗂️
- **Effort**: `[S]`
- **What**: Document which CI workflows run which test engines, and how to debug CI failures

### T-036: Performance regression baseline
- **Agent**: Quality Auditor 🔒
- **Effort**: `[M]`
- **What**: Run full suite 3x, record timing baseline, add to CI as perf regression check
- **Current**: Only T063 checks widget <5s. No overall suite timing tracked.

### T-037: Review E2E report accumulation
- **Agent**: Structural Auditor 🏗️
- **Effort**: `[S]`
- **What**: Keep ignored `tests/e2e/results/` reports out of commits and clean any accidental artifacts before release.

---

## Agent Assignment Summary

| Agent | Role | Tasks | Priority Range |
|-------|------|-------|----------------|
| 🗂️ Indexer & Navigator | Indexing, documentation, cross-refs | T-035 | P3 |
| 🏗️ Structural Auditor | Naming, dead code, fixture consolidation | T-022, T-037 | P2-P3 |
| 🎯 Coverage Hunter | Missing tests, edge cases, depth | T-001 through T-015, T-024, T-025 | P0-P1 |
| ⚙️ Infrastructure Modernizer | Tooling, DX, CI integration | T-020, T-021, T-033, T-034 | P2-P3 |
| 🔒 Quality & Security Auditor | Flakiness, isolation, security | T-023, T-030 through T-032, T-036 | P2-P3 |
