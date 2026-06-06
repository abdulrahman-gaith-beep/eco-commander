"""
Codex server-truth usage source via OpenAI backend API.

Mirror of claude_oauth.py pattern:
- Auth: access_token from ~/.codex/auth.json (no Keychain required).
- Endpoint: GET https://api.openai.com/backend-api/wham/usage
- UA: Uses an OpenAI-Codex CLI compatible user agent.
- Response: 100 - remaining_percentage = used_pct.

Use with caution: this endpoint is only used when server-truth polling is
explicitly enabled.
"""
from __future__ import annotations

import json
import ssl
import time
import urllib.error
import urllib.request
from pathlib import Path

from . import caps
from . import pace as _pace_mod
from .time_utils import format_resets_in as _format_resets_in

CODEX_DIR = Path.home() / ".codex"
AUTH_PATH = CODEX_DIR / "auth.json"
ENDPOINT = "https://chatgpt.com/backend-api/wham/usage"
USER_AGENT = "OpenAI-Codex/0.124.0"
REQUEST_TIMEOUT = 5


def _read_auth_data() -> tuple[str | None, str | None]:
    """Read access_token and account_id from ~/.codex/auth.json. File is user-RW-only."""
    p = AUTH_PATH
    if not p.exists():
        return None, None
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None, None
    tokens = d.get("tokens") or {}
    token = tokens.get("access_token") if isinstance(tokens, dict) else None
    token = token if isinstance(token, str) and token else None

    account_id = d.get("account_id")
    if not account_id and isinstance(tokens, dict):
        account_id = tokens.get("account_id")
    account_id = account_id if isinstance(account_id, str) and account_id else None

    return token, account_id
def collect() -> dict:
    """Fetch usage truth from OpenAI. Never raises; returns ok=False on error."""
    token, account_id = _read_auth_data()
    if not token:
        return _stub("No access_token found in ~/.codex/auth.json", "no_auth_token")

    headers = {
        "Authorization": f"Bearer {token}",
        "User-Agent": USER_AGENT,
        "Accept": "application/json",
    }
    if account_id:
        headers["ChatGPT-Account-Id"] = account_id

    req = urllib.request.Request(
        ENDPOINT,
        headers=headers,
        method="GET",
    )

    try:
        # Use a generic SSL context for better compatibility
        ctx = ssl.create_default_context()
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT, context=ctx) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except ssl.SSLError as exc:
        return _stub(f"SSL error during Codex API call: {type(exc).__name__}", "tls_failure")
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            return _stub("Codex OAuth 401: Unauthorized (token expired?)", "http_401")
        if exc.code == 429:
            return _stub("Codex OAuth 429: Rate limited by OpenAI", "http_429")
        return _stub(f"Codex API HTTP {exc.code}", f"http_{exc.code}")
    except urllib.error.URLError:
        return _stub("Codex API network error", "network")
    except (json.JSONDecodeError, OSError) as exc:
        return _stub(f"Codex API response parse error: {type(exc).__name__}", "parse")
    except Exception as exc:
        # Catch-all to prevent widget crashes, but avoid logging the token/traceback
        return _stub(f"Codex API unexpected error: {type(exc).__name__}", "unexpected")

    # Parse usage. Observed backend response shape:
    #   rate_limit.primary_window.used_percent       (5h block, 0-100)
    #   rate_limit.primary_window.reset_after_seconds
    #   rate_limit.primary_window.limit_window_seconds
    #   rate_limit.secondary_window.used_percent     (7d block)
    #   rate_limit.secondary_window.reset_after_seconds
    rl = data.get("rate_limit") or {}
    pw = rl.get("primary_window") or {}
    sw = rl.get("secondary_window") or {}
    if "used_percent" not in pw or "used_percent" not in sw:
        return _stub("Codex API response missing rate-limit windows", "schema")

    try:
        s_pct = round(float(pw["used_percent"]), 1)
        w_pct = round(float(sw["used_percent"]), 1)
    except (ValueError, TypeError):
        return _stub("Codex API returned malformed usage percentages", "schema")

    now = time.time()

    # Session window: use API's reset_after_seconds for accuracy.
    s_reset_after = pw.get("reset_after_seconds")
    s_window = pw.get("limit_window_seconds") or (5 * 3600)
    try:
        s_reset_after = float(s_reset_after) if s_reset_after is not None else None
        s_window = float(s_window)
    except (ValueError, TypeError):
        s_reset_after = None
        s_window = 5 * 3600
    if s_reset_after is not None and s_reset_after > 0:
        session_end = now + s_reset_after
        session_start = session_end - s_window
    else:
        session_end = now + s_window
        session_start = now
    session_resets_in = _format_resets_in(session_end - now)

    # Weekly window: prefer the API's secondary_window reset over Monday-anchor.
    w_reset_after = sw.get("reset_after_seconds")
    w_window = sw.get("limit_window_seconds") or (7 * 24 * 3600)
    try:
        w_reset_after = float(w_reset_after) if w_reset_after is not None else None
        w_window = float(w_window)
    except (ValueError, TypeError):
        w_reset_after = None
        w_window = 7 * 24 * 3600
    if w_reset_after is not None and w_reset_after > 0:
        week_end = now + w_reset_after
        week_start = week_end - w_window
    else:
        week_end = _pace_mod.next_monday_1am_local()
        week_start = week_end - caps.WEEKLY_WINDOW_SECONDS
    weekly_resets_in = _format_resets_in(week_end - now)

    s_pace = _pace_mod.build_pace_fields(s_pct, session_start, session_end, now)
    w_pace = _pace_mod.build_pace_fields(w_pct, week_start, week_end, now)

    return {
        "tool": "codex",
        "ok": True,
        "source": "api",
        "auth": {
            "account_id_present": bool(account_id),
        },
        "session": {
            "pct": min(s_pct, 999.9),
            "resets_in": session_resets_in,
            **s_pace,
        },
        "weekly": {
            "pct": min(w_pct, 999.9),
            "resets_in": weekly_resets_in,
            **w_pace,
        },
        "last_event_ts": int(now),
    }


def _stub(reason: str, code: str | None = None) -> dict:
    """Return fallback structure on error."""
    return {
        "tool": "codex",
        "ok": False,
        "source": "api",
        "error": reason,
        "error_code": code or "error",
        "fallback": "jsonl",
        "session": {"pct": 0.0, "resets_in": "—"},
        "weekly": {"pct": 0.0, "resets_in": "—"},
    }


if __name__ == "__main__":
    print(json.dumps(collect(), indent=2))
