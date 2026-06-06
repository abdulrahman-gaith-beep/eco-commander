"""Codex GPT-5.5 adapter — shells `codex exec` non-interactively.

Convention:
    codex exec --skip-git-repo-check --cd <workdir> -m gpt-5.5 < prompt-from-stdin
    Captures stdout to <log_dir>/<job_id>.codex.stdout
    Captures stderr to <log_dir>/<job_id>.codex.stderr

Process-group: started with `start_new_session=True` so we can SIGKILL the
entire process tree on timeout (Codex CLI is Electron + Node → forks workers
that re-parent to launchd and keep burning quota if only the top PID is killed).

Error-kind heuristics (parsed from stderr tail):
    "try again at" / "daily limit" / "quota exhausted" → hard_wall
    "rate limit" / "429" / "too many"                   → throttle
    exit 124 (gtimeout)                                  → timeout
    exit 127                                             → io_error (codex not found)
"""

from __future__ import annotations

import os
import signal
import subprocess
import time
from contextlib import suppress
from typing import Any

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
    """SIGKILL the entire process group; ignore if already dead."""
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except (OSError, ProcessLookupError):
        # already dead or never started a group
        with suppress(OSError):
            proc.kill()


class CodexAdapter:
    provider_name = "codex"

    def _render_prompt(self, job: Any) -> str:
        """Translate a job's template + template_vars into a Codex prompt."""
        template = job.template
        v = job.template_vars or {}

        if template == "codegen-swift":
            spec_files = v.get("spec_files", []) or []
            output_targets = v.get("output_targets") or [v.get("output_target", "")]
            output_targets = [t for t in output_targets if t]
            specs_block = "\n".join(f"  - {s}" for s in spec_files)
            outputs_block = "\n".join(f"  - {t}" for t in output_targets)
            project_name = v.get("project_name", "the target iOS project")
            return (
                "You are Codex GPT-5.5 generating production Swift code for "
                f"{project_name}.\n\n"
                "READ THESE SPEC FILES (absolute paths):\n"
                f"{specs_block}\n\n"
                "PRODUCE THESE OUTPUT FILES (paths relative to workdir):\n"
                f"{outputs_block}\n\n"
                "Constraints:\n"
                "  - Honor sacred-names rules, including idafah and closed-formula exceptions.\n"
                "  - SwiftUI iOS 17+ idioms; Arabic-RTL aware.\n"
                "  - GRDB.swift 6.x for any SQLite work.\n"
                "  - NO file outside the listed output targets.\n"
                "  - Write each file using your edit tool; do not just print to stdout.\n"
                "When done, print one line: '✅ codegen complete: <N> files written'."
            )

        # Default: raw_prompt or unknown template — use prompt field directly
        return v.get("prompt", "") or job.notes or ""

    def fire(
        self,
        job: Any,
        candidate: dict[str, str],
        log_dir: str,
    ) -> AdapterResult:
        codex_bin = os.environ.get("ECO_CODEX_BIN", "codex")
        prompt = self._render_prompt(job)
        if not prompt.strip():
            return AdapterResult.failure("io_error", notes="empty prompt after template render")

        try:
            timeout_s = validate_timeout_s(getattr(job, "timeout_s", 600))
            workdir = validate_workdir(getattr(job, "workdir", ""))
            stdout_path, stderr_path = prepare_log_paths(log_dir, job.id, self.provider_name)
        except (OSError, ValueError) as exc:
            return AdapterResult.failure("io_error", notes=sanitize_note(f"unsafe scheduler setup: {exc}"))

        model = candidate.get("model", "gpt-5.5")
        cmd = [
            codex_bin, "exec",
            "--skip-git-repo-check",
            "--cd", str(workdir),
            "-m", model,
        ]

        # ECO_DRY_RUN=1 → echo command, exit 0
        if os.environ.get("ECO_DRY_RUN") == "1":
            write_private_text(
                stdout_path,
                f"[DRY RUN] would invoke: {' '.join(cmd)}\n\n"
                f"{prompt_summary(prompt)}\n",
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
                    start_new_session=True,  # own process group, killable as a tree
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
                        notes=f"codex exec exceeded {timeout_s}s",
                        duration_s=time.time() - t0,
                    )
        except FileNotFoundError:
            return AdapterResult.failure("io_error", notes=f"{codex_bin} not in PATH")
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

        # Inspect stderr tail for quota / throttle markers
        try:
            tail = stderr_path.read_text(encoding="utf-8", errors="replace")[-2000:].lower()
        except OSError:
            tail = ""

        error_kind: ErrorKind
        if any(s in tail for s in ("try again at", "daily limit", "quota exhausted", "weekly limit")):
            error_kind = "hard_wall"
        elif any(s in tail for s in ("rate limit", "429", "too many requests")):
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
