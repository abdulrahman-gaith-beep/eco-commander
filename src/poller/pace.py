"""Shared pace-to-target machinery for all poller collectors.

Why this module exists
----------------------
Before this refactor, ``_pace()`` and ``_cycle_elapsed_pct()`` were duplicated
in three places (claude.py, codex.py, gemini.py) with subtle drift. T1 audit
recommended extraction; T3 locked it as Step 1; T4 confirmed it must land
*before* notify.py to keep thresholds uniform.

What's here
-----------
* ``cycle_elapsed_pct``  — how far through a reset cycle we are, 0..100.
* ``classify_pace``      — convert ``(actual_pct, expected_pct)`` → label/glyph.
* ``next_monday_1am_local`` — Anthropic's weekly anchor.
* ``THRESHOLDS``         — locked numbers from W4 brutal critic (T4).
* ``DEBOUNCE_HOURS``     — per-kind cooldown for notifications.
* ``WAKE_DEBOUNCE_S``    — skip evaluation after a sleep gap longer than this.

These constants are imported by ``notify.py`` so the same numbers drive both
the visible meters and the notification triggers.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

# ---------------------------------------------------------------------------
# Window definitions — canonical source is caps.py; re-exported here for
# callers that import pace but not caps.
# ---------------------------------------------------------------------------
from .caps import SESSION_WINDOW_SECONDS, WEEKLY_WINDOW_SECONDS

__all__ = [
    "DEBOUNCE_HOURS",
    "SESSION_WINDOW_SECONDS",
    "THRESHOLDS",
    "WAKE_DEBOUNCE_S",
    "WEEKLY_WINDOW_SECONDS",
    "build_pace_fields",
    "classify_pace",
    "cycle_elapsed_pct",
    "next_monday_1am_local",
]

# ---------------------------------------------------------------------------
# Locked thresholds
# ---------------------------------------------------------------------------

# Tuning rationale:
# - delta_pp_max -25 was too strict; it missed a real -21pp "behind" signal.
# - Softened to -15 + 15-pp headroom so we don't push the last few %.
THRESHOLDS: dict[str, dict[str, float]] = {
    "use_it_or_lose_it": {
        "target_pct_min": 80.0,   # only trigger late in the cycle
        "delta_pp_max":  -15.0,   # behind by at least 15 percentage points
        "remaining_min":  15.0,   # don't push into the last 15% of capacity
    },
    "throttle": {
        "pct_min":         80.0,
        "target_pct_max":  60.0,
        "delta_pp_min":    25.0,
    },
    "hard_wall": {
        "pct_min":         95.0,
    },
}

DEBOUNCE_HOURS: dict[str, int] = {
    "use_it_or_lose_it": 12,
    "throttle":           4,
    "hard_wall":          1,
}

# Wake-from-sleep guard (T4 §4) — skip an evaluation if the previous poll
# is older than this, to avoid spamming "use-it-or-lose-it" right after the
# laptop wakes across a Monday-1AM weekly rollover.
WAKE_DEBOUNCE_S = 300


# ---------------------------------------------------------------------------
# Time helpers
# ---------------------------------------------------------------------------


def next_monday_1am_local() -> float:
    """Return the epoch-seconds timestamp of the next Monday 01:00 local.

    Anthropic anchors weekly limits to Monday 01:00 local time; codex's weekly
    boundary is also tracked the same way for symmetry.
    """
    now = datetime.now(timezone.utc).astimezone()
    days_until_monday = (7 - now.weekday()) % 7
    candidate = (now + timedelta(days=days_until_monday)).replace(
        hour=1, minute=0, second=0, microsecond=0
    )
    if candidate <= now:
        candidate = candidate + timedelta(days=7)
    return candidate.timestamp()


def cycle_elapsed_pct(start_ts: float, end_ts: float, now: float) -> float:
    """How far through a cycle [start_ts, end_ts] is `now`, on 0..100.

    * Returns 0.0 if the cycle hasn't started, the span is non-positive, or
      times are nonsensical — never raises on bad input.
    * Clamped to 100.0 if past the end.
    """
    span = end_ts - start_ts
    if span <= 0:
        return 0.0
    elapsed = now - start_ts
    if elapsed <= 0:
        return 0.0
    if elapsed >= span:
        return 100.0
    return 100.0 * elapsed / span


# ---------------------------------------------------------------------------
# Pace classification
# ---------------------------------------------------------------------------


def classify_pace(actual_pct: float, expected_pct: float) -> dict:
    """Classify a meter's actual usage relative to the cycle-elapsed target.

    Returns a dict shaped::

        {"delta_pp": float, "label": str, "glyph": str}

    Labels and glyphs (chosen for colorblind-safety; shapes/animals not colors):

    * ``idle``    💤  — actual ≈ 0 and we're early in the cycle (no spam).
    * ``ahead``   🐎  — actual is +10pp or more above the target line.
    * ``on-pace`` 🟢  — within ±10pp of target.
    * ``behind``  🐢  — actual is -10pp or more below the target line.

    The ±10pp band is intentionally wider than the notification threshold
    (which is ±15 / +25). Display only labels; notifications fire on stricter
    deltas to keep alerts focused on actionable cases.
    """
    if actual_pct < 1.0 and expected_pct < 5.0:
        return {"delta_pp": 0.0, "label": "idle", "glyph": "💤"}

    delta = actual_pct - expected_pct
    if delta > 10.0:
        return {"delta_pp": round(delta, 1), "label": "ahead", "glyph": "🐎"}
    if delta < -10.0:
        return {"delta_pp": round(delta, 1), "label": "behind", "glyph": "🐢"}
    return {"delta_pp": round(delta, 1), "label": "on-pace", "glyph": "🟢"}


# ---------------------------------------------------------------------------
# Helper for collectors: build a pace block for a meter
# ---------------------------------------------------------------------------


def build_pace_fields(
    actual_pct: float,
    cycle_start_ts: float,
    cycle_end_ts: float,
    now: float,
) -> dict:
    """Return the four pace fields a collector emits per meter.

    * ``target_pct``      — cycle-elapsed-percentage (0..100)
    * ``pace_delta_pp``   — actual minus target
    * ``pace_label``      — idle / ahead / on-pace / behind
    * ``pace_glyph``      — colorblind-safe glyph
    * ``reset_epoch``     — when the cycle ends, epoch seconds (NEW; T4 fix #3 —
                            cycle-reset detection in notify.py needs this)
    """
    target = cycle_elapsed_pct(cycle_start_ts, cycle_end_ts, now)
    pace = classify_pace(actual_pct, target)
    return {
        "target_pct":     round(target, 1),
        "pace_delta_pp":  pace["delta_pp"],
        "pace_label":     pace["label"],
        "pace_glyph":     pace["glyph"],
        "reset_epoch":    int(cycle_end_ts) if cycle_end_ts > 0 else 0,
    }
