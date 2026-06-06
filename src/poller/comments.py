"""
Burn-rate detection + sticky-random comment selection.
Triggers on delta_pct between consecutive cycles (60s apart).
"""
import hashlib
import json
import os
import time
from pathlib import Path

from .time_utils import resolve_dotpath as _resolve

# Metadata keys from notify.py
METERS = [
    {"key": "claude.session", "tool": "Claude"},
    {"key": "claude.weekly",  "tool": "Claude"},
    {"key": "codex.session",  "tool": "Codex"},
    {"key": "codex.weekly",   "tool": "Codex"},
    {"key": "gemini.tiers.flash",      "tool": "Gemini"},
    {"key": "gemini.tiers.flash_lite", "tool": "Gemini"},
    {"key": "gemini.tiers.pro",        "tool": "Gemini"},
]

COOLDOWNS = {
    "gentle": 1800,  # 30m
    "bold": 900,    # 15m
    "alarmed": 300,  # 5m
}

def _comments_config_path() -> Path:
    """Return the user override catalog path under the configured ECO_HOME."""
    try:
        from common.config import EcoConfig

        return EcoConfig.from_env().eco_home / "config" / "comments.json"
    except ImportError:
        return Path(os.environ.get("ECO_HOME", str(Path.home() / ".eco"))) / "config" / "comments.json"


def evaluate(merged_usage: dict, prev_usage: dict | None, state: dict) -> str | None:
    """Return the comment for the highest-burn meter, or None.
    Updates `state` in place with last_comment_ts per tier."""
    if os.environ.get("ECO_COMMENTS", "0") != "1":
        return None
    if prev_usage is None:
        return None

    now = time.time()
    cur_ts_raw = merged_usage.get("ts")
    prev_ts_raw = prev_usage.get("ts")
    if cur_ts_raw is not None and prev_ts_raw is not None:
        cur_ts = float(cur_ts_raw)
        prev_ts = float(prev_ts_raw)
        gap = cur_ts - prev_ts
        # Avoid laptop-wake / long-idle spikes: comments compare adjacent poller
        # samples, not arbitrary old snapshots.
        if gap <= 0 or gap > 5 * 60:
            return None
    # Ensure state structure exists. Per A2 brutal fix, we use per-tier keys.
    lcts = state.setdefault("last_comment_ts", {"gentle": 0.0, "bold": 0.0, "alarmed": 0.0})
    if not isinstance(lcts, dict):
        lcts = state["last_comment_ts"] = {"gentle": 0.0, "bold": 0.0, "alarmed": 0.0}

    candidates = []
    for m in METERS:
        curr = _resolve(merged_usage, m["key"])
        prev = _resolve(prev_usage, m["key"])
        if not (curr and prev):
            continue
        if curr.get("reset_epoch") and prev.get("reset_epoch") and int(curr["reset_epoch"]) != int(prev["reset_epoch"]):
            continue

        delta = float(curr.get("pct", 0)) - float(prev.get("pct", 0))
        if delta >= 20:
            candidates.append((delta, "alarmed", m["tool"]))
        elif delta >= 10:
            candidates.append((delta, "bold", m["tool"]))
        elif delta >= 5:
            candidates.append((delta, "gentle", m["tool"]))

    if not candidates:
        return None

    # Pick highest-burn candidate
    candidates.sort(key=lambda x: x[0], reverse=True)
    _best_delta, tier, tool = candidates[0]

    # Cooldown check: alarmed (5m) pre-empts others; others respect 5m global quiet.
    last_any = max(float(v) for v in lcts.values())
    if tier == "alarmed":
        if (now - float(lcts.get("alarmed", 0))) < 300:
            return None
    else:
        if (now - float(lcts.get(tier, 0))) < COOLDOWNS[tier]:
            return None
        if (now - last_any) < 300:
            return None

    # Load catalog: user override ($ECO_HOME/config/comments.json) > bundled default
    user_cfg = _comments_config_path()
    bundled_cfg = Path(__file__).parent / "data" / "comments.json"

    cfg_path = user_cfg if user_cfg.exists() else bundled_cfg
    try:
        catalog = json.loads(cfg_path.read_text(encoding="utf-8"))
        options = catalog.get("tiers", {}).get(tier, [])
    except (OSError, json.JSONDecodeError, AttributeError):
        return None

    if not options:
        return None

    # Sticky 4-hour bucket selection: (tool, tier, epoch // 14400)
    bucket = int(now) // 14400
    seed = f"{tool}:{tier}:{bucket}".encode()
    h = hashlib.sha256(seed).hexdigest()
    idx = int(h, 16) % len(options)
    comment = str(options[idx])

    # Persist state
    lcts[tier] = now
    state["last_comment_text"] = comment
    return comment
