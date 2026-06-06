#!/usr/bin/env python3
"""
Usage poller entrypoint.

Runs every 60s under launchd. For each tool (Claude, Gemini, Codex):
  - calls collect()
  - writes ~/.eco/current/usage-<tool>.json (atomic)
Then merges all three into ~/.eco/current/usage.json (atomic).

Failures in one tool never block the others. Errors are surfaced in the
merged JSON so the SwiftBar renderer can show a per-tool warning badge.
"""
from __future__ import annotations

import json
import logging
import os
import re
import sys
import tempfile
import time
import traceback
from contextlib import suppress
from pathlib import Path
from typing import Any

logger = logging.getLogger("eco.poller")

# Allow `python -m poller.main` from src/ AND `python src/poller/main.py`
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from common.config import EcoConfig  # type: ignore
    from poller import (  # type: ignore
        accounts,
        alternatives,
        claude,
        claude_oauth,
        codex,
        codex_oauth,
        comments,
        discovery,
        gemini,
        notify,
        value,
    )
else:
    from common.config import EcoConfig

    from . import (
        accounts,
        alternatives,
        claude,
        claude_oauth,
        codex,
        codex_oauth,
        comments,
        discovery,
        gemini,
        notify,
        value,
    )


def _out_dir() -> Path:
    return EcoConfig.from_env().current_dir


