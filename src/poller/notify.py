"""Pace-based notification dispatcher.

Decides which (if any) macOS notification to fire based on each meter's
pace state. Debounced via state file at ``~/.eco/state/notify.json``.

Trigger logic (locked in T3 + T4):
  * use_it_or_lose_it — late in cycle AND meaningfully behind AND headroom
    remaining. Tells you "stop hoarding paid quota".
  * throttle — heavily used early-mid cycle. Tells you "you'll hit the wall".
  * hard_wall — at or above 95%. Tells you "switch tools NOW".

Anti-spam:
  * Per-meter, per-kind cooldown (DEBOUNCE_HOURS).
  * Wake-from-sleep guard — skip if we missed a poll cycle by >5 minutes
    (T4 §4 — avoids the laptop-wake spam scenario).
  * Cycle-reset detection via ``reset_epoch`` change (T4 fix #3 — was
    pct-delta, brittle on rolling 5h windows).
  * Master env switch ``ECO_NOTIFICATIONS=0`` disables everything.

Safety:
  * LOG_ONLY mode (default ON via ``ECO_NOTIFY_LOG_ONLY=1``, T4 fix C3) —
    decisions are logged but no actual notification fires. Flip to 0 in
    config when ready to go live.
  * AppleScript body is escaped as AppleScript string literals.
  * State file uses atomic write (write to .tmp, os.replace) so a crash
    mid-write can't corrupt durable state.
"""
from __future__ import annotations

import json
import logging
import os
import subprocess
import tempfile
import time
from contextlib import suppress
from pathlib import Path
from typing import Any

from . import pace as _pace_mod
from .time_utils import resolve_dotpath as _resolve

logger = logging.getLogger("eco.poller.notify")

try:
    from common.config import EcoConfig
except ImportError:
    EcoConfig = None  # type: ignore[assignment,misc]

STATE_PATH = Path.home() / ".eco" / "state" / "notify.json"  # legacy fallback
STATE_VERSION = 1


def _state_path() -> Path:
    if EcoConfig is not None:
        return EcoConfig.from_env().state_dir / "notify.json"
    return Path(os.environ.get("ECO_HOME", Path.home() / ".eco")) / "state" / "notify.json"


def _log_only() -> bool:
    """Default LOG_ONLY=True so step 7 of the rollout is a config flip,
    not a code change (T4 fix C3)."""
    return os.environ.get("ECO_NOTIFY_LOG_ONLY", "1") != "0"


def _enabled() -> bool:
    """Master off-switch. Default on."""
    return os.environ.get("ECO_NOTIFICATIONS", "1") != "0"


# ---------------------------------------------------------------------------
# Meters — keyed by JSON pointer (T4 fix #2 — keys mirror real shape)
# ---------------------------------------------------------------------------

METERS: list[dict[str, Any]] = [
    {"key": "claude.session", "tool": "Claude", "meter": "Session",
     "model_class": "Opus/Sonnet"},
    {"key": "claude.weekly",  "tool": "Claude", "meter": "Weekly",
     "model_class": "Sonnet"},
    {"key": "codex.session",  "tool": "Codex",  "meter": "Session",
     "model_class": "GPT-5.5"},
    {"key": "codex.weekly",   "tool": "Codex",  "meter": "Weekly",
     "model_class": "GPT-5.5"},
    {"key": "gemini.tiers.flash",      "tool": "Gemini", "meter": "Flash",
     "model_class": "Flash 3"},
    {"key": "gemini.tiers.flash_lite", "tool": "Gemini", "meter": "Flash Lite",
     "model_class": "Flash Lite 3.1"},
    {"key": "gemini.tiers.pro",        "tool": "Gemini", "meter": "Pro",
     "model_class": "Pro 3.1"},
]

