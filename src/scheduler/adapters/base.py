"""Adapter contract: every provider implementation returns an AdapterResult.

Error kinds map to meter state transitions:
    hard_wall   → quota exhausted; mark meter blocked, skip ladder rung
    throttle    → rate limit; back off N seconds, retry same rung
    timeout     → wall clock exceeded; bump attempt counter, try next rung
    io_error    → CLI not found / file missing; mark job failed (config bug)
    nonzero_exit→ CLI ran but returned non-zero; treat as transient failure
    unknown     → catch-all, treat as transient
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal, Protocol

ErrorKind = Literal["", "hard_wall", "throttle", "timeout", "io_error", "nonzero_exit", "unknown"]


def prompt_summary(prompt: str) -> str:
    """Return a non-reversible prompt identifier for diagnostic dry-run logs."""
    digest = hashlib.sha256(prompt.encode("utf-8")).hexdigest()[:16]
    return f"prompt omitted ({len(prompt)} chars, sha256={digest})"


def sanitize_note(text: str, limit: int = 300) -> str:
    """Redact obvious secrets and collapse user-home paths before persisting notes."""
    if not text:
        return ""
    home = str(Path.home())
    redacted = text.replace(home, "~")
    redacted = re.sub(r"/Users/[^/\s]+", "/Users/[user]", redacted)
    redacted = re.sub(r"(?i)bearer\s+[A-Za-z0-9._~+/=-]+", "Bearer [redacted]", redacted)
    redacted = re.sub(
        r"(?i)(access_token|refresh_token|id_token|authorization|api[_-]?key|token|secret|password)"
        r"(['\"]?\s*[:=]\s*['\"]?)[^'\"\s,}]+",
        r"\1\2[redacted]",
        redacted,
    )
    redacted = re.sub(r"sk-[A-Za-z0-9_-]{12,}", "[redacted-token]", redacted)
    redacted = re.sub(r"[\r\n\t]+", " ", redacted)
    return redacted[:limit]


def redact_sensitive_text(text: str) -> str:
    """Redact obvious token material from captured provider logs."""
    if not text:
        return ""
    redacted = text
    redacted = re.sub(r"/Users/[^/\s]+", "/Users/[user]", redacted)
    redacted = re.sub(r"(?i)(authorization:\s*bearer\s+)[^\s\"']+", r"\1[redacted]", redacted)
    redacted = re.sub(
        r"(?i)(access_token|refresh_token|id_token|api[_-]?key|token|secret|password)"
        r"(['\"]?\s*[:=]\s*['\"]?)[^'\"\s,}]+",
        r"\1\2[redacted]",
        redacted,
    )
    redacted = re.sub(r"sk-[A-Za-z0-9_-]{12,}", "[redacted-token]", redacted)
    return redacted


def redact_log_file(path: str | Path) -> None:
    p = Path(path)
    if not p.exists() or p.is_symlink():
        return
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    redacted = redact_sensitive_text(text)
    if redacted == text:
        return
    try:
        p.write_text(redacted, encoding="utf-8")
        p.chmod(0o600)
    except OSError:
        return


def exception_note(exc: BaseException) -> str:
    detail = sanitize_note(str(exc), limit=120)
    return f"{type(exc).__name__}: {detail}" if detail else type(exc).__name__


@dataclass
class AdapterResult:
    """One adapter.fire() outcome."""

    ok: bool
    error_kind: ErrorKind = ""
    stdout_path: str = ""
    stderr_path: str = ""
    duration_s: float = 0.0
    exit_code: int = 0
    notes: str = ""

    @classmethod
    def success(cls, stdout_path: str, duration_s: float, exit_code: int = 0) -> AdapterResult:
        return cls(ok=True, stdout_path=stdout_path, duration_s=duration_s, exit_code=exit_code)

    @classmethod
    def failure(cls, error_kind: ErrorKind, notes: str = "", duration_s: float = 0.0) -> AdapterResult:
        return cls(ok=False, error_kind=error_kind, notes=notes, duration_s=duration_s)


class Adapter(Protocol):
    """Each provider implements this."""

    provider_name: str

    def fire(
        self,
        job: Any,  # Job — avoid circular import
        candidate: dict[str, str],
        log_dir: str,
    ) -> AdapterResult:
        """Run the job on this provider; return outcome.

        Args:
            job: the Job dataclass
            candidate: ladder rung {"provider": ..., "model": ..., "meter": ...}
            log_dir: directory to write stdout/stderr logs into
        """
        ...