def _atomic_write(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(data, fh, indent=2, sort_keys=True)
        os.replace(tmp, path)
        os.chmod(path, 0o600)
    except Exception:
        with suppress(OSError):
            os.unlink(tmp)
        raise


def _safe_collect(name: str, fn) -> dict:
    """Run a collector. NEVER let the exception detail land in usage.json —
    it's world-readable and exception strings can carry request URLs / bearer
    headers (P0 finding from W3 brutal auditor 2026-05-10).

    Public payload: only the exception class name. Sanitized traceback frames go
    to the private log file at ~/.eco/logs/poller.log (mode 0600).
    """
    try:
        payload: Any = fn()
        if isinstance(payload, dict):
            return payload
        return {"tool": name, "ok": False, "error": "InvalidCollectorPayload"}
    except Exception as exc:
        _log_private(name, exc)
        exc_name = re.sub(r"[^\w]", "", type(exc).__name__) or "Error"
        return {
            "tool": name,
            "ok": False,
            "source": "error",
            "error": exc_name,   # NO message — could leak token in URL
        }


def _sanitize_traceback_filename(filename: str) -> str:
    return re.sub(r"/Users/[^/]+", "~", str(filename))


def _log_private(tool: str, exc: BaseException) -> None:
    """Append sanitized traceback frames to a 0600-mode private log; never to JSON."""
    log_dir = EcoConfig.from_env().log_dir
    log_path = log_dir / "poller.log"
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        # Create with restrictive perms if missing.
        if not log_path.exists():
            log_path.touch(mode=0o600)
        else:
            with suppress(OSError):
                os.chmod(log_path, 0o600)
        with log_path.open("a", encoding="utf-8") as fh:
            ts = time.strftime("%Y-%m-%dT%H:%M:%S")
            fh.write(f"[{ts}] {tool}: {type(exc).__name__}\n")
            for frame in traceback.extract_tb(exc.__traceback__, limit=5):
                filename = _sanitize_traceback_filename(frame.filename)
                fh.write(f'  File "{filename}", line {frame.lineno}, in {frame.name}\n')
            fh.write("\n")
    except OSError:
        # If we can't write the log, swallow — better than crashing the poller.
        pass


def _pick_collector(tool: str, oauth_fn, jsonl_fn, prev_usage=None):
    """If user opted into server-truth and the OAuth call works, use it.
    Else fall back to JSONL parser. Default OFF — silent on first OSS install.

    Transient OAuth failure (429 rate-limit, network, TLS) reuses the
    previous cycle's OAuth result if one is available — jsonl-estimate
    has its own calibration drift and is worse than a 60s-stale truth.
    """
    if not discovery.server_truth_enabled(tool):
        return _safe_collect(tool, jsonl_fn)
    oauth_result = _safe_collect(tool, oauth_fn)
    if oauth_result.get("ok"):
        return oauth_result

    # OAuth failed. If the failure is transient AND we have a prior OAuth
    # snapshot, reuse it rather than degrading to jsonl-estimate.
    err = str(oauth_result.get("error_code") or oauth_result.get("error", ""))
    transient = err.startswith("http_5") or err in {"http_429", "network", "tls_failure"}
    if transient and prev_usage:
        prev_tool = prev_usage.get(tool) or {}
        if prev_tool.get("ok") and prev_tool.get("source") == "api":
            prev_tool = dict(prev_tool)
            prev_tool["stale"] = True
            prev_tool["stale_reason"] = err
            return prev_tool

    # No prior OAuth or non-transient failure — fall back to JSONL.
    fallback = _safe_collect(tool, jsonl_fn)
    fallback["oauth_fallback_reason"] = oauth_result.get("error", "unknown")
    return fallback


def _load_prev_usage() -> dict | None:
    """Load the previous cycle's usage.json so comments can compute deltas."""
    path = _out_dir() / "usage.json"
    if not path.exists():
        return None
    try:
        payload: Any = json.loads(path.read_text(encoding="utf-8"))
        return payload if isinstance(payload, dict) else None
    except (OSError, json.JSONDecodeError):
        return None


def _augment_claude_with_jsonl(claude_payload: dict) -> dict:
    """Ensure per_account[] and token-level breakdown are present on Claude.

    When OAuth wins, the payload has %-only meters and no per_account.
    The widget needs per_account to render the multi-account selector;
    value.py needs token counts to price usage. We run the JSONL collector
    once and graft the missing fields on without overwriting OAuth's
    authoritative pct values.
    """
    if not isinstance(claude_payload, dict):
        return claude_payload
    if "per_account" in claude_payload and "input_tokens" in (claude_payload.get("weekly") or {}):
        return claude_payload  # nothing to do — JSONL already won this cycle

    jsonl_truth = _safe_collect("claude_jsonl_aux", claude.collect_multi)
    if not jsonl_truth.get("ok"):
        # Even if JSONL bombs, still emit an empty per_account so the
        # widget can render a "no data" pill instead of crashing.
        claude_payload.setdefault("per_account", [])
        return claude_payload

    claude_payload.setdefault("per_account", jsonl_truth.get("per_account", []))

    for window in ("session", "weekly"):
        jw = jsonl_truth.get(window) or {}
        ow = claude_payload.get(window) or {}
        for tk in ("input_tokens", "output_tokens",
                   "cache_creation_tokens", "cache_read_tokens",
                   "by_model"):
            if tk in jw and tk not in ow:
                ow[tk] = jw[tk]
        claude_payload[window] = ow
    return claude_payload


def _augment_codex_with_jsonl(codex_payload: dict) -> dict:
    """Graft token detail onto Codex OAuth pct truth when available.

    The OpenAI backend usage endpoint is authoritative for percentages and
    reset windows, but it can be pct-only. JSONL gives token splits for local
    work, so we add those fields without changing source="api".
    """
    if not isinstance(codex_payload, dict):
        return codex_payload
    if "input_tokens" in (codex_payload.get("weekly") or {}):
        return codex_payload

    jsonl_truth = _safe_collect("codex_jsonl_aux", codex.collect)
    if not jsonl_truth.get("ok"):
        return codex_payload

    for window in ("session", "weekly"):
        jw = jsonl_truth.get(window) or {}
        ow = codex_payload.get(window) or {}
        for tk in ("tokens", "input_tokens", "output_tokens",
                   "cached_input_tokens", "reasoning_output_tokens",
                   "cap", "by_model"):
            if tk in jw and tk not in ow:
                ow[tk] = jw[tk]
        if jw:
            ow.setdefault("token_estimate_source", "jsonl")
        codex_payload[window] = ow
    codex_payload.setdefault("usage_estimate_source", "jsonl")
    return codex_payload


def main() -> int:
    started = time.time()
    prev_usage = _load_prev_usage()
    # Stream-B: claude.collect_multi adds a per_account[] array on top of
    # the existing collect() output. Falls back to single-account collect()
    # via _pick_collector's existing JSONL path on OAuth opt-in.
    results = {
        "claude": _pick_collector("claude", claude_oauth.collect, claude.collect_multi, prev_usage),
        "gemini": _safe_collect("gemini", gemini.collect),
        "codex":  _pick_collector("codex",  codex_oauth.collect,  codex.collect, prev_usage),
    }

    # Stream-B: when OAuth wins for Claude, graft per_account + token
    # breakdown from a JSONL pass so the widget + value.py have what
    # they need without sacrificing OAuth pct accuracy.
    results["claude"] = _augment_claude_with_jsonl(results["claude"])
    results["codex"] = _augment_codex_with_jsonl(results["codex"])

    # Stamp configured plan/account context onto each tool's payload without
    # discarding collector-provided detected account counts.
    for tool in ("claude", "gemini", "codex"):
        if isinstance(results.get(tool), dict):
            results[tool] = accounts.stamp(results[tool], tool)

    # Per-tool atomic writes (preserved — widget reads usage-<tool>.json too).
    for tool, payload in results.items():
        _atomic_write(_out_dir() / f"usage-{tool}.json", payload)

    # Collect alternatives BEFORE the single merged write (T4 fix #1 —
    # avoids the race window where SwiftBar reads usage.json missing
    # the alternatives key).
    alternatives_block = _safe_collect("alternatives", alternatives.collect)

    merged = {
        "ts": int(started),
        "duration_ms": int((time.time() - started) * 1000),
        "version": 1,
        **results,
        "alternatives": alternatives_block,
    }

    # Stream-B: stamp the API-equivalent USD value block. Wrapped in
    # _safe_collect so a pricing/schema bug never breaks the poller.
    merged["value"] = _safe_collect("value", lambda: value.compute(merged))

    # Burn-rate comment (default OFF — gated by ECO_COMMENTS=1).
    # State persisted in notify.json so we share the cooldown clock.
    if os.environ.get("ECO_COMMENTS", "0") == "1":
        try:
            state_path = EcoConfig.from_env().state_dir / "notify.json"
            state = {}
            if state_path.exists():
                try:
                    state = json.loads(state_path.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError):
                    state = {}
            comment = comments.evaluate(merged, prev_usage, state)
            if comment:
                merged["comment"] = comment
                state_path.parent.mkdir(parents=True, exist_ok=True)
                _atomic_write(state_path, state)
        except Exception as exc:
            logger.warning(f"comments failed (non-fatal): {type(exc).__name__}")

    _atomic_write(_out_dir() / "usage.json", merged)

    # Notify AFTER the write so a slow / hung osascript can't delay
    # widget reads. Wrapped in try/except so a notify bug never breaks
    # the poller.
    try:
        notify_result = notify.evaluate(merged)
        if notify_result.get("fired"):
            logger.info(f"notify: fired {len(notify_result['fired'])} notifications")
    except Exception as exc:
        logger.warning(f"notify failed (non-fatal): {type(exc).__name__}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
