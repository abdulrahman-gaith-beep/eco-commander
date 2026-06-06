"""Configured account and subscription context for usage payloads.

Shipped defaults are intentionally neutral. Users may opt into local metadata
by creating ``$ECO_HOME/accounts.json``; runtime collectors still own live usage
meters and this module never reads credential files.
"""
from __future__ import annotations

import json
import os
from copy import deepcopy
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

_KNOWN_TOOLS = ("claude", "gemini", "codex")
_NEUTRAL_CONTEXT: dict[str, Any] = {
    "plan": "Unknown",
    "configured_accounts": 0,
    "account_inventory": [],
}

_CONTEXT: dict[str, dict[str, Any]] = {
    tool: deepcopy(_NEUTRAL_CONTEXT) for tool in _KNOWN_TOOLS
}

_OVERRIDE_LIST_KEYS = {"account_inventory", "plan_aliases", "plan_events"}


def _accounts_config_path() -> Path:
    """Return the optional local account metadata path under ECO_HOME."""
    try:
        from common.config import EcoConfig

        return EcoConfig.from_env().eco_home / "accounts.json"
    except ImportError:
        return Path(os.environ.get("ECO_HOME", str(Path.home() / ".eco"))) / "accounts.json"


def _load_local_context() -> dict[str, dict[str, Any]]:
    path = _accounts_config_path()
    if not path.exists():
        return {}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(raw, dict):
        return {}
    tools = raw.get("tools", raw)
    if not isinstance(tools, dict):
        return {}
    return {
        str(tool): data
        for tool, data in tools.items()
        if isinstance(tool, str) and isinstance(data, dict)
    }


def _coerce_configured_accounts(value: Any, *, fallback: int = 0) -> int:
    try:
        count = int(value)
    except (TypeError, ValueError):
        return fallback
    return max(count, 0)


def _merge_context(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    ctx = deepcopy(base)
    if "plan" in override:
        ctx["plan"] = str(override.get("plan") or "Unknown")
    if "configured_accounts" in override:
        ctx["configured_accounts"] = _coerce_configured_accounts(
            override.get("configured_accounts"),
            fallback=_coerce_configured_accounts(ctx.get("configured_accounts")),
        )
    for key in _OVERRIDE_LIST_KEYS:
        if key in override and isinstance(override[key], list):
            ctx[key] = deepcopy(override[key])
    return ctx


def _days_until(value: str, today: date | None = None) -> int | None:
    try:
        target = date.fromisoformat(value)
    except (TypeError, ValueError):
        return None
    base = today or datetime.now(timezone.utc).date()
    return (target - base).days


def tool_context(tool: str, *, today: date | None = None) -> dict[str, Any]:
    """Return a deep-copied context block for ``tool``.

    Adds ``days_until`` to dated plan events so the widget and scheduler can
    warn without reimplementing calendar math.
    """
    tool_key = str(tool)
    ctx = deepcopy(_CONTEXT.get(tool_key, _NEUTRAL_CONTEXT))
    override = _load_local_context().get(tool_key)
    if override:
        ctx = _merge_context(ctx, override)
    for event in ctx.get("plan_events", []):
        if not isinstance(event, dict):
            continue
        days = _days_until(event.get("effective_date", ""), today=today)
        if days is not None:
            event["days_until"] = days
            event["expired"] = days < 0
            event["imminent"] = 0 <= days <= 14
    return ctx


def stamp(payload: dict[str, Any], tool: str | None = None) -> dict[str, Any]:
    """Attach configured context while preserving collector-provided detail."""
    if not isinstance(payload, dict):
        return payload
    tool_key = tool or str(payload.get("tool", ""))
    ctx = tool_context(tool_key)
    detected_present = "accounts" in payload
    detected = payload.get("accounts")
    configured = _coerce_configured_accounts(ctx.get("configured_accounts"))
    if configured and detected_present and detected is not None and detected != configured:
        payload.setdefault("detected_accounts", detected)
    payload["configured_accounts"] = configured
    if not detected_present:
        payload["accounts"] = configured
    payload.setdefault("plan", ctx.get("plan") or "Unknown")
    if ctx.get("plan_aliases"):
        payload["plan_aliases"] = ctx["plan_aliases"]
    payload["account_inventory"] = ctx.get("account_inventory", [])
    if ctx.get("plan_events"):
        payload["plan_events"] = ctx["plan_events"]
    return payload