# Notification copy templates. T4 fix #4: branch on missing reset_epoch
# so we never render literally "Resets in —".
TEMPLATES = {
    "use_it_or_lose_it": (
        "🐢 {tool} {meter} underutilized "
        "({pct:.0f}% vs {target:.0f}% target).{cycle_msg} "
        "Shift {model_class} tasks here."
    ),
    "throttle": (
        "🐎 {tool} {meter} hot ({pct:.0f}% used vs {target:.0f}% target). "
        "Switch to a lower-cost or local fallback."
    ),
    "hard_wall": (
        "⚠️ {tool} {meter} at {pct:.0f}%. Hard limit imminent. "
        "Use another configured fallback for remaining work."
    ),
}


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------


def _load_state() -> dict[str, Any]:
    path = _state_path()
    if not path.exists():
        return {"version": STATE_VERSION, "last_poll_ts": 0, "meters": {}}
    try:
        raw: Any = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        logger.warning(f"notify state corrupt; resetting: {exc}")
        return {"version": STATE_VERSION, "last_poll_ts": 0, "meters": {}}
    data: dict[str, Any] = raw if isinstance(raw, dict) else {}
    # M3 fix — protect against partially-corrupt-but-parseable state.
    data.setdefault("version", STATE_VERSION)
    data.setdefault("last_poll_ts", 0)
    data.setdefault("meters", {})
    if not isinstance(data["meters"], dict):
        data["meters"] = {}
    return data


def _save_state(state: dict[str, Any]) -> None:
    path = _state_path()
    tmp = ""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(state, fh, indent=2, sort_keys=True)
        os.replace(tmp, path)
    except OSError as exc:
        logger.warning(f"notify state write failed: {exc}")
        if tmp:
            with suppress(OSError):
                os.unlink(tmp)


# ---------------------------------------------------------------------------
# Meter resolution
# ---------------------------------------------------------------------------





def _classify(meter: dict[str, Any]) -> str | None:
    """Return one of 'use_it_or_lose_it' / 'throttle' / 'hard_wall' / None."""
    pct = float(meter.get("pct", 0))
    target = float(meter.get("target_pct", 0))
    delta = float(meter.get("pace_delta_pp", 0))

    t = _pace_mod.THRESHOLDS
    if pct >= t["hard_wall"]["pct_min"]:
        return "hard_wall"
    if (pct >= t["throttle"]["pct_min"]
            and target <= t["throttle"]["target_pct_max"]
            and delta >= t["throttle"]["delta_pp_min"]):
        return "throttle"
    if (target >= t["use_it_or_lose_it"]["target_pct_min"]
            and delta <= t["use_it_or_lose_it"]["delta_pp_max"]
            and (100.0 - pct) >= t["use_it_or_lose_it"]["remaining_min"]):
        return "use_it_or_lose_it"
    return None


def _should_fire(meter_state: dict[str, Any], kind: str, now: float) -> bool:
    last_by_kind = meter_state.get("last_fired_by_kind")
    if not isinstance(last_by_kind, dict):
        last_by_kind = {}
    if kind == "hard_wall" and meter_state.get("last_kind") not in ("hard_wall", None):
        return True
    last_fired = float(last_by_kind.get(kind, meter_state.get("last_fired_ts", 0)) or 0)
    if last_fired == 0:
        return True
    cooldown_s = _pace_mod.DEBOUNCE_HOURS[kind] * 3600
    return (now - last_fired) >= cooldown_s


def _format_body(meter_meta: dict, meter_data: dict, kind: str) -> str:
    pct = float(meter_data.get("pct", 0))
    target = float(meter_data.get("target_pct", 0))
    resets_in = meter_data.get("resets_in", "")
    # T4 fix #4 — don't render "Resets in —" if resets_in is unknown.
    cycle_msg = f" Resets in {resets_in}." if resets_in and resets_in != "—" else ""
    return TEMPLATES[kind].format(
        tool=meter_meta["tool"],
        meter=meter_meta["meter"],
        pct=pct, target=target,
        model_class=meter_meta["model_class"],
        cycle_msg=cycle_msg,
    )


