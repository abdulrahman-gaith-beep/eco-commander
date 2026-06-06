"""Gemini adapter — shells `gemini -p '' -m <model> --output-format text`.

Model mapping (candidate.model → CLI -m flag):
    gemini-3.1-pro-preview
    gemini-3-flash-preview
    gemini-3.1-flash-lite-preview

Templates supported:
    raw_prompt: uses template_vars["prompt"]
    research:   wraps prompt with synthesis framing
    cataloging: forces JSON output via --output-format json
"""

from __future__ import annotations

import os
import signal
import subprocess
import time
from contextlib import suppress
from pathlib import Path
from typing import Any, ClassVar

from scheduler.adapters.base import (
    AdapterResult,
    ErrorKind,
    exception_note,
    prompt_summary,
    redact_log_file,
    sanitize_note,
)
from scheduler.queue import (
    open_private_log,
    prepare_log_paths,
    validate_timeout_s,
    validate_workdir,
    write_private_text,
)


def _kill_tree(proc: subprocess.Popen) -> None:
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except (OSError, ProcessLookupError):
        with suppress(OSError):
            proc.kill()


def _contained_include_dirs(include_dirs: list[Any], workdir: Path) -> list[Path]:
    """Keep Gemini workspace expansion under the job workdir unless explicitly allowed."""
    allow_external = os.environ.get("ECO_GEMINI_ALLOW_EXTERNAL_INCLUDE_DIRS") == "1"
    safe_dirs: list[Path] = []
    for raw in include_dirs:
        path = Path(str(raw)).expanduser()
        if not path.is_absolute():
            path = workdir / path
        resolved = validate_workdir(str(path))
        if not allow_external and resolved != workdir and workdir not in resolved.parents:
            raise ValueError(f"include directory escapes workdir: {raw}")
        safe_dirs.append(resolved)
    return safe_dirs


class GeminiAdapter:
    provider_name = "gemini"
    _APPROVAL_MODES: ClassVar[set[str]] = {"default", "auto_edit", "yolo", "plan"}

    def _render_prompt(self, job: Any) -> str:
        v = job.template_vars or {}
        template = job.template
        prompt = v.get("prompt", "") or job.notes or ""

        if template == "research":
            corpus = v.get("corpus_paths", []) or []
            corpus_block = "\n".join(f"  - {p}" for p in corpus)
            return (
                f"{prompt}\n\n"
                "Read these inputs:\n"
                f"{corpus_block}\n\n"
                "Output: TL;DR (3 bullets) + Findings + Open Questions. "
                "Cite by absolute path."
            )
        return prompt

    def fire(
        self,
        job: Any,
        candidate: dict[str, str],
        log_dir: str,
    ) -> AdapterResult:
        gemini_bin = os.environ.get("ECO_GEMINI_BIN", "gemini")
        prompt = self._render_prompt(job)
        if not prompt.strip():
            return AdapterResult.failure("io_error", notes="empty prompt after template render")

        try:
            timeout_s = validate_timeout_s(getattr(job, "timeout_s", 600))
            workdir = validate_workdir(getattr(job, "workdir", ""))
            stdout_path, stderr_path = prepare_log_paths(log_dir, job.id, self.provider_name)
        except (OSError, ValueError) as exc:
            return AdapterResult.failure("io_error", notes=sanitize_note(f"unsafe scheduler setup: {exc}"))

        model = candidate.get("model", "gemini-3.1-flash-lite-preview")
        v = job.template_vars or {}
        include_dirs = v.get("include_directories", []) or []
        try:
            safe_include_dirs = _contained_include_dirs(include_dirs, workdir)
        except ValueError as exc:
            return AdapterResult.failure("io_error", notes=sanitize_note(str(exc)))
        approval_mode = os.environ.get("ECO_GEMINI_APPROVAL_MODE", "plan")
        if approval_mode not in self._APPROVAL_MODES:
            return AdapterResult.failure("io_error", notes=f"invalid ECO_GEMINI_APPROVAL_MODE: {approval_mode}")

        cmd = [
            gemini_bin,
            # Gemini headless mode accepts stdin and appends it to --prompt.
            # Keep the real prompt out of argv so process listings do not expose it.
            "-p", "",
            "-m", model,
            "--approval-mode", approval_mode,
            "--allowed-mcp-server-names", "none",
            "--output-format", "text",
        ]
        for d in safe_include_dirs:
            cmd.extend(["--include-directories", str(d)])

        if os.environ.get("ECO_DRY_RUN") == "1":
            safe_cmd = [gemini_bin, "-p", "[prompt omitted]", "-m", model, "--approval-mode", approval_mode]
            write_private_text(
                stdout_path,
                f"[DRY RUN] gemini cmd: {safe_cmd}... ({len(cmd)} args)\n{prompt_summary(prompt)}\n",
            )
            write_private_text(stderr_path, "")
            return AdapterResult.success(str(stdout_path), 0.0, exit_code=0)

        t0 = time.time()
        try:
            with open_private_log(stdout_path, "wb") as so, open_private_log(stderr_path, "wb") as se:
                proc = subprocess.Popen(
                    cmd,
                    stdin=subprocess.PIPE,
                    stdout=so,
                    stderr=se,
                    cwd=str(workdir),
                    start_new_session=True,
                )
                try:
                    proc.communicate(input=prompt.encode("utf-8"), timeout=timeout_s)
                    exit_code = proc.returncode
                except subprocess.TimeoutExpired:
                    _kill_tree(proc)
                    with suppress(subprocess.TimeoutExpired):
                        proc.communicate(timeout=10)
                    redact_log_file(stdout_path)
                    redact_log_file(stderr_path)
                    return AdapterResult.failure(
                        "timeout",
                        notes=f"gemini exceeded {timeout_s}s",
                        duration_s=time.time() - t0,
                    )
        except FileNotFoundError:
            return AdapterResult.failure("io_error", notes=f"{gemini_bin} not in PATH")
        except Exception as exc:
            redact_log_file(stdout_path)
            redact_log_file(stderr_path)
            return AdapterResult.failure(
                "unknown",
                notes=exception_note(exc),
                duration_s=time.time() - t0,
            )

        duration = time.time() - t0
        redact_log_file(stdout_path)
        redact_log_file(stderr_path)
        if exit_code == 0:
            return AdapterResult.success(str(stdout_path), duration, exit_code)

        try:
            tail = stderr_path.read_text(encoding="utf-8", errors="replace")[-2000:].lower()
        except OSError:
            tail = ""

        error_kind: ErrorKind
        if any(s in tail for s in ("resource_exhausted", "quota exceeded", "quota exhausted", "daily limit", "use a different model")):
            error_kind = "hard_wall"
        elif any(s in tail for s in ("rate limit", "429", "rpm", "too many")):
            error_kind = "throttle"
        else:
            error_kind = "nonzero_exit"

        return AdapterResult(
            ok=False,
            error_kind=error_kind,
            stdout_path=str(stdout_path),
            stderr_path=str(stderr_path),
            duration_s=duration,
            exit_code=exit_code,
            notes=sanitize_note(tail[-300:].strip()),
        )
