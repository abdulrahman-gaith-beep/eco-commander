# Poller Package Manifest

> **Package**: `src/poller/` · **Language**: Python 3.10+ · **Version**: unset (see F7)
> **Entry point**: `python -m poller.main` or `python src/poller/main.py`

## Module Dependency DAG (topological order)

```
caps.py          ← leaf (no imports)
pace.py          ← leaf (no imports, mirrors caps constants)
time_utils.py    ← leaf (stdlib only)
discovery.py     ← leaf (stdlib only)
accounts.py      ← leaf (stdlib only)
alternatives.py  ← leaf (stdlib + shutil/subprocess)
value.py         ← leaf (no imports from package)
comments.py      ← leaf (stdlib only)
claude.py        ← caps, pace
codex.py         ← caps, pace
gemini.py        ← pace
claude_oauth.py  ← pace
codex_oauth.py   ← caps, pace
notify.py        ← pace
main.py          ← ALL above modules
py.typed         ← (PEP 561 marker, not a module)
```

## Public API Surface

| Module | Function | Returns | Side Effects |
|---|---|---|---|
| `main.py` | `main()` | `int` (exit code) | Writes `~/.eco/current/usage*.json`, fires notifications |
| `claude.py` | `collect()` | `dict` | Reads `~/.claude/projects/**/*.jsonl` |
| `claude.py` | `collect_multi()` | `dict` | Same + per-account enumeration |
| `gemini.py` | `collect()` | `dict` | HTTP calls to Google APIs, refreshes OAuth token |
| `codex.py` | `collect()` | `dict` | Reads `~/.codex/sessions/**/*.jsonl` |
| `claude_oauth.py` | `collect()` | `dict` | Reads macOS Keychain, HTTP to Anthropic API |
| `codex_oauth.py` | `collect()` | `dict` | Reads `~/.codex/auth.json`, HTTP to OpenAI API |
| `notify.py` | `evaluate(merged)` | `dict` | May fire macOS notifications, writes `notify.json` |
| `value.py` | `compute(merged)` | `dict` | Pure function — no side effects |
| `discovery.py` | `detect_user()` | `str` | Pure |
| `discovery.py` | `home_paths()` | `HomePaths` | Pure |
| `discovery.py` | `detect_accounts(tool)` | `int` | Filesystem probe |
| `discovery.py` | `detect_plans()` | `dict` | Reads `~/.eco/config.json` |
| `discovery.py` | `server_truth_enabled(tool)` | `bool` | Reads `~/.eco/config.json` |
| `accounts.py` | `stamp(payload, tool)` | `dict` | Pure (mutates payload in-place) |
| `alternatives.py` | `collect()` | `dict` | Runs `ollama list` subprocess |
| `comments.py` | `evaluate(merged, prev, state)` | `str\|None` | Mutates `state` in-place |
| `time_utils.py` | `parse_iso_to_epoch(ts)` | `float\|None` | Pure |
| `time_utils.py` | `format_resets_in(seconds)` | `str` | Pure |
| `time_utils.py` | `resolve_dotpath(data, key)` | `dict\|None` | Pure |

## Output Schema (`usage.json`)

```json
{
  "ts": 1716000000,
  "duration_ms": 350,
  "version": 1,
  "claude": { "tool": "claude", "ok": true, "source": "jsonl|api",
              "session": {"pct": 45.2, "tokens": 10000000, ...},
              "weekly":  {"pct": 72.1, "tokens": 48000000, ...},
              "per_account": [...] },
  "gemini": { "tool": "gemini", "ok": true, "source": "api",
              "tiers": {"flash": {...}, "flash_lite": {...}, "pro": {...}},
              "per_account": [...] },
  "codex":  { "tool": "codex", "ok": true, "source": "jsonl|api",
              "session": {"pct": 15.0, ...}, "weekly": {"pct": 30.0, ...} },
  "alternatives": { "antigravity": {...}, "cursor": {...}, "ollama": {...} },
  "value":  { "total_usd_7d": 0.0, "by_tool": {"claude": "no data"}, ... }
}
```

## Calibration Constants (caps.py)

| Constant | Value | Last Calibrated | Notes |
|---|---|---|---|
| `CLAUDE_MAX20X_5H_TOKENS` | 1 | public neutral default | Back-compat alias for `CLAUDE_DEFAULT_5H_TOKENS` |
| `CLAUDE_MAX20X_7D_ALL_TOKENS` | 1 | public neutral default | Back-compat alias for `CLAUDE_DEFAULT_7D_ALL_TOKENS` |
| `CLAUDE_MAX20X_7D_SONNET_TOKENS` | 1 | public neutral default | Back-compat alias for `CLAUDE_DEFAULT_7D_SONNET_TOKENS` |
| `CACHE_READ_WEIGHT` | 0.00 | 2026-05-10 | Anthropic: "cache reads don't count" |
| `CODEX_PRO_SESSION_TOKENS` | 1 | public neutral default | Back-compat alias for `CODEX_DEFAULT_SESSION_TOKENS` |
| `CODEX_PRO_WEEKLY_TOKENS` | 1 | public neutral default | Back-compat alias for `CODEX_DEFAULT_WEEKLY_TOKENS` |

## Test Coverage

| Module | Test File | Coverage |
|---|---|---|
| `accounts.py` | `tests/python/test_accounts.py` | ✅ |
| `alternatives.py` | `tests/python/test_alternatives.py` | ✅ |
| `caps.py` | `tests/python/test_caps.py` | ✅ |
| `claude.py` | `tests/python/test_claude_multi_account.py` | ✅ |
| `claude_oauth.py` | `tests/python/test_claude_oauth.py` | ✅ |
| `codex.py` | `tests/python/test_codex.py` | ✅ |
| `codex_oauth.py` | `tests/python/test_codex_oauth.py` | ✅ |
| `comments.py` | `tests/python/test_comments.py` | ✅ |
| `discovery.py` | `tests/python/test_discovery.py` | ✅ |
| `gemini.py` | `tests/python/test_gemini.py` | ✅ |
| `main.py` | `tests/python/test_poller_main.py` | ✅ |
| `notify.py` | `tests/python/test_notify.py` | ✅ |
| `pace.py` | `tests/python/test_pace.py` | ✅ |
| `value.py` | `tests/python/test_value.py` | ✅ |

## Known Issues

- No publish-blocking poller issues are tracked in this manifest. Treat source
  and tests as authoritative when this summary drifts.
