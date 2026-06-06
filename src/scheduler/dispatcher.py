"""Single-pass scheduler tick — invoked by launchd every 2 min.

Reads ~/.eco/state/notify.json + ~/.eco/queue/jobs.yaml, walks each pending
job's model_preference ladder, fires via the first adapter whose meter is
available, records outcome, persists state. Then exits.

NOT a long-running daemon. launchd is the cron.
"""

from __future__ import annotations

import fcntl
import json
import logging
import os
import sys
import time
from contextlib import contextmanager, suppress
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


from scheduler.adapters import get_adapter
from scheduler.adapters.base import AdapterResult, sanitize_note
from scheduler.queue import (
    DEFAULT_QUEUE_PATH,
    DEFAULT_RESULTS_DIR,
    Attempt,
    Job,
    QueueLoadError,
    load_queue,
    pending_ready_jobs,
    save_queue,
    validate_timeout_s,
)
from scheduler.routing import pick_candidate

logger = logging.getLogger("eco.scheduler")

try:
    from common.config import EcoConfig
except ImportError:
    EcoConfig = None  # type: ignore[assignment,misc]

ECO_HOME = Path(os.environ.get("ECO_HOME", str(Path.home() / ".eco")))
STATE_PATH = ECO_HOME / "state" / "notify.json"  # legacy fallback for callers that patch it directly
DEFAULT_RETRY_MAX = 3
MAX_RETRY_MAX = 100
DEFAULT_RETRY_BACKOFF_S = (60, 300, 1800)
MAX_RETRY_BACKOFF_S = 86400


def _state_path() -> Path:
    if EcoConfig is not None:
        return EcoConfig.from_env().state_dir / "notify.json"
    return Path(os.environ.get("ECO_HOME", str(Path.home() / ".eco"))) / "state" / "notify.json"


def _load_state() -> dict:
    path = _state_path()
    if not path.exists():
        return {"meters": {}}
    try:
        payload: Any = json.loads(path.read_text(encoding="utf-8"))
        return payload if isinstance(payload, dict) else {"meters": {}}
    except (OSError, json.JSONDecodeError):
        return {"meters": {}}


def _save_state(state: dict) -> None:
    """Atomic write of state back to notify.json."""
    import tempfile
    path = _state_path()
    tmp = ""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(state, fh, indent=2, sort_keys=True)
        os.replace(tmp, path)
    except OSError:
        if tmp:
            with suppress(OSError):
                os.unlink(tmp)
        raise


def _coerce_positive_int(value: Any, name: str) -> int:
    if isinstance(value, bool):
        raise ValueError(f"{name} must be an integer >= 1")
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be an integer >= 1") from exc
    if parsed < 1:
        raise ValueError(f"{name} must be an integer >= 1")
    return parsed


def _stamp_meter_fire(state: dict, meter_key: str, now: float) -> None:
    """Record that the scheduler fired a job on this meter.

    Writes ``last_fired_ts`` into the meter's state so routing.py's
    throttle cooldown uses the actual dispatch time, not just the
    notify.py notification delivery time.
    """
    meters = state.setdefault("meters", {})
    m = meters.setdefault(meter_key, {})
    m["last_fired_ts"] = int(now)
    _save_state(state)


def _now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _with_note(message: str, note: str) -> str:
    return f"{message}: {note}" if note else message


def _safe_retry_max(retry: Any) -> int:
    if not isinstance(retry, dict):
        return DEFAULT_RETRY_MAX
    value = retry.get("max", DEFAULT_RETRY_MAX)
    if isinstance(value, bool):
        return DEFAULT_RETRY_MAX
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return DEFAULT_RETRY_MAX
    if parsed < 1:
        return DEFAULT_RETRY_MAX
    return min(parsed, MAX_RETRY_MAX)


