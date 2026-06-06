"""Quota-aware routing: meter availability + model-preference ladder walk.

Reads meter state written by src/poller/notify.py at ~/.eco/state/notify.json.
Each meter has a `last_kind` (use_it_or_lose_it | throttle | hard_wall) and a
`last_reset_epoch`. A meter is BLOCKED when last_kind == "hard_wall" and the
reset epoch hasn't passed. Throttle adds a per-minute cooldown.
"""

from __future__ import annotations

import time
from collections.abc import Iterable
from dataclasses import dataclass
from typing import Any, Literal

MeterKind = Literal["use_it_or_lose_it", "throttle", "hard_wall", "unknown"]
_KNOWN_KINDS: set[MeterKind] = {"use_it_or_lose_it", "throttle", "hard_wall", "unknown"}


def _safe_float(value: Any, default: float = 0.0) -> float:
    """Best-effort float conversion for untrusted meter state."""
    if isinstance(value, bool):
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


@dataclass(frozen=True)
class MeterStatus:
    """Snapshot of one meter's availability."""

    key: str
    kind: MeterKind
    last_reset_epoch: float
    last_fired_ts: float
    available: bool
    reason: str  # empty if available
    seconds_until_available: int  # 0 if available now


def meter_status(state: dict[str, Any], meter_key: str, now: float | None = None) -> MeterStatus:
    """Return availability snapshot for one meter.

    Args:
        state: Full notify.json dict (must have a `meters` key, but defensive about it).
        meter_key: e.g. "gemini.tiers.pro", "codex.session", "claude.session".
        now: Override epoch for testing. Defaults to time.time().
    """
    now = time.time() if now is None else now
    meters = state.get("meters", {}) if isinstance(state, dict) else {}
    if not isinstance(meters, dict):
        meters = {}
    m = meters.get(meter_key)

    if not isinstance(m, dict) or not m:
        # Unknown meter: optimistic — we'd rather attempt than over-block.
        return MeterStatus(
            key=meter_key,
            kind="unknown",
            last_reset_epoch=0.0,
            last_fired_ts=0.0,
            available=True,
            reason="",
            seconds_until_available=0,
        )

    raw_kind = m.get("last_kind", "unknown")
    kind: MeterKind = raw_kind if isinstance(raw_kind, str) and raw_kind in _KNOWN_KINDS else "unknown"
    reset_epoch = _safe_float(m.get("last_reset_epoch", 0.0))
    last_fired = _safe_float(m.get("last_fired_ts", 0.0))

    # hard_wall: blocked until reset epoch passes
    if kind == "hard_wall" and reset_epoch > now:
        return MeterStatus(
            key=meter_key,
            kind=kind,
            last_reset_epoch=reset_epoch,
            last_fired_ts=last_fired,
            available=False,
            reason="hard_wall",
            seconds_until_available=int(reset_epoch - now),
        )

    # throttle: 60s cooldown after last fire (per-minute rate limit)
    if kind == "throttle" and (now - last_fired) < 60:
        return MeterStatus(
            key=meter_key,
            kind=kind,
            last_reset_epoch=reset_epoch,
            last_fired_ts=last_fired,
            available=False,
            reason="throttle_cooldown",
            seconds_until_available=int(60 - (now - last_fired)),
        )

    # use_it_or_lose_it: always available — burn it
    return MeterStatus(
        key=meter_key,
        kind=kind,
        last_reset_epoch=reset_epoch,
        last_fired_ts=last_fired,
        available=True,
        reason="",
        seconds_until_available=0,
    )


def meter_available(state: dict[str, Any], meter_key: str, now: float | None = None) -> bool:
    """Boolean shortcut for ``meter_status(...).available``."""
    return meter_status(state, meter_key, now).available


@dataclass(frozen=True)
class LadderChoice:
    """Result of walking a model_preference ladder."""

    candidate: dict[str, Any] | None  # the chosen ladder rung, or None if all blocked
    skipped: list[tuple[str, str]]  # [(provider/model, reason), ...]
    next_available_in_s: int  # if None chosen, min seconds until SOME rung opens


def pick_candidate(
    ladder: Iterable[dict[str, Any]],
    state: dict[str, Any],
    now: float | None = None,
) -> LadderChoice:
    """Walk a job's model_preference ladder; return first rung whose meter is open.

    Each rung is a dict like ``{"provider": "codex", "model": "gpt-5.5", "meter": "codex.session"}``.
    """
    now = time.time() if now is None else now
    skipped: list[tuple[str, str]] = []
    min_wait = 10**9

    for rung in ladder:
        meter_key = rung.get("meter", "")
        st = meter_status(state, meter_key, now)
        if st.available:
            return LadderChoice(candidate=rung, skipped=skipped, next_available_in_s=0)
        skipped.append(
            (
                f"{rung.get('provider', '?')}/{rung.get('model', '?')}",
                st.reason,
            )
        )
        if st.seconds_until_available < min_wait:
            min_wait = st.seconds_until_available

    return LadderChoice(
        candidate=None,
        skipped=skipped,
        next_available_in_s=0 if min_wait == 10**9 else int(min_wait),
    )
