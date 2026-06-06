"""
Claude Code usage source.

Strategy: parse ~/.claude/projects/**/*.jsonl, sum `usage` token fields
on assistant messages within the rolling 5h and 7d windows.

Two sophistications added 2026-05-10 after a 3-auditor calibration
investigation found our naive sum was systematically wrong:

  1. **Dedupe by message.id.** A single assistant turn often produces
     multiple JSONL rows that share `message.id` and emit overlapping
     usage objects (streaming partial → final, multi-content-block
     fanout). Naive summing double-counts. We keep the row with the
     largest output_tokens per id (the final-streamed row carries
     cumulative output; input/cache numbers are stable across rows).

  2. **Per-model bucketing.** Paid Claude tiers can expose independent
     rate-limit windows: 5h (all), 7d (all), and model-specific weekly
     buckets. We track the visible buckets and show the worst-saturated one.

  3. **cache_read weighted at 0.0x.** cache_read_input_tokens were previously
     weighted at 0.10x due to conflating Anthropic's pricing (10% cost)
     with Anthropic's Rate Limits. Anthropic docs explicitly state:
     "Tokens read from cache do not count towards your token rate limits."

The default JSONL path does not touch the macOS Keychain. Keychain-backed
server-truth lives in claude_oauth.py and is used only when
discovery.server_truth_enabled("claude") is true. This collector estimates
from JSONL and marks source="jsonl" so downstream knows.
"""
from __future__ import annotations

import glob
import json
import os
import time
from pathlib import Path

from . import caps, discovery
from . import pace as _pace_mod
from .time_utils import format_resets_in as _format_resets_in
from .time_utils import parse_iso_to_epoch as _parse_ts

CLAUDE_PROJECTS_DIR = Path.home() / ".claude" / "projects"

_next_monday_1am_local = _pace_mod.next_monday_1am_local


def _classify_model(model: str) -> str:
    m = (model or "").lower()
    if "opus" in m:
        return "opus"
    if "sonnet" in m:
        return "sonnet"
    if "haiku" in m:
        return "haiku"
    return "other"