def _safe_retry_backoff_s(retry: Any, attempt_number: int) -> int:
    if isinstance(retry, dict):
        raw_backoff = retry.get("backoff_s", DEFAULT_RETRY_BACKOFF_S)
    else:
        raw_backoff = DEFAULT_RETRY_BACKOFF_S
    if isinstance(raw_backoff, str | bytes) or not isinstance(raw_backoff, list | tuple):
        raw_items = [raw_backoff]
    else:
        raw_items = list(raw_backoff)

    backoffs: list[int] = []
    for raw in raw_items:
        if isinstance(raw, bool):
            continue
        try:
            parsed = int(raw)
        except (TypeError, ValueError):
            continue
        if parsed < 0:
            continue
        backoffs.append(min(parsed, MAX_RETRY_BACKOFF_S))
    if not backoffs:
        backoffs = list(DEFAULT_RETRY_BACKOFF_S)

    index = max(0, min(max(attempt_number, 1) - 1, len(backoffs) - 1))
    return backoffs[index]


def _iso_after(backoff_s: int, now: datetime | None = None) -> str:
    base = now or datetime.now(timezone.utc).astimezone()
    return (base + timedelta(seconds=backoff_s)).isoformat(timespec="seconds")


def _meter_float(value: Any) -> float:
    if isinstance(value, bool):
        return 0.0
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _stamp_meter_result(state: dict, meter_key: str, result: AdapterResult, now: float, backoff_s: int = 0) -> None:
    """Record dispatch and quota feedback in the meter state routing reads."""
    meters = state.setdefault("meters", {})
    if not isinstance(meters, dict):
        meters = {}
        state["meters"] = meters
    m = meters.setdefault(meter_key, {})
    if not isinstance(m, dict):
        m = {}
        meters[meter_key] = m
    m["last_fired_ts"] = int(now)
    if result.error_kind in {"hard_wall", "throttle"}:
        m["last_kind"] = result.error_kind
    if result.error_kind == "hard_wall":
        reset_epoch = _meter_float(m.get("last_reset_epoch", 0.0))
        if reset_epoch <= now:
            m["last_reset_epoch"] = int(now + max(backoff_s, 0))
    _save_state(state)


@contextmanager
def _scheduler_tick_lock(queue_path: Path):
    """Serialize whole ticks so two launchd invocations cannot claim the same job."""
    if sys.platform == "win32":
        yield
        return
    lock = queue_path.with_suffix(queue_path.suffix + ".tick.lock")
    lock.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(lock), os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _reset_stale_running(jobs: list[Job], grace_s: int = 60) -> int:
    """Reset jobs stuck in 'running' past their timeout back to 'pending'.

    A scheduler tick that was SIGKILLed mid-fire leaves a job at 'running'
    with no completing tick. Without this, the job is unreachable —
    pending_ready_jobs filters status != 'pending'.

    Returns count of jobs reset.
    """
    now = time.time()
    reset_count = 0
    for j in jobs:
        if j.status != "running":
            continue
        if not j.started_iso:
            continue
        try:
            started = datetime.fromisoformat(j.started_iso).timestamp()
        except ValueError:
            continue
        try:
            timeout = max(validate_timeout_s(j.timeout_s), 60)
        except ValueError:
            timeout = 600
        if (now - started) > (timeout + grace_s):
            j.status = "pending"
            j.last_error = f"reset_stale_running: was 'running' for {int(now-started)}s (timeout {timeout}s)"
            reset_count += 1
    return reset_count


