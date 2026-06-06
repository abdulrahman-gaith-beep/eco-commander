"""
Codex CLI usage source.

Strategy: scan ~/.codex/sessions/**/*.jsonl. Codex stores token counters
CUMULATIVELY within a session — so per-file we take the MAX value seen
within each window, then sum across files.

Per-turn fields observed in the wild:
  input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens, total_tokens

All cumulative. We track input/output separately for the renderer's
I/O split, and use total_tokens as the canonical billable sum.

Codex stores OAuth tokens in ~/.codex/auth.json. A future enhancement
could replay the rate-limit endpoint directly; for now we estimate.
"""
from __future__ import annotations

import glob
import json
import os
import re
import time
from pathlib import Path

from . import caps
from . import pace as _pace_mod
from .time_utils import format_resets_in as _format_resets_in
from .time_utils import parse_iso_to_epoch as _parse_ts

CODEX_SESSIONS_DIR = Path.home() / ".codex" / "sessions"

# Capture per-event cumulative counters. They live on the same JSON line
# as `total_tokens`, so a regex pass is sufficient.
TOTAL_RE = re.compile(r'"total_tokens"\s*:\s*(\d+)')
INPUT_RE = re.compile(r'"input_tokens"\s*:\s*(\d+)')
OUTPUT_RE = re.compile(r'"output_tokens"\s*:\s*(\d+)')
CACHED_IN_RE = re.compile(r'"cached_input_tokens"\s*:\s*(\d+)')
REASONING_OUT_RE = re.compile(r'"reasoning_output_tokens"\s*:\s*(\d+)')
TS_RE = re.compile(r'"timestamp"\s*:\s*"([^"]+)"')

_next_monday_1am_local = _pace_mod.next_monday_1am_local
_cycle_elapsed_pct = _pace_mod.cycle_elapsed_pct
_pace = _pace_mod.classify_pace


def _pct_used(tokens: int, cap: int | float) -> float | None:
    if caps.is_unknown_token_cap(cap):
        return None
    return round(100 * tokens / cap, 1)


def _clamp_pct(pct: float | None) -> float | None:
    if pct is None:
        return None
    return min(pct, 999.9)


def _cap_status(cap: int | float) -> str:
    return "unknown" if caps.is_unknown_token_cap(cap) else "calibrated"


def _pace_with_pct(
    pct: float | None, cycle_start: float, cycle_end: float, now: float
) -> dict:
    pace_block = _pace_mod.build_pace_fields(pct or 0.0, cycle_start, cycle_end, now)
    if pct is None:
        return {
            **pace_block,
            "pace_delta_pp": None,
            "pace_label": "unknown",
            "pace_glyph": "—",
        }
    return pace_block


def _empty(reason: str) -> dict:
    base = {
        "tokens": 0, "input_tokens": 0, "output_tokens": 0,
        "reasoning_output_tokens": 0,
        "cached_input_tokens": 0, "pct": None, "pct_display": "—",
        "resets_in": "—",
    }
    return {
        "tool": "codex",
        "ok": False,
        "source": "jsonl",
        "error": reason,
        "session": {
            **base,
            "cap": caps.CODEX_PRO_SESSION_TOKENS,
            "cap_status": _cap_status(caps.CODEX_PRO_SESSION_TOKENS),
        },
        "weekly": {
            **base,
            "cap": caps.CODEX_PRO_WEEKLY_TOKENS,
            "cap_status": _cap_status(caps.CODEX_PRO_WEEKLY_TOKENS),
        },
        "last_event_ts": 0,
    }


def _zero_counts() -> dict[str, int]:
    return {"total": 0, "input": 0, "output": 0, "cached": 0, "reasoning": 0}


def _parse_token_line(line: str) -> tuple[float, dict[str, int]] | None:
    """Return (timestamp, cumulative counters) for one Codex JSONL line.

    This parser stays shape-tolerant: it only needs a timestamp and
    ``total_tokens`` on the line. Other counters default to zero so older
    session files continue to count.
    """
    if "total_tokens" not in line:
        return None
    tot_m = TOTAL_RE.search(line)
    if not tot_m:
        return None
    ts_m = TS_RE.search(line)
    ts = _parse_ts(ts_m.group(1)) if ts_m else None
    if ts is None:
        return None
    in_m = INPUT_RE.search(line)
    out_m = OUTPUT_RE.search(line)
    cin_m = CACHED_IN_RE.search(line)
    rout_m = REASONING_OUT_RE.search(line)
    return ts, {
        "total": int(tot_m.group(1)),
        "input": int(in_m.group(1)) if in_m else 0,
        "output": int(out_m.group(1)) if out_m else 0,
        "cached": int(cin_m.group(1)) if cin_m else 0,
        "reasoning": int(rout_m.group(1)) if rout_m else 0,
    }


def _delta_counts(max_counts: dict[str, int], baseline: dict[str, int]) -> dict[str, int]:
    return {
        k: max(0, int(max_counts.get(k, 0)) - int(baseline.get(k, 0)))
        for k in ("total", "input", "output", "cached", "reasoning")
    }


