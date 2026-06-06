"""eco-scheduler CLI surface — `python -m scheduler.cli <subcmd>`.

Subcommands:
    status      Pretty-print queue + meter state
    add         Append a job from YAML file or inline args
    run-once    One tick; print summary JSON
    tail        Watch the last completed job's stdout log
    drain       Run ticks until no ready jobs remain (or N ticks max)
    seed        Import per-project mission yaml files into the queue
    cancel      Cancel a pending or gated job by id
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from scheduler.dispatcher import _load_state, tick
    from scheduler.queue import (
        DEFAULT_QUEUE_PATH,
        DEFAULT_RESULTS_DIR,
        Job,
        QueueLoadError,
        add_jobs,
        load_queue,
        safe_log_path,
        save_queue,
    )
    from scheduler.routing import meter_status
else:
    from .dispatcher import _load_state, tick
    from .queue import (
        DEFAULT_QUEUE_PATH,
        DEFAULT_RESULTS_DIR,
        Job,
        QueueLoadError,
        add_jobs,
        load_queue,
        safe_log_path,
        save_queue,
    )
    from .routing import meter_status


def _path_inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def _cmd_add_error(path: Path, reason: str) -> int:
    print(f"error: {path}: {reason}", file=sys.stderr)
    return 2


def _cmd_queue_load_error(exc: QueueLoadError) -> int:
    print(f"error: cannot load scheduler queue: {exc}", file=sys.stderr)
    return 2


def _summary_has_failed_attempt(summary: dict[str, Any]) -> bool:
    return bool(summary.get("errors")) or any(not fired.get("ok", False) for fired in summary.get("fired", []))


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


def _coerce_non_negative_int(value: Any, name: str) -> int:
    if isinstance(value, bool):
        raise ValueError(f"{name} must be an integer >= 0")
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be an integer >= 0") from exc
    if parsed < 0:
        raise ValueError(f"{name} must be an integer >= 0")
    return parsed


def _arg_positive_int(value: str) -> int:
    try:
        return _coerce_positive_int(value, "value")
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc


def _arg_non_negative_int(value: str) -> int:
    try:
        return _coerce_non_negative_int(value, "value")
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc


def cmd_status(args: argparse.Namespace) -> int:
    state = _load_state()
    try:
        jobs = load_queue()
    except QueueLoadError as exc:
        return _cmd_queue_load_error(exc)

    if args.json:
        meters = {k: vars(meter_status(state, k)) for k in state.get("meters", {})}
        out: dict[str, Any] = {
            "queue_path": str(DEFAULT_QUEUE_PATH),
            "total_jobs": len(jobs),
            "by_status": {},
            "meters": meters,
            "next_pending": [],
        }
        for j in jobs:
            out["by_status"][j.status] = out["by_status"].get(j.status, 0) + 1
        for j in jobs[:5]:
            if j.status in ("pending", "gated_by_quota"):
                out["next_pending"].append({
                    "id": j.id,
                    "priority": j.priority,
                    "earliest_iso": j.earliest_iso,
                    "providers": [r.get("provider") for r in j.model_preference],
                })
        print(json.dumps(out, indent=2))
        return 0

    print(f"━━━ eco-scheduler status @ {datetime.now(timezone.utc).isoformat(timespec='seconds')} ━━━")
    print(f"queue: {DEFAULT_QUEUE_PATH}")
    print()
    print(f"Jobs ({len(jobs)} total):")
    counts: dict[str, int] = {}
    for j in jobs:
        counts[j.status] = counts.get(j.status, 0) + 1
    for s in ("pending", "running", "completed", "failed", "gated_by_quota", "cancelled"):
        if counts.get(s, 0):
            print(f"  {s:18s} {counts[s]}")
    print()
    print("Meters:")
    for k in sorted(state.get("meters", {})):
        st = meter_status(state, k)
        flag = "✅" if st.available else "🔒"
        wait_s = st.seconds_until_available
        wait_str = "" if wait_s == 0 else f" (in {wait_s//60}m {wait_s%60}s)"
        print(f"  {flag} {k:30s} {st.kind:18s}{wait_str}")
    print()
    print("Next pending jobs (top 5):")
    pendings = [j for j in jobs if j.status in ("pending", "gated_by_quota")][:5]
    if not pendings:
        print("  (none)")
    for j in pendings:
        providers = "/".join(r.get("provider", "?") for r in j.model_preference)
        print(f"  [{j.priority}] {j.id:30s} -> {providers}  (earliest {j.earliest_iso or 'now'})")
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    if args.file:
        input_path = Path(args.file)
        try:
            raw = input_path.read_text(encoding="utf-8")
            data = yaml.safe_load(raw) or {}
        except FileNotFoundError:
            return _cmd_add_error(input_path, "file not found")
        except OSError as exc:
            return _cmd_add_error(input_path, exc.strerror or str(exc))
        except yaml.YAMLError as exc:
            return _cmd_add_error(input_path, f"invalid YAML: {exc}")
        jobs_raw = data.get("jobs", []) if isinstance(data, dict) else data
        if not isinstance(jobs_raw, list):
            return _cmd_add_error(input_path, "YAML must contain a list of jobs or a {jobs: [...]} root")
        new_jobs = []
        for idx, job_raw in enumerate(jobs_raw):
            try:
                new_jobs.append(Job.from_dict(job_raw))
            except (TypeError, ValueError) as exc:
                return _cmd_add_error(input_path, f"jobs[{idx}]: {exc}")
    else:
        print("error: --file is required (inline mode not yet implemented)", file=sys.stderr)
        return 2

    try:
        added = add_jobs(new_jobs)
    except QueueLoadError as exc:
        return _cmd_add_error(exc.path, exc.reason)
    except OSError as exc:
        return _cmd_add_error(DEFAULT_QUEUE_PATH, exc.strerror or str(exc))
    print(f"✅ added {added} new job(s); {len(new_jobs) - added} skipped (id already in queue)")
    return 0


def cmd_run_once(args: argparse.Namespace) -> int:
    try:
        max_jobs = _coerce_positive_int(args.max_jobs, "--max-jobs")
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    try:
        summary = tick(max_jobs_per_tick=max_jobs)
    except QueueLoadError as exc:
        return _cmd_queue_load_error(exc)
    print(json.dumps(summary, indent=2))
    return 1 if _summary_has_failed_attempt(summary) else 0


def cmd_drain(args: argparse.Namespace) -> int:
    try:
        max_ticks = _coerce_positive_int(args.max_ticks, "--max-ticks")
        interval_s = _coerce_non_negative_int(args.interval_s, "--interval-s")
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    for i in range(max_ticks):
        try:
            summary = tick(max_jobs_per_tick=1)
        except QueueLoadError as exc:
            return _cmd_queue_load_error(exc)
        print(f"--- tick {i+1}/{max_ticks} ---")
        print(json.dumps(summary, indent=2))
        if _summary_has_failed_attempt(summary):
            print("error: scheduler attempt failed; see summary above", file=sys.stderr)
            return 1
        if not summary["fired"] and not summary.get("gated"):
            print("queue idle; exit")
            return 0
        if not summary["fired"]:
            # all remaining jobs gated by quota — bail
            print("all remaining jobs gated; exit")
            return 0
        if interval_s > 0:
            time.sleep(interval_s)
    return 0


def cmd_tail(args: argparse.Namespace) -> int:
    try:
        jobs = load_queue()
    except QueueLoadError as exc:
        return _cmd_queue_load_error(exc)
    target = None
    if args.id:
        target = next((j for j in jobs if j.id == args.id), None)
    else:
        # most recent attempt
        recent = sorted(
            (j for j in jobs if j.attempts),
            key=lambda j: j.attempts[-1].iso,
            reverse=True,
        )
        target = recent[0] if recent else None
    if not target or not target.attempts:
        print("no jobs with attempts found", file=sys.stderr)
        return 1
    attempt = target.attempts[-1]
    try:
        default_log_path = safe_log_path(DEFAULT_RESULTS_DIR, target.id, attempt.provider, "stdout")
    except ValueError as exc:
        print(f"unsafe scheduler log path: {exc}", file=sys.stderr)
        return 1
    if attempt.log_path:
        stored = Path(attempt.log_path).expanduser()
        try:
            root = DEFAULT_RESULTS_DIR.expanduser().resolve()
            stored_resolved = stored.resolve()
        except OSError as exc:
            print(f"unsafe stored log path: {exc}", file=sys.stderr)
            return 1
        if not _path_inside(stored_resolved, root):
            print(f"refusing log path outside scheduler log dir: {stored_resolved}", file=sys.stderr)
            return 1
        log_path = stored_resolved
    else:
        log_path = default_log_path
    if not log_path.exists():
        print(f"log not found: {log_path}", file=sys.stderr)
        return 1
    print(log_path.read_text(encoding="utf-8", errors="replace"))
    return 0


def cmd_seed(args: argparse.Namespace) -> int:
    """Scan a directory for mission YAML files and import all jobs."""
    seed_dir = Path(args.dir).expanduser().resolve()
    if not seed_dir.is_dir():
        print(f"error: {seed_dir} is not a directory", file=sys.stderr)
        return 2

    yaml_files = sorted(seed_dir.glob("*.yaml")) + sorted(seed_dir.glob("*.yml"))
    if not yaml_files:
        print(f"no .yaml/.yml files found in {seed_dir}", file=sys.stderr)
        return 1

    total_added = 0
    total_skipped = 0
    total_invalid = 0
    for yf in yaml_files:
        try:
            raw = yf.read_text(encoding="utf-8")
            data = yaml.safe_load(raw) or {}
        except (OSError, yaml.YAMLError) as exc:
            print(f"  ⚠️  {yf.name}: parse error ({exc})", file=sys.stderr)
            total_invalid += 1
            continue

        jobs_raw = data.get("jobs", []) if isinstance(data, dict) else data
        if not isinstance(jobs_raw, list):
            print(f"  ⚠️  {yf.name}: no jobs list found", file=sys.stderr)
            total_invalid += 1
            continue

        new_jobs = []
        for idx, j in enumerate(jobs_raw):
            try:
                new_jobs.append(Job.from_dict(j))
            except (TypeError, KeyError, ValueError) as exc:
                total_invalid += 1
                print(f"  ⚠️  {yf.name}: bad job entry {idx} ({exc})", file=sys.stderr)

        if new_jobs:
            try:
                added = add_jobs(new_jobs)
            except QueueLoadError as exc:
                return _cmd_queue_load_error(exc)
            skipped = len(new_jobs) - added
            total_added += added
            total_skipped += skipped
            print(f"  ✅ {yf.name}: {added} added, {skipped} skipped")
        else:
            print(f"  ⏭️  {yf.name}: no valid jobs")

    print(
        f"\nSeed complete: {total_added} job(s) added, "
        f"{total_skipped} skipped (already in queue), {total_invalid} invalid"
    )
    return 1 if total_invalid else 0


def cmd_cancel(args: argparse.Namespace) -> int:
    """Cancel a pending or gated job by id."""
    try:
        jobs = load_queue()
    except QueueLoadError as exc:
        return _cmd_queue_load_error(exc)
    target = next((j for j in jobs if j.id == args.id), None)
    if not target:
        print(f"error: job '{args.id}' not found in queue", file=sys.stderr)
        return 1

    if target.status not in ("pending", "gated_by_quota") and not args.force:
        print(
            f"error: job '{args.id}' has status '{target.status}' — "
            f"use --force to cancel anyway",
            file=sys.stderr,
        )
        return 1

    previous_status = target.status
    target.status = "cancelled"
    save_queue(jobs)
    print(f"✅ cancelled job '{args.id}' (was: {previous_status})")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="eco-scheduler")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_status = sub.add_parser("status", help="show queue + meter state")
    p_status.add_argument("--json", action="store_true")
    p_status.set_defaults(func=cmd_status)

    p_add = sub.add_parser("add", help="append jobs from a YAML file")
    p_add.add_argument("--file", "-f", required=True, help="YAML file containing jobs")
    p_add.set_defaults(func=cmd_add)

    p_ro = sub.add_parser("run-once", help="one scheduler tick")
    p_ro.add_argument("--max-jobs", type=_arg_positive_int, default=1)
    p_ro.set_defaults(func=cmd_run_once)

    p_dr = sub.add_parser("drain", help="run ticks until queue idle or N ticks")
    p_dr.add_argument("--max-ticks", type=_arg_positive_int, default=10)
    p_dr.add_argument("--interval-s", type=_arg_non_negative_int, default=0)
    p_dr.set_defaults(func=cmd_drain)

    p_tail = sub.add_parser("tail", help="print most recent attempt log")
    p_tail.add_argument("--id", help="specific job id (default: latest attempt)")
    p_tail.set_defaults(func=cmd_tail)

    p_seed = sub.add_parser("seed", help="import mission YAML files from a directory")
    p_seed.add_argument("--dir", "-d", required=True, help="directory containing mission .yaml files")
    p_seed.set_defaults(func=cmd_seed)

    p_cancel = sub.add_parser("cancel", help="cancel a pending or gated job")
    p_cancel.add_argument("id", help="job id to cancel")
    p_cancel.add_argument("--force", action="store_true", help="cancel even if not pending/gated")
    p_cancel.set_defaults(func=cmd_cancel)

    args = p.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