def _tick_unlocked(
    queue_path: Path | None = None,
    log_dir: Path | None = None,
    max_jobs_per_tick: int = 1,
    state: dict | None = None,
) -> dict:
    """One scheduler pass. Returns a summary dict."""
    queue_path = queue_path or DEFAULT_QUEUE_PATH
    log_dir = log_dir or DEFAULT_RESULTS_DIR
    max_jobs_per_tick = _coerce_positive_int(max_jobs_per_tick, "max_jobs_per_tick")
    state = state if state is not None else _load_state()

    jobs = load_queue(queue_path)
    stale_reset = _reset_stale_running(jobs)
    if stale_reset:
        save_queue(jobs, queue_path)
    ready = pending_ready_jobs(jobs)
    if any(j.status == "failed" and j.last_error.startswith("invalid earliest_iso") for j in jobs):
        save_queue(jobs, queue_path)

    summary: dict[str, Any] = {
        "tick_iso": _now_iso(),
        "total_jobs": len(jobs),
        "pending": sum(1 for j in jobs if j.status == "pending"),
        "running": sum(1 for j in jobs if j.status == "running"),
        "completed": sum(1 for j in jobs if j.status == "completed"),
        "failed": sum(1 for j in jobs if j.status == "failed"),
        "ready_now": len(ready),
        "fired": [],
        "gated": [],
    }

    fired_count = 0
    for job in ready:
        if fired_count >= max_jobs_per_tick:
            break
        if job.requires_confirm:
            summary["gated"].append({"id": job.id, "reason": "requires_confirm"})
            continue

        choice = pick_candidate(job.model_preference, state)
        if choice.candidate is None:
            summary["gated"].append(
                {
                    "id": job.id,
                    "reason": "all_meters_blocked",
                    "next_available_in_s": choice.next_available_in_s,
                    "skipped": choice.skipped,
                }
            )
            # Update job status (do NOT mark failed — re-eligible next tick)
            job.status = "gated_by_quota"
            job.last_error = f"all_meters_blocked; next in {choice.next_available_in_s}s"
            for i, j in enumerate(jobs):
                if j.id == job.id:
                    jobs[i] = job
                    break
            save_queue(jobs, queue_path)
            continue

        provider = choice.candidate["provider"]
        try:
            adapter = get_adapter(provider)
        except ValueError as exc:
            failure_note = sanitize_note(str(exc), limit=300)
            job.status = "failed"
            job.last_error = _with_note(f"unknown provider: {provider}", failure_note)
            job.completed_iso = _now_iso()
            attempt = Attempt(
                iso=_now_iso(),
                provider=provider,
                model=choice.candidate.get("model", ""),
                meter=choice.candidate.get("meter", ""),
                ok=False,
                error_kind="io_error",
            )
            job.attempts.append(attempt)
            for i, j in enumerate(jobs):
                if j.id == job.id:
                    jobs[i] = job
                    break
            save_queue(jobs, queue_path)
            fired_summary = {
                "id": job.id,
                "provider": provider,
                "model": choice.candidate.get("model", ""),
                "ok": False,
                "error_kind": "io_error",
                "duration_s": 0.0,
                "status_after": job.status,
                "last_error": job.last_error,
            }
            if failure_note:
                fired_summary["notes"] = failure_note
            summary["fired"].append(fired_summary)
            fired_count += 1
            continue

        # Mark running, persist before firing (crash safety)
        job.status = "running"
        job.started_iso = _now_iso()
        for i, j in enumerate(jobs):
            if j.id == job.id:
                jobs[i] = job
                break
        save_queue(jobs, queue_path)

        logger.info(f"firing {job.id} via {provider}/{choice.candidate.get('model')}")
        result: AdapterResult = adapter.fire(job, choice.candidate, str(log_dir))

        attempt = Attempt(
            iso=_now_iso(),
            provider=provider,
            model=choice.candidate.get("model", ""),
            meter=choice.candidate.get("meter", ""),
            ok=result.ok,
            error_kind=result.error_kind,
            duration_s=result.duration_s,
            log_path=result.stdout_path,
        )
        job.attempts.append(attempt)
        failure_note = sanitize_note(result.notes, limit=300) if not result.ok else ""
        non_wall_attempts = sum(1 for a in job.attempts if a.error_kind != "hard_wall")
        wall_attempts = sum(1 for a in job.attempts if a.error_kind == "hard_wall")
        retry_attempt_number = wall_attempts if result.error_kind == "hard_wall" else non_wall_attempts
        retry_backoff_s = _safe_retry_backoff_s(job.retry, retry_attempt_number)

        # Stamp dispatch and quota feedback into notify.json so routing.py sees
        # throttle and hard-wall outcomes on the next ladder walk.
        #
        # Known v0.x limitation: the queue tick lock serializes dispatcher
        # instances, but this notify.json read-modify-write still shares state
        # with src/poller/notify.py without a cross-process notify-state lock.
        meter_key = choice.candidate.get("meter", "")
        state_error = ""
        if meter_key:
            try:
                _stamp_meter_result(state, meter_key, result, time.time(), retry_backoff_s)
            except OSError as exc:
                state_error = sanitize_note(f"state write failed: {exc}", limit=300)

        if result.ok:
            job.status = "completed"
            job.completed_iso = _now_iso()
            job.last_error = ""
        else:
            # If hard_wall, leave job pending so it re-tries next reset window
            # AND don't count it against retry.max (quota-walls are not the job's fault).
            max_retry = _safe_retry_max(job.retry)
            if result.error_kind == "hard_wall":
                job.status = "pending"
                job.earliest_iso = _iso_after(retry_backoff_s)
                job.last_error = _with_note(
                    f"hard_wall on {choice.candidate.get('meter')}; will retry after {retry_backoff_s}s",
                    failure_note,
                )
            elif non_wall_attempts >= max_retry:
                job.status = "failed"
                job.completed_iso = _now_iso()
                job.last_error = _with_note(result.error_kind or "unknown", failure_note)
            else:
                job.status = "pending"
                job.earliest_iso = _iso_after(retry_backoff_s)
                job.last_error = _with_note(
                    f"{result.error_kind} (attempt {non_wall_attempts}/{max_retry}); retry after {retry_backoff_s}s",
                    failure_note,
                )

        # Persist after each fire
        for i, j in enumerate(jobs):
            if j.id == job.id:
                jobs[i] = job
                break
        save_queue(jobs, queue_path)

        fired_summary = {
            "id": job.id,
            "provider": provider,
            "model": choice.candidate.get("model", ""),
            "ok": result.ok,
            "error_kind": result.error_kind,
            "duration_s": round(result.duration_s, 2),
            "status_after": job.status,
        }
        if not result.ok:
            fired_summary["last_error"] = job.last_error
            if failure_note:
                fired_summary["notes"] = failure_note
        if state_error:
            fired_summary["state_error"] = state_error
            summary.setdefault("errors", []).append(
                {"id": job.id, "error_kind": "io_error", "message": state_error}
            )
        summary["fired"].append(fired_summary)
        fired_count += 1

    return summary