def _iter_assistant_records(since_ts: float):
    """Yield (path, ts, usage, msg_id, model) for assistant messages."""
    if not CLAUDE_PROJECTS_DIR.exists():
        return
    for path in glob.glob(str(CLAUDE_PROJECTS_DIR / "**" / "*.jsonl"), recursive=True):
        try:
            mtime = os.path.getmtime(path)
            # Pre-filter only large files where mtime can be trusted to skip.
            if mtime < since_ts and os.path.getsize(path) > 16 * 1024 * 1024:
                continue
            with open(path, encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    if '"usage"' not in line or '"assistant"' not in line:
                        continue
                    try:
                        rec = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if rec.get("type") != "assistant":
                        continue
                    msg = rec.get("message")
                    if not isinstance(msg, dict):
                        continue
                    usage = msg.get("usage")
                    if not usage:
                        continue
                    ts = _parse_ts(rec.get("timestamp") or "")
                    if ts is None or ts < since_ts:
                        continue
                    yield (
                        path, ts, usage,
                        msg.get("id") or rec.get("uuid") or f"_anon:{path}:{ts}",
                        msg.get("model") or "",
                    )
        except OSError:
            continue


def _empty_breakdown() -> dict:
    return {
        "input": 0, "output": 0,
        "cache_creation": 0, "cache_read": 0,
        "billable": 0,
    }


def _add(into: dict, src: dict, crw: float) -> None:
    i = int(src.get("input_tokens") or 0)
    o = int(src.get("output_tokens") or 0)
    cc = int(src.get("cache_creation_input_tokens") or 0)
    cr = int(src.get("cache_read_input_tokens") or 0)
    into["input"] += i
    into["output"] += o
    into["cache_creation"] += cc
    into["cache_read"] += cr
    into["billable"] += i + o + cc + int(crw * cr)


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


def _compute_active_block(
    sorted_events: list, window_seconds: int = 5 * 3600
) -> tuple[float, float, bool]:
    """Walk chronologically-sorted events to find the active session block.

    Anthropic's 5h block semantics: block starts at first message after a
    >=window_seconds gap (or the very first message ever). Block lasts
    exactly window_seconds from its start; subsequent messages within the
    block do NOT extend it. After expiry, the next message starts a new block.

    Args:
        sorted_events: list of (ts, usage, model, path) tuples, sorted by ts asc.
        window_seconds: block length (default 5h).

    Returns:
        (block_start, block_end, is_active) — is_active is True iff
        block_end > time.time() (block still has time remaining).
        Returns (0.0, 0.0, False) if sorted_events is empty.
    """
    if not sorted_events:
        return 0.0, 0.0, False

    block_start = sorted_events[0][0]
    block_end = block_start + window_seconds

    for evt in sorted_events[1:]:
        ts = evt[0]
        if ts >= block_end:
            block_start = ts
            block_end = ts + window_seconds

    is_active = block_end > time.time()
    return block_start, block_end, is_active


def collect() -> dict:
    now = time.time()
    week_since = now - caps.WEEKLY_WINDOW_SECONDS
    crw = caps.CACHE_READ_WEIGHT

    # Step 1: dedupe by message.id.
    # Streaming partial→final pattern: same id, monotonically increasing
    # output_tokens; identical input/cache numbers. Final row is the one
    # with the largest output_tokens.
    best: dict[str, tuple[float, dict, str, str]] = {}
    for path, ts, usage, mid, model in _iter_assistant_records(week_since):
        prev = best.get(mid)
        if prev is None or int(usage.get("output_tokens") or 0) > int(
            prev[1].get("output_tokens") or 0
        ):
            best[mid] = (ts, usage, model, path)

    # Step 2: aggregate into all-models + per-model buckets.
    s_all = _empty_breakdown()
    w_all = _empty_breakdown()
    s_by_model = {k: _empty_breakdown() for k in ("opus", "sonnet", "haiku", "other")}
    w_by_model = {k: _empty_breakdown() for k in ("opus", "sonnet", "haiku", "other")}

    # Sort events chronologically for block calculation and stable iteration.
    sorted_events = sorted(best.values(), key=lambda x: x[0])

    # Identify the active session block (Anthropic semantics).
    block_start, block_end, is_active = _compute_active_block(
        sorted_events, caps.SESSION_WINDOW_SECONDS
    )

    last_event_ts = 0.0
    session_files: set[str] = set()
    weekly_files: set[str] = set()
    s_models_seen: set[str] = set()
    w_models_seen: set[str] = set()

    for ts, usage, model, path in sorted_events:
        bucket = _classify_model(model)
        _add(w_all, usage, crw)
        _add(w_by_model[bucket], usage, crw)
        weekly_files.add(path)
        # Filter out synthetic/internal model markers like "<synthetic>"
        is_real_model = bool(model) and not model.startswith("<")
        if is_real_model:
            w_models_seen.add(model)

        # Only events within the ACTIVE block count toward session usage.
        if is_active and block_start <= ts < block_end:
            _add(s_all, usage, crw)
            _add(s_by_model[bucket], usage, crw)
            session_files.add(path)
            if is_real_model:
                s_models_seen.add(model)

        if ts > last_event_ts:
            last_event_ts = ts

    # Step 3: reset times + cycle math for pace-to-target.
    if is_active:
        session_resets_in = _format_resets_in(block_end - now)
    else:
        # Session is dormant (no active block).
        block_start = block_end = 0.0
        session_resets_in = "—"

    week_end = _next_monday_1am_local()
    week_start = week_end - caps.WEEKLY_WINDOW_SECONDS
    weekly_resets_in = _format_resets_in(week_end - now)

    # Step 4: percentages.
    # Anthropic exposes only 2 weekly meters (all + Sonnet-only); no Opus meter.
    s_pct = _pct_used(s_all["billable"], caps.CLAUDE_MAX20X_5H_TOKENS)
    w_all_pct = _pct_used(w_all["billable"], caps.CLAUDE_MAX20X_7D_ALL_TOKENS)
    w_sonnet_pct = _pct_used(
        w_by_model["sonnet"]["billable"],
        caps.CLAUDE_MAX20X_7D_SONNET_TOKENS,
    )
    # Headline weekly = worst-saturated bucket (matches Claude.ai's display).
    known_weekly_pcts = [p for p in (w_all_pct, w_sonnet_pct) if p is not None]
    w_headline = max(known_weekly_pcts) if known_weekly_pcts else None

    # Build per-meter pace blocks from shared pace.py — one source of truth.
    s_pace_block = _pace_with_pct(s_pct, block_start, block_end, now)
    w_pace_block = _pace_with_pct(w_headline, week_start, week_end, now)

    return {
        "tool": "claude",
        "ok": True,
        "source": "jsonl",
        "session": {
            "tokens": s_all["billable"],
            "input_tokens": s_all["input"],
            "output_tokens": s_all["output"],
            "cache_creation_tokens": s_all["cache_creation"],
            "cache_read_tokens": s_all["cache_read"],
            "by_model": {k: v["billable"] for k, v in s_by_model.items()},
            "models_seen": sorted(s_models_seen),
            "cap": caps.CLAUDE_MAX20X_5H_TOKENS,
            "cap_status": _cap_status(caps.CLAUDE_MAX20X_5H_TOKENS),
            "pct": _clamp_pct(s_pct),
            **({"pct_display": "—"} if s_pct is None else {}),
            "resets_in": session_resets_in,
            "sessions": len(session_files),
            # Pace-to-target + reset_epoch (T4 fix #3 — notify.py needs this).
            **s_pace_block,
        },
        "weekly": {
            "tokens": w_all["billable"],
            "input_tokens": w_all["input"],
            "output_tokens": w_all["output"],
            "cache_creation_tokens": w_all["cache_creation"],
            "cache_read_tokens": w_all["cache_read"],
            "by_model": {k: v["billable"] for k, v in w_by_model.items()},
            "models_seen": sorted(w_models_seen),
            "cap": caps.CLAUDE_MAX20X_7D_ALL_TOKENS,
            "cap_sonnet": caps.CLAUDE_MAX20X_7D_SONNET_TOKENS,
            "cap_status": (
                "unknown"
                if w_headline is None
                else "calibrated"
            ),
            "pct": _clamp_pct(w_headline),
            "pct_all": _clamp_pct(w_all_pct),
            "pct_sonnet": _clamp_pct(w_sonnet_pct),
            **({"pct_display": "—"} if w_headline is None else {}),
            "resets_in": weekly_resets_in,
            "sessions": len(weekly_files),
            **w_pace_block,
        },
        "last_event_ts": int(last_event_ts),
        "dedup_unique_messages": len(best),
        "cache_read_weight": crw,
    }




# --- Multi-account iteration ----------------------------------------------
# Claude Code uses a single ~/.claude/ auth context. So "multi-account"
# means: whichever account is currently authenticated is the one we can
# estimate from JSONL. The other configured slot(s) appear as ok=False until
# the user runs
#   claude logout && claude login
# to swap.
#
# We still emit a per_account[] array so the widget can render both slots
# and prompt the swap when the inactive slot is the interesting one.
# Slugs come from $ECO_CLAUDE_ACCOUNTS (comma-separated), default "primary".
UNKNOWN_PLAN = "Unknown"


def _account_slugs() -> list[str]:
    """Account slugs to iterate, from ECO_CLAUDE_ACCOUNTS env (csv)."""
    raw = os.environ.get("ECO_CLAUDE_ACCOUNTS", "primary")
    slugs = [s.strip().lower() for s in raw.split(",") if s.strip()]
    return slugs or ["primary"]


def _keychain_present_for(slug: str) -> bool:
    """Best-effort probe: does a per-slug Keychain entry exist?

    This is gated by discovery.server_truth_enabled("claude"). Default JSONL
    collection must not invoke macOS `security` or touch Keychain state.

    Convention probed: "Claude Code-credentials-<slug>". Claude Code today
    uses a single un-suffixed entry, so this returns False for every slug
    in current installs — that's the documented current state. If Anthropic
    later adds per-account suffixes, this picks them up without further
    code changes.
    """
    if not discovery.server_truth_enabled("claude"):
        return False

    import subprocess  # local import — keeps module-load cost off the hot path
    try:
        r = subprocess.run(
            ["security", "find-generic-password", "-s", f"Claude Code-credentials-{slug}"],
            capture_output=True, text=True, timeout=3, check=False,
        )
    except (FileNotFoundError, OSError):
        return False
    except Exception:
        return False
    return r.returncode == 0


def collect_multi() -> dict:
    """Aggregate + per-account view.

    Returns the same top-level keys as collect() (widget reads keep working)
    PLUS a per_account list:

        per_account: [
          {slug, plan, ok, source, note?, session?, weekly?},
          ...
        ]

    Today only the active account has real data; inactive slots carry
    ok=False with source="auth-not-present".
    """
    aggregate = collect()  # the existing single-account collector
    slugs = _account_slugs()
    per_account: list[dict] = []

    # The primary (first) slug owns the live JSONL data — the JSONL pool
    # is shared across accounts because Claude Code rewrites the same
    # ~/.claude/projects/ tree regardless of which account is logged in.
    primary_slug = slugs[0] if slugs else "primary"
    keychain_probe_enabled = discovery.server_truth_enabled("claude")

    for slug in slugs:
        has_suffixed_kc = (
            keychain_probe_enabled
            and slug != primary_slug
            and _keychain_present_for(slug)
        )

        if slug == primary_slug:
            # Active account: its JSONL is the data we already have.
            per_account.append({
                "slug": slug,
                "plan": UNKNOWN_PLAN,
                "ok": aggregate.get("ok", False),
                "source": aggregate.get("source", "jsonl"),
                "session": aggregate.get("session"),
                "weekly": aggregate.get("weekly"),
            })
        else:
            # Inactive slot. If a per-slug Keychain entry exists, future
            # work can OAuth-poll it. For now we expose the slot as
            # not-present so the UI can render "swap to this account".
            per_account.append({
                "slug": slug,
                "plan": UNKNOWN_PLAN,
                "ok": False,
                "source": "auth-not-present" if not has_suffixed_kc else "auth-suffixed",
                "note": (
                    "swap to this account to populate"
                    if not has_suffixed_kc
                    else "per-slug Keychain entry found — OAuth poll not yet wired"
                ),
            })

    aggregate["per_account"] = per_account
    return aggregate


if __name__ == "__main__":
    print(json.dumps(collect_multi(), indent=2))
