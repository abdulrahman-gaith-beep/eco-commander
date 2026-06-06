"""Ollama adapter — local always-on fallback for cataloging/lightweight tasks.

Default models: qwen3:4b, gemma4:e4b, phi4-mini:3.8b, qwen3:1.7b.
NEVER routed for hard synthesis or codegen (per match-model-to-task rule).
"""

from __future__ import annotations

import os
import signal
import subprocess
import time
from contextlib import suppress
from typing import Any

from scheduler.adapters.base import AdapterResult, exception_note, prompt_summary, redact_log_file, sanitize_note
from scheduler.queue import open_private_log, prepare_log_paths, validate_timeout_s, write_private_text


def _kill_tree(proc: subprocess.Popen) -> None:
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except (OSError, ProcessLookupError):
        with suppress(OSError):
            proc.kill()


def _tail_text(path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")[-2000:]
    except OSError:
        return ""


def _ollama_nonzero_notes(stdout_path, stderr_path, model: str, exit_code: int) -> str:
    tail = f"{_tail_text(stderr_path)}\n{_tail_text(stdout_path)}".lower()
    if any(marker in tail for marker in ("could not connect", "connection refused", "is ollama running", "ollama serve")):
        return sanitize_note("daemon-down: start the Ollama daemon with `ollama serve` and retry")
    if any(marker in tail for marker in ("model not found", "pull model", "not found")):
        return sanitize_note(f"model-missing: run `ollama pull {model}` and retry")
    detail = sanitize_note(tail[-300:].strip())
    return f"runtime: ollama exited {exit_code}" + (f"; {detail}" if detail else "")


class OllamaAdapter:
    provider_name = "ollama"

    def _render_prompt(self, job: Any) -> str:
        v = job.template_vars or {}
        return v.get("prompt", "") or job.notes or ""

    def fire(
        self,
        job: Any,
        candidate: dict[str, str],
        log_dir: str,
    ) -> AdapterResult:
        ollama_bin = os.environ.get("ECO_OLLAMA_BIN", "ollama")
        prompt = self._render_prompt(job)
        if not prompt.strip():
            return AdapterResult.failure("io_error", notes="empty prompt")

        try:
            timeout_s = validate_timeout_s(getattr(job, "timeout_s", 600))
            stdout_path, stderr_path = prepare_log_paths(log_dir, job.id, self.provider_name)
        except (OSError, ValueError) as exc:
            return AdapterResult.failure("io_error", notes=sanitize_note(f"unsafe scheduler log setup: {exc}"))

        model = candidate.get("model", "qwen3:4b")
        cmd = [ollama_bin, "run", model]

        if os.environ.get("ECO_DRY_RUN") == "1":
            write_private_text(stdout_path, f"[DRY RUN] ollama run {model}\n{prompt_summary(prompt)}\n")
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
                        notes=f"ollama run {model} exceeded {timeout_s}s",
                        duration_s=time.time() - t0,
                    )
        except FileNotFoundError:
            return AdapterResult.failure("io_error", notes=f"{ollama_bin} not in PATH")
        except Exception as exc:
            redact_log_file(stdout_path)
            redact_log_file(stderr_path)
            return AdapterResult.failure("unknown", notes=exception_note(exc))

        duration = time.time() - t0
        redact_log_file(stdout_path)
        redact_log_file(stderr_path)
        if exit_code == 0:
            return AdapterResult.success(str(stdout_path), duration, exit_code)
        return AdapterResult(
            ok=False,
            error_kind="nonzero_exit",
            stdout_path=str(stdout_path),
            stderr_path=str(stderr_path),
            duration_s=duration,
            exit_code=exit_code,
            notes=_ollama_nonzero_notes(stdout_path, stderr_path, model, exit_code),
        )