def _scan_file(path: str, session_since: float, week_since: float) -> dict:
    """Scan one cumulative-counter JSONL file and return per-window deltas.

    Codex stores cumulative counters per session file. If a session began
    before a quota window, raw max-in-window overcounts pre-window tokens. We
    therefore subtract the latest counter seen before each window boundary.
    """
    baseline_w = _zero_counts()
    baseline_s = _zero_counts()
    max_w = _zero_counts()
    max_s = _zero_counts()
    seen_w = False
    seen_s = False
    file_last_ts = 0.0
    earliest_session_ts = 0.0

    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            parsed = _parse_token_line(line)
            if parsed is None:
                continue
            ts, counts = parsed
            if ts > file_last_ts:
                file_last_ts = ts

            if ts < session_since:
                baseline_s = counts
            if ts < week_since:
                baseline_w = counts
                continue

            seen_w = True
            if counts["total"] >= max_w["total"]:
                max_w = counts

            if ts < session_since:
                # Still need to track weekly data but skip session
                continue

            seen_s = True
            if counts["total"] >= max_s["total"]:
                max_s = counts
                if earliest_session_ts == 0.0 or ts < earliest_session_ts:
                    earliest_session_ts = ts

    return {
        "week": _delta_counts(max_w, baseline_w) if seen_w else _zero_counts(),
        "session": _delta_counts(max_s, baseline_s) if seen_s else _zero_counts(),
        "last_ts": file_last_ts,
        "earliest_session_ts": earliest_session_ts,
    }


def collect() -> dict:
    now = time.time()
    session_since = now - caps.SESSION_WINDOW_SECONDS
    week_since = now - caps.WEEKLY_WINDOW_SECONDS

    s = {"total": 0, "input": 0, "output": 0, "cached": 0, "reasoning": 0}
    w = {"total": 0, "input": 0, "output": 0, "cached": 0, "reasoning": 0}
    last_event_ts = 0.0
    earliest_session_ts = 0.0

    if not CODEX_SESSIONS_DIR.exists():
        return _empty("sessions dir missing")

    for path in glob.glob(str(CODEX_SESSIONS_DIR / "**" / "*.jsonl"), recursive=True):
        try:
            if os.path.getmtime(path) < week_since and os.path.getsize(path) > 16 * 1024 * 1024:
                continue
            scanned = _scan_file(path, session_since, week_since)
            for k in ("total", "input", "output", "cached", "reasoning"):
                s[k] += scanned["session"][k]
                w[k] += scanned["week"][k]
            file_last_ts = float(scanned["last_ts"])
            file_session_ts = float(scanned["earliest_session_ts"])
            if file_session_ts and (earliest_session_ts == 0.0 or file_session_ts < earliest_session_ts):
                earliest_session_ts = file_session_ts
            if file_last_ts > last_event_ts:
                last_event_ts = file_last_ts
        except OSError:
            continue

    s_pct = _pct_used(s["total"], caps.CODEX_PRO_SESSION_TOKENS)
    w_pct = _pct_used(w["total"], caps.CODEX_PRO_WEEKLY_TOKENS)

    if earliest_session_ts > 0:
        block_start = earliest_session_ts
        block_end = block_start + caps.SESSION_WINDOW_SECONDS
        session_resets_in = _format_resets_in(block_end - now)
    else:
        block_start = block_end = 0.0
        session_resets_in = "—"

    week_end = _next_monday_1am_local()
    week_start = week_end - caps.WEEKLY_WINDOW_SECONDS
    weekly_resets_in = _format_resets_in(week_end - now)

    # Build pace blocks via shared pace.py — emits reset_epoch (T4 fix #3).
    s_pace_block = _pace_with_pct(s_pct, block_start, block_end, now)
    w_pace_block = _pace_with_pct(w_pct, week_start, week_end, now)

    return {
        "tool": "codex",
        "ok": True,
        "source": "jsonl",
        "session": {
            "tokens": s["total"],
            "input_tokens": s["input"],
            "output_tokens": s["output"],
            "reasoning_output_tokens": s["reasoning"],
            "cached_input_tokens": s["cached"],
            "cap": caps.CODEX_PRO_SESSION_TOKENS,
            "cap_status": _cap_status(caps.CODEX_PRO_SESSION_TOKENS),
            "pct": _clamp_pct(s_pct),
            **({"pct_display": "—"} if s_pct is None else {}),
            "resets_in": session_resets_in,
            **s_pace_block,
        },
        "weekly": {
            "tokens": w["total"],
            "input_tokens": w["input"],
            "output_tokens": w["output"],
            "reasoning_output_tokens": w["reasoning"],
            "cached_input_tokens": w["cached"],
            "cap": caps.CODEX_PRO_WEEKLY_TOKENS,
            "cap_status": _cap_status(caps.CODEX_PRO_WEEKLY_TOKENS),
            "pct": _clamp_pct(w_pct),
            **({"pct_display": "—"} if w_pct is None else {}),
            "resets_in": weekly_resets_in,
            **w_pace_block,
        },
        "last_event_ts": int(last_event_ts),
    }


if __name__ == "__main__":
    print(json.dumps(collect(), indent=2))