def tick(
    queue_path: Path | None = None,
    log_dir: Path | None = None,
    max_jobs_per_tick: int = 1,
    state: dict | None = None,
) -> dict:
    """One scheduler pass under a process-wide tick lock for this queue."""
    queue_path = queue_path or DEFAULT_QUEUE_PATH
    with _scheduler_tick_lock(queue_path):
        return _tick_unlocked(
            queue_path=queue_path,
            log_dir=log_dir,
            max_jobs_per_tick=max_jobs_per_tick,
            state=state,
        )


def _summary_has_failed_attempt(summary: dict[str, Any]) -> bool:
    return bool(summary.get("errors")) or any(not fired.get("ok", False) for fired in summary.get("fired", []))


def main() -> int:
    logging.basicConfig(
        level=os.environ.get("ECO_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )
    try:
        max_jobs = _coerce_positive_int(os.environ.get("ECO_MAX_JOBS_PER_TICK", "1"), "ECO_MAX_JOBS_PER_TICK")
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    try:
        summary = tick(max_jobs_per_tick=max_jobs)
    except QueueLoadError as exc:
        print(f"error: cannot load scheduler queue: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(summary, indent=2, sort_keys=False))
    return 1 if _summary_has_failed_attempt(summary) else 0


if __name__ == "__main__":
    raise SystemExit(main())
