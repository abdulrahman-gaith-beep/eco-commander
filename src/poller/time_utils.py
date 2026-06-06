"""Shared time formatting and ISO parsing helpers for all poller collectors.

Extracted from claude.py, codex.py, gemini.py, claude_oauth.py, and
codex_oauth.py where these functions were duplicated identically (S1/S2
from src/ audit 2026-05-22).

All collectors should import from here instead of defining their own.
"""
from __future__ import annotations

from datetime import datetime


def parse_iso_to_epoch(ts: str) -> float | None:
    """Parse an ISO 8601 timestamp string to epoch seconds.

    Handles both ``Z``-suffixed UTC timestamps and ``+HH:MM`` offset forms.
    Returns ``None`` on invalid input — never raises.
    """
    if not ts:
        return None
    try:
        if ts.endswith("Z"):
            ts = ts[:-1] + "+00:00"
        return datetime.fromisoformat(ts).timestamp()
    except (ValueError, TypeError):
        return None


def format_resets_in(seconds: float) -> str:
    """Format a countdown in seconds as a human-readable ``Nh MMm`` string.

    Examples:
        ``format_resets_in(7500)`` → ``"2h 05m"``
        ``format_resets_in(90000)`` → ``"1d 1h"``
        ``format_resets_in(-10)`` → ``"0h 00m"``
    """
    s = max(0, int(seconds))
    h, rem = divmod(s, 3600)
    m, _ = divmod(rem, 60)
    if h >= 24:
        d = h // 24
        return f"{d}d {h % 24}h"
    return f"{h}h {m:02d}m"


def resolve_dotpath(data: dict, key: str) -> dict | None:
    """Walk a dot-separated path through nested dicts.

    Example: ``resolve_dotpath(merged, "claude.session")`` returns
    ``merged["claude"]["session"]`` if both levels are dicts, else ``None``.

    Extracted from notify.py and comments.py where it was duplicated as
    ``_resolve()`` (S3 from audit).
    """
    node: object = data
    for part in key.split("."):
        if not isinstance(node, dict):
            return None
        node = node.get(part)
        if node is None:
            return None
    return node if isinstance(node, dict) else None
