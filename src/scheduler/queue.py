"""YAML-backed job queue at ~/.eco/queue/jobs.yaml.

Atomic writes (tempfile + os.replace), POSIX flock for concurrency safety.
Schema is gem-swarm `missions:` compatible with these additions:
    - project, workdir, template, template_vars
    - model_preference (ladder of {provider, model, meter} dicts)
    - earliest_iso, priority, timeout_s, retry
    - status, attempts, created_iso, started_iso, completed_iso, last_error
"""

from __future__ import annotations

import fcntl
import os
import re
import stat
import sys
import tempfile
import time
from contextlib import contextmanager, suppress
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

try:
    from common.config import EcoConfig as _EcoConfig
    DEFAULT_QUEUE_PATH = _EcoConfig.from_env().queue_dir / "jobs.yaml"
    DEFAULT_RESULTS_DIR = _EcoConfig.from_env().queue_dir / "logs"
except ImportError:
    DEFAULT_QUEUE_PATH = Path(os.environ.get("ECO_HOME", str(Path.home() / ".eco"))) / "queue" / "jobs.yaml"
    DEFAULT_RESULTS_DIR = Path(os.environ.get("ECO_HOME", str(Path.home() / ".eco"))) / "queue" / "logs"

JobStatus = str  # pending | running | completed | failed | gated_by_quota | cancelled
SAFE_JOB_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
SAFE_LOG_PART_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
MIN_TIMEOUT_S = 1
MAX_TIMEOUT_S = 21600
DEFAULT_MODEL_PREFERENCE = (
    {"provider": "gemini", "model": "gemini-3-flash-preview", "meter": "gemini.tiers.flash"},
)


@dataclass
class QueueLoadError(ValueError):
    """Queue file could not be parsed into valid scheduler jobs."""

    path: Path
    reason: str

    def __str__(self) -> str:
        return f"{self.path}: {self.reason}"


def _now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def validate_job_id(value: Any) -> str:
    """Return a scheduler-safe job id or raise ValueError."""
    if not isinstance(value, str):
        raise ValueError("job id must be a string")
    if not SAFE_JOB_ID_RE.fullmatch(value):
        raise ValueError("job id must match [A-Za-z0-9][A-Za-z0-9._-]{0,127}")
    if ".." in value:
        raise ValueError("job id must not contain '..'")
    return value


def validate_timeout_s(value: Any) -> int:
    """Return a bounded timeout in seconds or raise ValueError."""
    if isinstance(value, bool):
        raise ValueError("timeout_s must be an integer")
    try:
        timeout = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("timeout_s must be an integer") from exc
    if timeout < MIN_TIMEOUT_S or timeout > MAX_TIMEOUT_S:
        raise ValueError(f"timeout_s must be between {MIN_TIMEOUT_S} and {MAX_TIMEOUT_S}")
    return timeout


def validate_model_preference(value: Any) -> list[dict[str, str]]:
    """Return a validated model ladder or raise ValueError."""
    if not isinstance(value, list):
        raise ValueError("model_preference must be a list")
    if not value:
        raise ValueError("model_preference must contain at least one provider")
    clean: list[dict[str, str]] = []
    for idx, rung in enumerate(value):
        if not isinstance(rung, dict):
            raise ValueError(f"model_preference[{idx}] must be a mapping")
        clean_rung: dict[str, str] = {}
        for key in ("provider", "model", "meter"):
            rung_value = rung.get(key)
            if not isinstance(rung_value, str):
                raise ValueError(f"model_preference[{idx}].{key} must be a string")
            if not rung_value.strip():
                raise ValueError(f"model_preference[{idx}].{key} must not be empty")
            if any(ch in rung_value for ch in "\r\n\t"):
                raise ValueError(f"model_preference[{idx}].{key} must not contain control characters")
            clean_rung[key] = rung_value
        clean.append(clean_rung)
    return clean


def _default_model_preference() -> list[dict[str, str]]:
    return [dict(rung) for rung in DEFAULT_MODEL_PREFERENCE]


def validate_depends_on_jobs(value: Any) -> list[str]:
    """Return dependency job ids or reject malformed queue entries."""
    if value is None:
        return []
    if not isinstance(value, list):
        raise ValueError("depends_on_jobs must be a list")
    clean: list[str] = []
    for idx, job_id in enumerate(value):
        if not isinstance(job_id, str):
            raise ValueError(f"depends_on_jobs[{idx}] must be a string")
        try:
            clean.append(validate_job_id(job_id))
        except ValueError as exc:
            raise ValueError(f"depends_on_jobs[{idx}] invalid: {exc}") from exc
    return clean


