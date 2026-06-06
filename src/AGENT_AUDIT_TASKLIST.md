# AI Agent Audit Tasklist — `src/` Directory

> Generated: 2026-05-22 · For use by AI agents auditing eco-commander source code.
> **Navigation**: Start at [AI_NAV.md](./AI_NAV.md) for file registry and dependency graph.

---

## How to Use This Tasklist

Each task below has a **scope**, **files to inspect**, **what to check**, and **acceptance criteria**. An AI agent should:
1. Read the relevant `MANIFEST.md` for the subsystem
2. Read the specific files listed
3. Apply the checks
4. Report findings as a structured markdown table

---

## Tier 1 — Critical Audit Tasks

### T1.1: Token Cap Calibration Verification
- **Scope**: `poller/caps.py`
- **Files**: [caps.py](./poller/caps.py), [claude.py](./poller/claude.py), [codex.py](./poller/codex.py)
- **Check**: Compare calibrated cap constants against the latest vendor-published or screenshot-derived values. Verify `CACHE_READ_WEIGHT = 0.00` matches current Anthropic rate-limit policy.
- **Accept**: Report with `CURRENT_VALUE | EXPECTED_VALUE | DRIFT` table.

### T1.2: Security — No Token Leakage in Output
- **Scope**: All poller collectors and scheduler adapters
- **Files**: All files in `poller/`, `scheduler/adapters/`
- **Check**: Verify no code path can write OAuth tokens, API keys, or bearer headers to `usage.json`, scheduler logs, or notification text. Check all `except` blocks use `_safe_collect` / `exception_note` / `sanitize_note`.
- **Accept**: "No leakage paths found" or table of findings.

### T1.3: Privacy Surface Validation
- **Scope**: `scheduler/queue.py` — `validate_workdir()`
- **Files**: [queue.py](./scheduler/queue.py)
- **Check**: Verify the blocked paths list matches the user's absolute prohibition list. Verify symlink traversal can't bypass the check.
- **Accept**: Blocklist matches user rules; symlink escape tested.

### T1.4: Atomic Write Correctness
- **Scope**: All `_atomic_write` / `tempfile + os.replace` patterns
- **Files**: [main.py](./poller/main.py), [queue.py](./scheduler/queue.py), [notify.py](./poller/notify.py), [gemini.py](./poller/gemini.py)
- **Check**: Verify every atomic write: (1) creates temp in same dir, (2) uses `os.replace`, (3) sets restrictive permissions, (4) cleans up temp on exception.
- **Accept**: All 4 checks pass for each write site.

---

## Tier 2 — Enhancement Audit Tasks

### T2.1: Test Coverage Gap Analysis
- **Scope**: All Python modules vs `tests/python/`
- **Files**: All `src/poller/*.py`, `src/scheduler/*.py`, `tests/python/*.py`
- **Check**: For each source module, identify whether a corresponding test file exists. List untested public functions.
- **Accept**: Coverage matrix with `MODULE | TEST_FILE | FUNCTIONS_TESTED | FUNCTIONS_MISSING`.

### T2.2: Docstring Completeness
- **Scope**: All Python modules
- **Files**: All `.py` files in `src/`
- **Check**: Every public function/class has a docstring. Type annotations are present. Return types documented.
- **Accept**: `MODULE | TOTAL_PUBLIC | DOCUMENTED | TYPED | SCORE%` table.

### T2.3: Error Handling Consistency
- **Scope**: All adapter `.fire()` methods
- **Files**: [codex.py](./scheduler/adapters/codex.py), [gemini.py](./scheduler/adapters/gemini.py), [claude.py](./scheduler/adapters/claude.py), [ollama.py](./scheduler/adapters/ollama.py)
- **Check**: Every adapter: (1) handles `FileNotFoundError`, (2) handles `TimeoutExpired`, (3) uses `_kill_tree`, (4) calls `redact_log_file`, (5) classifies error_kind from stderr.
- **Accept**: 5-check matrix per adapter, all green.

### T2.4: Recipe Header Compliance
- **Scope**: All recipes in `src/recipes/`
- **Files**: All `.sh` files in `src/recipes/`
- **Check**: Every recipe has `# DESC:` header. Missing `# INPUTS:`, `# OUTPUT:`, `# USES:`, `# HUMAN:` are flagged.
- **Accept**: Compliance table per [recipes/MANIFEST.md](./recipes/MANIFEST.md).

### T2.5: Shell Script Quality
- **Scope**: All shell scripts in `src/bin/` and `src/recipes/`
- **Files**: All `.sh` files
- **Check**: Run `shellcheck` equivalent analysis. Check for: `set -u`/`set -e` guards, quoted variables, proper error handling, no hardcoded paths that should use `$HOME` or discovery.
- **Accept**: Per-script findings with severity.

---

## Tier 3 — Structural Improvement Tasks

### T3.1: Import Standardization
- **Scope**: `poller/main.py`
- **Files**: [main.py](./poller/main.py)
- **Check**: The dual import path (`if __package__` block at L27-37) is fragile. Propose a standardization.
- **Accept**: Recommendation with rationale.

### T3.2: URL Validity Check
- **Scope**: `poller/accounts.py`
- **Files**: [accounts.py](./poller/accounts.py)
- **Check**: All hardcoded URLs (Google, OpenAI help pages) return HTTP 200.
- **Accept**: URL | STATUS table.

### T3.3: Deprecated Code Removal
- **Scope**: All collectors
- **Files**: All `poller/*.py`
- **Check**: Search for `# TODO`, `# FIXME`, `# HACK`, `# XXX`, deprecated shims, and `Remove after` comments.
- **Accept**: List of actionable items with file:line references.

### T3.4: Configuration Externalization
- **Scope**: Hardcoded values that should be in `~/.eco/config.json`
- **Files**: [gemini.py](./poller/gemini.py) (client_id/secret), [value.py](./poller/value.py) (`ECO_VALUE_MODEL_JSON`), [accounts.py](./poller/accounts.py) (account inventory)
- **Check**: Identify all hardcoded values that change when the user's setup changes.
- **Accept**: `VALUE | FILE | RECOMMENDATION` table.

---

## Tier 4 — Performance & Observability

### T4.1: Poller Cycle Time Profiling
- **Scope**: `poller/main.py`
- **Check**: Profile the hot path. Which collectors are slowest? Are HTTP timeouts (8s each) sequential or could they be parallelized?
- **Accept**: Timing breakdown per collector.

### T4.2: Scheduler Tick Efficiency
- **Scope**: `scheduler/dispatcher.py`
- **Check**: Does the tick hold the lock for the entire fire duration? Should it release between jobs?
- **Accept**: Lock holding analysis with recommendation.

### T4.3: Log Rotation
- **Scope**: `~/.eco/logs/poller.log`
- **Check**: Does the log grow unboundedly? Is log rotation configured?
- **Accept**: Size analysis + rotation recommendation.
