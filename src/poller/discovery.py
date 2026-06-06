"""Auto-detection of user / paths / plans / accounts.

Replaces every hardcoded `$HOME/...` and `com.eco-commander.*`
in the codebase. Pure stdlib (pwd, os, pathlib, json) so v3 can ship as
public OSS without dragging in toolkit.

This module is the foundation of the OSS-readiness work. NO module here
may import from a tool-specific collector (claude.py, codex.py, gemini.py)
to keep the dependency graph: discovery → collectors, never the reverse.
"""
from __future__ import annotations

import json
import os
import pwd
from pathlib import Path
from typing import TypedDict


class HomePaths(TypedDict):
    home: Path
    eco: Path
    claude: Path
    gemini: Path
    codex: Path


class PlanInfo(TypedDict):
    plan: str
    accounts: int
    source: str  # "api" | "config" | "default"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def detect_user() -> str:
    """Return the Mac short-name (e.g. ``alex``).

    Use this anywhere you'd otherwise parse ``/Users/<name>/`` from a path.
    """
    return pwd.getpwuid(os.getuid()).pw_name


def home_paths() -> HomePaths:
    """All filesystem roots the poller cares about, derived from $HOME."""
    h = Path.home()
    return {
        "home":   h,
        "eco":    h / ".eco",
        "claude": h / ".claude",
        "gemini": h / ".gemini",
        "codex":  h / ".codex",
    }


def detect_accounts(tool: str) -> int:
    """Count distinct OAuth credential files for a tool.

    * ``gemini``: 1 if ``~/.gemini/oauth_creds.json`` exists,
                  + count of ``~/.gemini/accounts/oauth_creds.*.json``
    * ``codex``:  1 if ``~/.codex/auth.json`` exists, else 0
    * ``claude``: not enumerable from disk (Keychain). Defaults to 0; user can
                  opt into a local count in ``~/.eco/config.json``.

    Unknown tool → 0.
    """
    h = Path.home()
    if tool == "gemini":
        n = 1 if (h / ".gemini" / "oauth_creds.json").exists() else 0
        accounts_dir = h / ".gemini" / "accounts"
        if accounts_dir.exists():
            n += len(list(accounts_dir.glob("oauth_creds.*.json")))
        return n
    if tool == "codex":
        return 1 if (h / ".codex" / "auth.json").exists() else 0
    if tool == "claude":
        cfg = _load_config()
        return _coerce_account_count(_tool_config(cfg, "claude").get("accounts", 0))
    return 0


def detect_plans() -> dict[str, PlanInfo]:
    """Return per-tool plan info.

    Today: reads ``~/.eco/config.json`` overrides; falls back to defaults.
    Future: when server-truth is on, reads plan tier from API responses
    (Anthropic ``/api/oauth/usage`` includes ``tier``; Gemini ``loadCodeAssist``
    includes ``currentTier.id``). Out of scope for this module; collectors
    write the API-derived plan into ``usage.json`` directly.
    """
    cfg = _load_config()
    plans: dict[str, PlanInfo] = {}
    for tool in ("claude", "gemini", "codex"):
        tool_cfg = _tool_config(cfg, tool)
        plan_name = tool_cfg.get("plan") or _default_plan(tool)
        plans[tool] = {
            "plan":     str(plan_name),
            "accounts": detect_accounts(tool),
            "source":   "config" if tool_cfg.get("plan") else "default",
        }
    return plans


def server_truth_enabled(tool: str) -> bool:
    """True iff the user has flipped the per-tool ``more access`` toggle.

    Read from ``~/.eco/config.json:server_truth.<tool>`` (default False).
    Default-off keeps OSS install silent — no Keychain prompts on first run.
    """
    cfg = _load_config()
    flag = cfg.get("server_truth", {})
    if not isinstance(flag, dict):
        return False
    return bool(flag.get(tool, False))


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


def _config_path() -> Path:
    try:
        from common.config import EcoConfig
        return EcoConfig.from_env().config_path
    except ImportError:
        return Path(os.environ.get("ECO_HOME", Path.home() / ".eco")) / "config.json"


def _load_config() -> dict:
    p = _config_path()
    if not p.exists():
        return {}
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _tool_config(cfg: dict, tool: str) -> dict:
    raw = cfg.get(tool, {}) if isinstance(cfg, dict) else {}
    return raw if isinstance(raw, dict) else {}


def _coerce_account_count(value: object) -> int:
    try:
        return max(int(value), 0)
    except (TypeError, ValueError):
        return 0


_DEFAULTS = {
    "claude": "Unknown",
    "gemini": "Unknown",
    "codex":  "Unknown",
}


def _default_plan(tool: str) -> str:
    return _DEFAULTS.get(tool, "Unknown")