def validate_earliest_iso(value: Any) -> str:
    """Validate earliest_iso shape without changing legacy date parsing behavior."""
    if not isinstance(value, str):
        raise ValueError("earliest_iso must be a string")
    return value


def validate_template_vars(value: Any) -> dict[str, Any]:
    """Return template variables or reject malformed queue entries."""
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError("template_vars must be a mapping")
    return value


def validate_workdir(value: Any) -> Path:
    """Resolve a workdir and reject known-sensitive macOS privacy surfaces."""
    raw = value or os.getcwd()
    if not isinstance(raw, str):
        raise ValueError("workdir must be a string")
    home = Path.home().resolve()
    blocked = [
        home / "Library" / "Mobile Documents",
        home / "Library" / "Keychains",
        home / "Library" / "Mail",
        home / "Library" / "Messages",
        home / "Library" / "Safari",
        home / "Library" / "Contacts",
        home / "Library" / "Calendars",
        home / "Library" / "Photos",
        home / "Library" / "Notes",
        home / "Library" / "HomeKit",
        home / "Library" / "Cookies",
        home / ".ssh",
        Path("/Users") / "tg",
    ]
    cloud_storage = home / "Library" / "CloudStorage"
    raw_path = Path(raw).expanduser()
    raw_norm = os.path.normpath(str(raw_path))
    for denied in blocked:
        denied_norm = os.path.normpath(str(denied))
        if raw_norm == denied_norm or raw_norm.startswith(denied_norm + os.sep):
            raise ValueError(f"workdir is under prohibited privacy surface: {denied}")
    cloud_norm = os.path.normpath(str(cloud_storage))
    if raw_norm == cloud_norm or raw_norm.startswith(cloud_norm + os.sep):
        rel = raw_norm[len(cloud_norm):].lstrip(os.sep)
        first_part = rel.split(os.sep, 1)[0] if rel else ""
        if first_part.startswith("iCloud"):
            raise ValueError("workdir is under prohibited iCloud CloudStorage surface")

    path = raw_path.resolve()
    if path == cloud_storage or cloud_storage in path.parents:
        try:
            first_part = path.relative_to(cloud_storage).parts[0]
        except (IndexError, ValueError):
            first_part = ""
        if first_part.startswith("iCloud"):
            raise ValueError("workdir is under prohibited iCloud CloudStorage surface")
    for denied in blocked:
        if path == denied or denied in path.parents:
            raise ValueError(f"workdir is under prohibited privacy surface: {denied}")
    return path


