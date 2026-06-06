"""Server-truth Claude collector — opt-in via discovery.server_truth_enabled('claude').

Reads OAuth bearer from macOS Keychain entry "Claude Code-credentials" via
the system's `security` binary. Claude Code stores either a raw bearer token
or a JSON credentials blob; only the access token may be sent as Bearer.
Calls GET /api/oauth/usage. Returns the same output shape as src/poller/claude.py
so main.py can swap collectors freely.

Security (P0/P1 from W3 brutal auditor):
- NEVER log the bearer token
- Use Anthropic's User-Agent header (eco-commander/3.0) + anthropic-beta header
- Catch ssl.SSLError specifically — its __str__ may contain the URL
- All exception paths return generic {"ok": false} — no detail in the JSON
- Subprocess timeout=3 on the security command
- HTTP timeout 8s
"""
from __future__ import annotations

import json
import logging
import ssl
import subprocess
import time
import urllib.error
import urllib.request
from typing import Any

from . import pace as _pace_mod
from .time_utils import format_resets_in as _format_resets_in
from .time_utils import parse_iso_to_epoch as _parse_iso_to_epoch

logger = logging.getLogger("eco.poller.claude_oauth")

ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
KEYCHAIN_SERVICE = "Claude Code-credentials"
USER_AGENT = "eco-commander/3.0"
ANTHROPIC_BETA = "oauth-2025-04-20"
HTTP_TIMEOUT = 8
MIN_RAW_TOKEN_LEN = 12
MAX_RAW_TOKEN_LEN = 4096


def _clean_token(value: str) -> str | None:
    token = value.strip()
    if not (MIN_RAW_TOKEN_LEN <= len(token) <= MAX_RAW_TOKEN_LEN):
        return None
    if any(ch.isspace() or ord(ch) < 32 for ch in token):
        return None
    return token

def _extract_access_token(raw: str) -> str | None:
    """Extract an OAuth access token from raw or JSON keychain payloads."""
    value = raw.strip()
    if not value:
        return None
    if not value.startswith("{"):
        return _clean_token(value)
    try:
        data = json.loads(value)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None

    nested = data.get("claudeAiOauth")
    if isinstance(nested, dict):
        token = nested.get("accessToken")
        if isinstance(token, str) and token.strip():
            return _clean_token(token)

    token = data.get("accessToken")
    if isinstance(token, str) and token.strip():
        return _clean_token(token)
    return None

def _read_keychain_token() -> str | None:
    """Read the OAuth bearer from macOS Keychain. Never logs the token."""
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=3, check=False,
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    if result.returncode != 0:
        return None
    return _extract_access_token(result.stdout)
def _meter_reset_at(meter: dict[str, Any]) -> str:
    """Anthropic examples have used both reset_at and resets_at."""
    value = meter.get("resets_at") or meter.get("reset_at") or ""
    return value if isinstance(value, str) else ""

def _utilization_pct(value: Any) -> float:
    """Read utilization from /api/oauth/usage. Returns 0-100 percentage.

    Anthropic returns utilization already on a 0-100 scale: e.g. ``1.0`` means
    1% (matches Claude Code's /usage view). An earlier 0-1-vs-0-100 heuristic
    here inflated every sub-1% reading to 100% — removed.
    """
    try:
        pct = float(value or 0)
    except (TypeError, ValueError):
        return 0.0
    if pct < 0:
        return 0.0
    return pct

def _meter(data: dict[str, Any], key: str) -> dict[str, Any]:
    value = data.get(key) or {}
    return value if isinstance(value, dict) else {}

def collect() -> dict[str, Any]:
    """Single entry. Returns {"ok": false} on any failure — never raises."""
    token = _read_keychain_token()
    if not token:
        return {"tool": "claude", "ok": False, "source": "api", "fallback": "jsonl",
                "error": "no_keychain_token"}

    req = urllib.request.Request(
        ENDPOINT,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": ANTHROPIC_BETA,
            "User-Agent": USER_AGENT,
        },
        method="GET",
    )

    now = time.time()
    try:
        with urllib.request.urlopen(
            req,
            timeout=HTTP_TIMEOUT,
            context=ssl.create_default_context(),
        ) as resp:
            body = resp.read().decode("utf-8")
        data = json.loads(body)
    except urllib.error.HTTPError as exc:
        return {"tool": "claude", "ok": False, "source": "api", "fallback": "jsonl",
                "error": f"http_{exc.code}"}
    except ssl.SSLError:
        # P1.3 — TLS errors may contain the URL in their __str__; suppress detail.
        return {"tool": "claude", "ok": False, "source": "api", "fallback": "jsonl",
                "error": "tls_failure"}
    except (urllib.error.URLError, json.JSONDecodeError, OSError):
        return {"tool": "claude", "ok": False, "source": "api", "fallback": "jsonl",
                "error": "network"}
    if not isinstance(data, dict):
        return {"tool": "claude", "ok": False, "source": "api", "fallback": "jsonl",
                "error": "schema"}

    # Parse the three meters.
    five_h = _meter(data, "five_hour")
    seven_d = _meter(data, "seven_day")
    seven_d_son = _meter(data, "seven_day_sonnet")

    sess_pct = _utilization_pct(five_h.get("utilization", 0))
    week_pct = _utilization_pct(seven_d.get("utilization", 0))
    sonnet_pct = _utilization_pct(seven_d_son.get("utilization", 0))

    sess_reset = _parse_iso_to_epoch(_meter_reset_at(five_h))
    week_reset = _parse_iso_to_epoch(_meter_reset_at(seven_d))

    sess_resets_in = _format_resets_in((sess_reset or now) - now) if sess_reset else "—"
    week_resets_in = _format_resets_in((week_reset or now) - now) if week_reset else "—"

    # Build pace blocks via shared pace.py.
    sess_block = _pace_mod.build_pace_fields(
        sess_pct, sess_reset - 5*3600 if sess_reset else 0, sess_reset or 0, now,
    ) if sess_reset else {"target_pct": 0, "pace_delta_pp": 0, "pace_label": "idle", "pace_glyph": "💤", "reset_epoch": 0}
    week_block = _pace_mod.build_pace_fields(
        max(week_pct, sonnet_pct),
        week_reset - 7*24*3600 if week_reset else 0, week_reset or 0, now,
    ) if week_reset else {"target_pct": 0, "pace_delta_pp": 0, "pace_label": "idle", "pace_glyph": "💤", "reset_epoch": 0}

    return {
        "tool": "claude",
        "ok": True,
        "source": "api",
        "session": {
            "pct": round(sess_pct, 1),
            "resets_in": sess_resets_in,
            **sess_block,
        },
        "weekly": {
            "pct": round(max(week_pct, sonnet_pct), 1),
            "pct_all": round(week_pct, 1),
            "pct_sonnet": round(sonnet_pct, 1),
            "resets_in": week_resets_in,
            **week_block,
        },
    }