def _as_string_literal(value: str) -> str:
    """Escape a Python string for an AppleScript double-quoted literal."""
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _dispatch(title: str, body: str) -> None:
    """Fire a macOS notification via osascript. Quote-safe; timeout-bound."""
    if _log_only():
        logger.info(f"[notify LOG_ONLY] {title} — {body}")
        return
    script = (
        f"display notification {_as_string_literal(body)} "
        f"with title {_as_string_literal(title)}"
    )
    try:
        subprocess.run(
            ["osascript", "-e", script],
            timeout=3, check=False,
            capture_output=True,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        logger.warning(f"osascript dispatch failed: {exc}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def evaluate(merged: dict[str, Any]) -> dict[str, Any]:
    """Inspect each meter; fire/skip notifications; persist state."""
    now = time.time()
    notifications_enabled = _enabled()
    state = _load_state()

    # Wake-from-sleep guard (T4 §4) — single check up front.
    last_poll = float(state.get("last_poll_ts", 0))
    if last_poll > 0 and (now - last_poll) > _pace_mod.WAKE_DEBOUNCE_S:
        logger.info(f"notify: wake-from-sleep ({now - last_poll:.0f}s gap); skip this cycle")
        state["last_poll_ts"] = int(now)
        _save_state(state)
        return {"fired": [], "skipped_wake": True}
    state["last_poll_ts"] = int(now)

    fired: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []

    for meta in METERS:
        meter = _resolve(merged, meta["key"])
        if not meter:
            continue
        meter_state = state["meters"].setdefault(meta["key"], {})
        kind = _classify(meter)
        if not kind:
            meter_state["current_kind"] = "healthy"
            meter_state["current_seen_ts"] = int(now)
            meter_state["last_kind"] = "unknown"
            continue

        # Cycle-reset detection (T4 fix #3): clear last_fired_ts when the
        # cycle's reset_epoch changed since we last saw it.
        cur_reset = int(meter.get("reset_epoch") or 0)
        last_reset = int(meter_state.get("last_reset_epoch") or 0)
        if cur_reset and cur_reset != last_reset:
            meter_state["last_fired_ts"] = 0
            meter_state["last_fired_by_kind"] = {}
            meter_state["last_reset_epoch"] = cur_reset

        meter_state["current_kind"] = kind
        meter_state["current_seen_ts"] = int(now)
        meter_state["last_reset_epoch"] = cur_reset or last_reset

        # Scheduler routing depends on notify.json even when desktop
        # notifications are disabled. Keep the meter state current; only skip
        # delivery side effects.
        if not notifications_enabled:
            meter_state["last_kind"] = kind
            if kind in ("hard_wall", "throttle"):
                meter_state["last_fired_ts"] = int(now)
            skipped.append({"meter": meta["key"], "kind": kind, "reason": "notifications_disabled"})
            continue

        if not _should_fire(meter_state, kind, now):
            meter_state["last_kind"] = kind
            skipped.append({"meter": meta["key"], "kind": kind, "reason": "debounced"})
            continue

        title = f"eco-commander · {kind.replace('_', ' ').title()}"
        body = _format_body(meta, meter, kind)
        _dispatch(title, body)
        fired_by_kind = meter_state.setdefault("last_fired_by_kind", {})
        if not isinstance(fired_by_kind, dict):
            fired_by_kind = meter_state["last_fired_by_kind"] = {}
        fired_by_kind[kind] = int(now)
        meter_state["last_fired_ts"] = int(now)
        meter_state["last_kind"] = kind
        fired.append({"meter": meta["key"], "kind": kind, "body": body})

    _save_state(state)
    result: dict[str, Any] = {"fired": fired, "skipped": skipped}
    if not notifications_enabled:
        result["skipped_global"] = True
    return result