def _validate_log_part(name: str, value: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{name} must be a string")
    if not SAFE_LOG_PART_RE.fullmatch(value) or ".." in value:
        raise ValueError(f"{name} contains unsafe characters")
    return value


def safe_log_path(log_dir: str | Path, job_id: str, provider: str, stream: str) -> Path:
    """Construct a contained scheduler log path."""
    if stream not in {"stdout", "stderr"}:
        raise ValueError("stream must be stdout or stderr")
    safe_id = validate_job_id(job_id)
    safe_provider = _validate_log_part("provider", provider)
    safe_stream = stream
    root = Path(log_dir).expanduser().resolve()
    path = (root / f"{safe_id}.{safe_provider}.{safe_stream}").resolve()
    if path.parent != root:
        raise ValueError("log path escaped log directory")
    return path


def prepare_log_paths(log_dir: str | Path, job_id: str, provider: str) -> tuple[Path, Path]:
    """Create a private log directory and return stdout/stderr paths."""
    root = Path(log_dir).expanduser()
    existed = root.exists()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not root.is_dir():
        raise NotADirectoryError(str(root))
    if not existed:
        os.chmod(root, 0o700)
    mode = stat.S_IMODE(root.stat().st_mode)
    if mode & 0o077:
        raise PermissionError(f"log directory must be private 0700: {root}")
    return (
        safe_log_path(root, job_id, provider, "stdout"),
        safe_log_path(root, job_id, provider, "stderr"),
    )


def open_private_log(path: Path, mode: str):
    """Open a log file with 0600 permissions."""
    if path.is_symlink():
        raise OSError(f"refusing symlinked log path: {path}")
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    flags = os.O_CREAT | os.O_TRUNC | nofollow
    if "a" in mode:
        flags = os.O_CREAT | os.O_APPEND | nofollow
    if "r" in mode and all(ch not in mode for ch in "wa+"):
        if path.is_symlink():
            raise OSError(f"refusing symlinked log path: {path}")
        return path.open(mode)
    flags |= os.O_RDWR if "+" in mode else os.O_WRONLY
    fd = os.open(path, flags, 0o600)
    os.fchmod(fd, 0o600)
    return os.fdopen(fd, mode)


def write_private_text(path: Path, text: str) -> None:
    with open_private_log(path, "w") as fh:
        fh.write(text)


@dataclass
class Attempt:
    iso: str
    provider: str
    model: str
    meter: str
    ok: bool
    error_kind: str = ""  # "" | hard_wall | throttle | timeout | io_error | nonzero_exit | unknown
    duration_s: float = 0.0
    log_path: str = ""


@dataclass
class Job:
    """One scheduled unit of work."""

    id: str
    project: str = ""
    workdir: str = ""
    template: str = "raw_prompt"  # raw_prompt | codegen-swift | research | audit | etc
    template_vars: dict[str, Any] = field(default_factory=dict)
    model_preference: list[dict[str, str]] = field(default_factory=_default_model_preference)
    earliest_iso: str = ""
    priority: str = "P2"  # P0 | P1 | P2 | P3
    timeout_s: int = 600
    retry: dict[str, Any] = field(default_factory=lambda: {"max": 3, "backoff_s": [60, 300, 1800]})
    status: JobStatus = "pending"
    attempts: list[Attempt] = field(default_factory=list)
    created_iso: str = field(default_factory=_now_iso)
    started_iso: str = ""
    completed_iso: str = ""
    last_error: str = ""
    requires_confirm: bool = False
    depends_on_jobs: list[str] = field(default_factory=list)
    notes: str = ""

    def __post_init__(self) -> None:
        self.id = validate_job_id(self.id)
        self.template_vars = validate_template_vars(self.template_vars)
        self.timeout_s = validate_timeout_s(self.timeout_s)
        self.model_preference = validate_model_preference(self.model_preference)
        self.earliest_iso = validate_earliest_iso(self.earliest_iso)
        self.depends_on_jobs = validate_depends_on_jobs(self.depends_on_jobs)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> Job:
        if not isinstance(d, dict):
            raise ValueError("job must be a mapping")
        d = dict(d)
        if "model_preference" not in d:
            raise ValueError("model_preference is required")
        attempts_raw = d.pop("attempts", []) or []
        if not isinstance(attempts_raw, list):
            raise ValueError("attempts must be a list")
        attempts: list[Attempt] = []
        for idx, attempt in enumerate(attempts_raw):
            if isinstance(attempt, Attempt):
                attempts.append(attempt)
                continue
            if not isinstance(attempt, dict):
                raise ValueError(f"attempts[{idx}] must be a mapping")
            try:
                attempts.append(Attempt(**attempt))
            except TypeError as exc:
                raise ValueError(f"attempts[{idx}] invalid: {exc}") from exc
        # Drop unknown keys defensively (so future schema doesn't crash old code)
        valid_keys = set(cls.__dataclass_fields__)
        clean = {k: v for k, v in d.items() if k in valid_keys}
        if "template_vars" in clean:
            clean["template_vars"] = validate_template_vars(clean["template_vars"])
        if "depends_on_jobs" in clean:
            clean["depends_on_jobs"] = validate_depends_on_jobs(clean["depends_on_jobs"])
        clean["attempts"] = attempts
        return cls(**clean)

    def to_dict(self) -> dict[str, Any]:
        out = asdict(self)
        # Drop empty fields to keep YAML compact
        for k in ("started_iso", "completed_iso", "last_error", "notes"):
            if not out.get(k):
                out.pop(k, None)
        if not out["attempts"]:
            out.pop("attempts", None)
        if not out["depends_on_jobs"]:
            out.pop("depends_on_jobs", None)
        if not out["requires_confirm"]:
            out.pop("requires_confirm", None)
        return out


def _lock_path(queue_path: Path) -> Path:
    return queue_path.with_suffix(queue_path.suffix + ".lock")


@contextmanager
def _flock(queue_path: Path):
    """Best-effort exclusive lock; safe on macOS POSIX."""
    if sys.platform == "win32":
        yield
        return
    lock = _lock_path(queue_path)
    lock.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(lock), os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _load_queue_unlocked(p: Path) -> list[Job]:
    if not p.exists():
        return []
    raw = p.read_text(encoding="utf-8")
    if not raw.strip():
        return []
    try:
        data = yaml.safe_load(raw) or {}
    except yaml.YAMLError as exc:
        raise QueueLoadError(p, f"invalid YAML: {exc}") from exc
    if not isinstance(data, dict):
        raise QueueLoadError(p, "queue YAML must contain a {jobs: [...]} root")
    jobs_raw = data.get("jobs", [])
    if not isinstance(jobs_raw, list):
        raise QueueLoadError(p, "jobs must be a list")
    jobs: list[Job] = []
    for idx, job_raw in enumerate(jobs_raw):
        try:
            jobs.append(Job.from_dict(job_raw))
        except (TypeError, ValueError) as exc:
            raise QueueLoadError(p, f"jobs[{idx}]: {exc}") from exc
    return jobs


def load_queue(path: Path | None = None) -> list[Job]:
    """Read jobs.yaml; return [] if file missing."""
    p = path or DEFAULT_QUEUE_PATH
    if not p.exists():
        return []
    with _flock(p):
        return _load_queue_unlocked(p)


def _save_queue_unlocked(jobs: list[Job], p: Path) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    payload = {"version": 1, "jobs": [j.to_dict() for j in jobs]}
    fd, tmp = tempfile.mkstemp(dir=p.parent, prefix=p.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as fh:
            yaml.safe_dump(
                payload,
                fh,
                sort_keys=False,
                default_flow_style=False,
                allow_unicode=True,
            )
        os.replace(tmp, p)
        os.chmod(p, 0o600)
    except Exception:
        with suppress(OSError):
            os.unlink(tmp)
        raise


def save_queue(jobs: list[Job], path: Path | None = None) -> None:
    """Atomic write of jobs.yaml via tempfile + os.replace."""
    p = path or DEFAULT_QUEUE_PATH
    with _flock(p):
        _save_queue_unlocked(jobs, p)


def add_jobs(new: list[Job], path: Path | None = None) -> int:
    """Append new jobs, skip if id collision. Returns count added."""
    p = path or DEFAULT_QUEUE_PATH
    with _flock(p):
        existing = _load_queue_unlocked(p)
        existing_ids = {j.id for j in existing}
        to_add = [j for j in new if j.id not in existing_ids]
        if to_add:
            _save_queue_unlocked(existing + to_add, p)
        return len(to_add)


def update_job(job: Job, path: Path | None = None) -> None:
    """Replace one job by id; raise if not found."""
    p = path or DEFAULT_QUEUE_PATH
    with _flock(p):
        jobs = _load_queue_unlocked(p)
        for i, j in enumerate(jobs):
            if j.id == job.id:
                jobs[i] = job
                _save_queue_unlocked(jobs, p)
                return
    raise KeyError(f"job not found: {job.id}")


def pending_ready_jobs(jobs: list[Job], now: float | None = None) -> list[Job]:
    """Return jobs where status is pending/gated and earliest_iso <= now and deps satisfied.

    Includes 'gated_by_quota' so jobs blocked by a temporary quota wall
    are automatically re-evaluated on the next tick once the meter clears.
    """
    now = time.time() if now is None else now
    completed = {j.id for j in jobs if j.status == "completed"}

    ready: list[Job] = []
    for j in jobs:
        if j.status not in ("pending", "gated_by_quota"):
            continue
        if j.earliest_iso:
            try:
                eiso = datetime.fromisoformat(j.earliest_iso).timestamp()
            except ValueError:
                j.status = "failed"
                j.last_error = f"invalid earliest_iso: {j.earliest_iso!r}"
                continue
            if eiso > now:
                continue
        if j.depends_on_jobs and not set(j.depends_on_jobs).issubset(completed):
            continue
        ready.append(j)

    # Priority sort: P0 first, then by earliest_iso ASC, then by creation
    pr_order = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
    ready.sort(key=lambda j: (pr_order.get(j.priority, 9), j.earliest_iso, j.created_iso))
    return ready
