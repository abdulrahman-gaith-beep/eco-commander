"""Tests for scheduler.adapters — provider registry + per-adapter logic.

Covers:
- get_adapter: dispatch to correct adapter, ValueError on unknown
- GeminiAdapter: prompt rendering, dry-run, error-kind heuristics
- CodexAdapter: codegen-swift template, dry-run, error-kind heuristics
- OllamaAdapter: dry-run, empty prompt rejection
- AdapterResult: factory methods
"""

import os
import stat
import subprocess
import sys
import tempfile
import unittest
from dataclasses import dataclass
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "src"))

from scheduler.adapters import get_adapter
from scheduler.adapters.base import AdapterResult, redact_sensitive_text, sanitize_note
from scheduler.adapters.claude import ClaudeAdapter
from scheduler.adapters.codex import CodexAdapter
from scheduler.adapters.gemini import GeminiAdapter
from scheduler.adapters.ollama import OllamaAdapter


# Minimal Job-like object for adapter tests (avoids importing queue.py's Job)
@dataclass
class FakeJob:
    id: str = "test-job"
    template: str = "raw_prompt"
    template_vars: dict | None = None
    notes: str = ""
    workdir: str = ""
    timeout_s: int = 30

    def __post_init__(self):
        if self.template_vars is None:
            self.template_vars = {}


class FakeProcess:
    pid = 12345

    def __init__(self, returncode=0, stdout_text="", stderr_text="", timeout_cmd="provider", raise_timeout=False):
        self.returncode = returncode
        self.stdout_text = stdout_text
        self.stderr_text = stderr_text
        self.timeout_cmd = timeout_cmd
        self.raise_timeout = raise_timeout
        self.input = None
        self.stdout_handle = None
        self.stderr_handle = None

    def bind_handles(self, stdout_handle, stderr_handle):
        self.stdout_handle = stdout_handle
        self.stderr_handle = stderr_handle
        return self

    def communicate(self, input=None, timeout=None):
        if input is not None:
            self.input = input
        if self.raise_timeout:
            raise subprocess.TimeoutExpired(cmd=self.timeout_cmd, timeout=timeout)
        if self.stdout_handle and self.stdout_text:
            self.stdout_handle.write(self.stdout_text.encode("utf-8"))
            self.stdout_handle.flush()
        if self.stderr_handle and self.stderr_text:
            self.stderr_handle.write(self.stderr_text.encode("utf-8"))
            self.stderr_handle.flush()
        return None, None


class TestGetAdapter(unittest.TestCase):
    """get_adapter: lazy import dispatch."""

    def test_returns_gemini_adapter(self):
        adapter = get_adapter("gemini")
        self.assertEqual(adapter.provider_name, "gemini")

    def test_returns_codex_adapter(self):
        adapter = get_adapter("codex")
        self.assertEqual(adapter.provider_name, "codex")

    def test_returns_claude_adapter(self):
        adapter = get_adapter("claude")
        self.assertEqual(adapter.provider_name, "claude")

    def test_returns_ollama_adapter(self):
        adapter = get_adapter("ollama")
        self.assertEqual(adapter.provider_name, "ollama")

    def test_raises_on_unknown_provider(self):
        with self.assertRaises(ValueError) as ctx:
            get_adapter("nonexistent")
        self.assertIn("nonexistent", str(ctx.exception))


class TestAdapterResult(unittest.TestCase):
    """AdapterResult factory methods."""

    def test_success_factory(self):
        r = AdapterResult.success("/tmp/log", 3.5, exit_code=0)
        self.assertTrue(r.ok)
        self.assertEqual(r.stdout_path, "/tmp/log")
        self.assertEqual(r.duration_s, 3.5)
        self.assertEqual(r.error_kind, "")

    def test_failure_factory(self):
        r = AdapterResult.failure("hard_wall", notes="quota exceeded", duration_s=1.2)
        self.assertFalse(r.ok)
        self.assertEqual(r.error_kind, "hard_wall")
        self.assertIn("quota", r.notes)

    def test_redacts_token_like_log_text(self):
        user_path = Path("/").joinpath("Users", "sample", "project").as_posix()
        text = (
            'Authorization: Bearer secret-token access_token="abc123456789XYZ" '
            f"api_key=key123 token=sk-testsecret123456 {user_path}"
        )
        redacted = redact_sensitive_text(text)
        self.assertNotIn("secret-token", redacted)
        self.assertNotIn("abc123456789XYZ", redacted)
        self.assertNotIn("sk-testsecret123456", redacted)
        self.assertNotIn("key123", redacted)
        self.assertNotIn(user_path, redacted)

    def test_sanitize_note_redacts_tokens_and_user_paths(self):
        user_path = Path("/").joinpath("Users", "sample", "project").as_posix()
        text = (
            f"failed under {user_path} "
            "token=sk-secret123456789 Authorization: Bearer private-token"
        )
        redacted = sanitize_note(text)
        self.assertNotIn(user_path, redacted)
        self.assertNotIn("sk-secret123456789", redacted)
        self.assertNotIn("private-token", redacted)


class TestGeminiAdapter(unittest.TestCase):
    """GeminiAdapter: prompt rendering + dry-run."""

    def setUp(self):
        self.adapter = GeminiAdapter()
        self.tmpdir = tempfile.mkdtemp(prefix="eco-adapter-test-")

    def tearDown(self):
        import shutil

        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_raw_prompt_rendering(self):
        job = FakeJob(template_vars={"prompt": "analyze this code"})
        prompt = self.adapter._render_prompt(job)
        self.assertEqual(prompt, "analyze this code")

    def test_research_template_rendering(self):
        job = FakeJob(
            template="research",
            template_vars={
                "prompt": "find bugs",
                "corpus_paths": ["/path/a.py", "/path/b.py"],
            },
        )
        prompt = self.adapter._render_prompt(job)
        self.assertIn("find bugs", prompt)
        self.assertIn("/path/a.py", prompt)
        self.assertIn("TL;DR", prompt)

    def test_empty_prompt_fallback_to_notes(self):
        job = FakeJob(notes="notes-based prompt")
        prompt = self.adapter._render_prompt(job)
        self.assertEqual(prompt, "notes-based prompt")

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1"})
    def test_dry_run_mode(self):
        job = FakeJob(template_vars={"prompt": "test"})
        candidate = {"model": "gemini-3-flash-preview"}
        result = self.adapter.fire(job, candidate, self.tmpdir)
        self.assertTrue(result.ok)
        log_path = Path(result.stdout_path)
        log_content = log_path.read_text()
        self.assertIn("[DRY RUN]", log_content)
        self.assertEqual(stat.S_IMODE(log_path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(Path(self.tmpdir).stat().st_mode), 0o700)

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1"})
    def test_dry_run_omits_prompt_body(self):
        secret_prompt = "token=sk-secret123456789 private note"
        job = FakeJob(template_vars={"prompt": secret_prompt})
        result = self.adapter.fire(job, {"model": "gemini-3-flash-preview"}, self.tmpdir)
        self.assertTrue(result.ok)
        log_content = Path(result.stdout_path).read_text()
        self.assertIn("prompt omitted", log_content)
        self.assertNotIn(secret_prompt, log_content)
        self.assertNotIn("sk-secret123456789", log_content)

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1", "ECO_GEMINI_ALLOW_EXTERNAL_INCLUDE_DIRS": "1"})
    def test_external_include_dirs_still_reject_sensitive_paths(self):
        job = FakeJob(
            template_vars={
                "prompt": "test",
                "include_directories": [str(Path.home() / "Library" / "Keychains")],
            }
        )
        result = self.adapter.fire(job, {"model": "gemini-3-flash-preview"}, self.tmpdir)
        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "io_error")
        self.assertIn("prohibited privacy surface", result.notes)

    def test_empty_prompt_returns_io_error(self):
        job = FakeJob(template_vars={"prompt": ""}, notes="")
        candidate = {"model": "flash"}
        result = self.adapter.fire(job, candidate, self.tmpdir)
        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "io_error")
        self.assertIn("empty prompt", result.notes)

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1"})
    def test_unsafe_job_id_returns_io_error(self):
        job = FakeJob(id="../escape", template_vars={"prompt": "test"})
        result = self.adapter.fire(job, {"model": "gemini-3-flash-preview"}, self.tmpdir)
        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "io_error")

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1"})
    def test_invalid_timeout_returns_io_error(self):
        job = FakeJob(timeout_s=999999999, template_vars={"prompt": "test"})
        result = self.adapter.fire(job, {"model": "gemini-3-flash-preview"}, self.tmpdir)
        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "io_error")

    def test_prompt_is_sent_via_stdin_not_argv(self):
        secret_prompt = "private prompt body"
        job = FakeJob(template_vars={"prompt": secret_prompt})
        seen = {}

        def fake_popen(cmd, **kwargs):
            proc = FakeProcess(returncode=0).bind_handles(kwargs["stdout"], kwargs["stderr"])
            seen["cmd"] = cmd
            seen["proc"] = proc
            return proc

        with patch("scheduler.adapters.gemini.subprocess.Popen", side_effect=fake_popen):
            result = self.adapter.fire(job, {"model": "gemini-3-flash-preview"}, self.tmpdir)

        self.assertTrue(result.ok)
        self.assertNotIn(secret_prompt, seen["cmd"])
        self.assertEqual(seen["proc"].input, secret_prompt.encode("utf-8"))


class TestCodexAdapter(unittest.TestCase):
    """CodexAdapter: codegen-swift template + dry-run."""

    def setUp(self):
        self.adapter = CodexAdapter()
        self.tmpdir = tempfile.mkdtemp(prefix="eco-adapter-test-")

    def tearDown(self):
        import shutil

        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_raw_prompt_rendering(self):
        job = FakeJob(template_vars={"prompt": "fix this bug"})
        prompt = self.adapter._render_prompt(job)
        self.assertEqual(prompt, "fix this bug")

    def test_codegen_swift_template(self):
        job = FakeJob(
            template="codegen-swift",
            template_vars={
                "spec_files": ["/specs/a.md"],
                "output_targets": ["Views/Main.swift"],
            },
        )
        prompt = self.adapter._render_prompt(job)
        self.assertIn("Codex GPT-5.5", prompt)
        self.assertIn("/specs/a.md", prompt)
        self.assertIn("Views/Main.swift", prompt)
        self.assertIn("sacred-names", prompt)

    def test_codegen_swift_output_target_compat(self):
        """Supports both output_target (singular) and output_targets (plural)."""
        job = FakeJob(
            template="codegen-swift",
            template_vars={
                "spec_files": ["/a.md"],
                "output_target": "Single.swift",
            },
        )
        prompt = self.adapter._render_prompt(job)
        self.assertIn("Single.swift", prompt)

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1"})
    def test_dry_run_mode(self):
        job = FakeJob(template_vars={"prompt": "test"})
        candidate = {"model": "gpt-5.5"}
        result = self.adapter.fire(job, candidate, self.tmpdir)
        self.assertTrue(result.ok)
        log_path = Path(result.stdout_path)
        log_content = log_path.read_text()
        self.assertIn("[DRY RUN]", log_content)
        self.assertEqual(stat.S_IMODE(log_path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(Path(self.tmpdir).stat().st_mode), 0o700)

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1"})
    def test_dry_run_omits_prompt_body(self):
        secret_prompt = "Authorization: Bearer private-token"
        job = FakeJob(template_vars={"prompt": secret_prompt})
        result = self.adapter.fire(job, {"model": "gpt-5.5"}, self.tmpdir)
        self.assertTrue(result.ok)
        log_content = Path(result.stdout_path).read_text()
        self.assertIn("prompt omitted", log_content)
        self.assertNotIn(secret_prompt, log_content)
        self.assertNotIn("private-token", log_content)

    def test_empty_prompt_returns_io_error(self):
        job = FakeJob(template_vars={"prompt": ""}, notes="")
        candidate = {"model": "gpt-5.5"}
        result = self.adapter.fire(job, candidate, self.tmpdir)
        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "io_error")

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1"})
    def test_unsafe_job_id_returns_io_error(self):
        job = FakeJob(id="../escape", template_vars={"prompt": "test"})
        result = self.adapter.fire(job, {"model": "gpt-5.5"}, self.tmpdir)
        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "io_error")

    def test_timeout_covers_stdin_write(self):
        proc = FakeProcess(timeout_cmd="codex", raise_timeout=True)
        job = FakeJob(template_vars={"prompt": "test"}, timeout_s=1)
        with patch("scheduler.adapters.codex.subprocess.Popen", return_value=proc), \
             patch("scheduler.adapters.codex._kill_tree") as mock_kill:
            result = self.adapter.fire(job, {"model": "gpt-5.5"}, self.tmpdir)

        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "timeout")
        self.assertEqual(proc.input, b"test")
        mock_kill.assert_called_once_with(proc)


class TestClaudeAdapter(unittest.TestCase):
    """ClaudeAdapter: dry-run, empty prompt, and timeout handling."""

    def setUp(self):
        self.adapter = ClaudeAdapter()
        self.tmpdir = tempfile.mkdtemp(prefix="eco-adapter-test-")

    def tearDown(self):
        import shutil

        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_raw_prompt_rendering(self):
        job = FakeJob(template_vars={"prompt": "review this"})
        prompt = self.adapter._render_prompt(job)
        self.assertEqual(prompt, "review this")

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1"})
    def test_dry_run_mode(self):
        job = FakeJob(template_vars={"prompt": "test"})
        candidate = {"model": "sonnet"}
        result = self.adapter.fire(job, candidate, self.tmpdir)
        self.assertTrue(result.ok)
        log_path = Path(result.stdout_path)
        log_content = log_path.read_text()
        self.assertIn("[DRY RUN]", log_content)
        self.assertIn("prompt omitted", log_content)
        self.assertNotIn("test", log_content)
        self.assertEqual(stat.S_IMODE(log_path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(Path(self.tmpdir).stat().st_mode), 0o700)

    def test_empty_prompt_returns_io_error(self):
        job = FakeJob(template_vars={"prompt": ""}, notes="")
        result = self.adapter.fire(job, {"model": "sonnet"}, self.tmpdir)
        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "io_error")
        self.assertIn("empty prompt", result.notes)

    def test_timeout_returns_timeout_error(self):
        proc = FakeProcess(timeout_cmd="claude", raise_timeout=True)
        job = FakeJob(template_vars={"prompt": "test"}, timeout_s=1)
        with patch("scheduler.adapters.claude.subprocess.Popen", return_value=proc), \
             patch("scheduler.adapters.claude._kill_tree") as mock_kill:
            result = self.adapter.fire(job, {"model": "sonnet"}, self.tmpdir)

        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "timeout")
        self.assertIn("claude exceeded 1s", result.notes)
        self.assertEqual(proc.input, b"test")
        mock_kill.assert_called_once_with(proc)

    def test_prompt_is_sent_via_stdin_not_argv(self):
        secret_prompt = "private claude prompt"
        job = FakeJob(template_vars={"prompt": secret_prompt})
        seen = {}

        def fake_popen(cmd, **kwargs):
            proc = FakeProcess(returncode=0).bind_handles(kwargs["stdout"], kwargs["stderr"])
            seen["cmd"] = cmd
            seen["proc"] = proc
            return proc

        with patch("scheduler.adapters.claude.subprocess.Popen", side_effect=fake_popen):
            result = self.adapter.fire(job, {"model": "sonnet"}, self.tmpdir)

        self.assertTrue(result.ok)
        self.assertNotIn(secret_prompt, seen["cmd"])
        self.assertEqual(seen["proc"].input, secret_prompt.encode("utf-8"))

    def test_error_kind_heuristics(self):
        cases = [
            ("insufficient credits quota", "hard_wall"),
            ("rate limit 429 too many requests", "throttle"),
            ("rate_limit_error from provider", "throttle"),
            ("unexpected runtime failure", "nonzero_exit"),
        ]
        for stderr_text, expected in cases:
            with self.subTest(expected=expected):
                def fake_popen(cmd, **kwargs):
                    return FakeProcess(returncode=1, stderr_text=stderr_text).bind_handles(
                        kwargs["stdout"],
                        kwargs["stderr"],
                    )

                job = FakeJob(template_vars={"prompt": "test"})
                with patch("scheduler.adapters.claude.subprocess.Popen", side_effect=fake_popen):
                    result = self.adapter.fire(job, {"model": "sonnet"}, self.tmpdir)

                self.assertFalse(result.ok)
                self.assertEqual(result.error_kind, expected)
                self.assertIn(stderr_text, result.notes)


class TestOllamaAdapter(unittest.TestCase):
    """OllamaAdapter: dry-run + empty prompt."""

    def setUp(self):
        self.adapter = OllamaAdapter()
        self.tmpdir = tempfile.mkdtemp(prefix="eco-adapter-test-")

    def tearDown(self):
        import shutil

        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_raw_prompt_rendering(self):
        job = FakeJob(template_vars={"prompt": "summarize"})
        prompt = self.adapter._render_prompt(job)
        self.assertEqual(prompt, "summarize")

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1"})
    def test_dry_run_mode(self):
        job = FakeJob(template_vars={"prompt": "test"})
        candidate = {"model": "qwen3:4b"}
        result = self.adapter.fire(job, candidate, self.tmpdir)
        self.assertTrue(result.ok)
        log_path = Path(result.stdout_path)
        log_content = log_path.read_text()
        self.assertIn("[DRY RUN]", log_content)
        self.assertEqual(stat.S_IMODE(log_path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(Path(self.tmpdir).stat().st_mode), 0o700)

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1"})
    def test_dry_run_omits_prompt_body(self):
        secret_prompt = "refresh_token=private-token"
        job = FakeJob(template_vars={"prompt": secret_prompt})
        result = self.adapter.fire(job, {"model": "qwen3:4b"}, self.tmpdir)
        self.assertTrue(result.ok)
        log_content = Path(result.stdout_path).read_text()
        self.assertIn("prompt omitted", log_content)
        self.assertNotIn(secret_prompt, log_content)
        self.assertNotIn("private-token", log_content)

    def test_empty_prompt_returns_io_error(self):
        job = FakeJob(template_vars={"prompt": ""}, notes="")
        candidate = {"model": "qwen3:4b"}
        result = self.adapter.fire(job, candidate, self.tmpdir)
        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "io_error")

    def test_notes_used_when_prompt_missing(self):
        job = FakeJob(notes="notes prompt")
        prompt = self.adapter._render_prompt(job)
        self.assertEqual(prompt, "notes prompt")

    @patch.dict(os.environ, {"ECO_DRY_RUN": "1"})
    def test_unsafe_job_id_returns_io_error(self):
        job = FakeJob(id="../escape", template_vars={"prompt": "test"})
        result = self.adapter.fire(job, {"model": "qwen3:4b"}, self.tmpdir)
        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "io_error")

    def test_timeout_covers_stdin_write(self):
        proc = FakeProcess(timeout_cmd="ollama", raise_timeout=True)
        job = FakeJob(template_vars={"prompt": "test"}, timeout_s=1)
        with patch("scheduler.adapters.ollama.subprocess.Popen", return_value=proc), \
             patch("scheduler.adapters.ollama._kill_tree") as mock_kill:
            result = self.adapter.fire(job, {"model": "qwen3:4b"}, self.tmpdir)

        self.assertFalse(result.ok)
        self.assertEqual(result.error_kind, "timeout")
        self.assertEqual(proc.input, b"test")
        self.assertIn("ollama run qwen3:4b exceeded 1s", result.notes)
        mock_kill.assert_called_once_with(proc)

    def test_nonzero_exit_notes_are_actionable(self):
        cases = [
            ("Error: could not connect to Ollama; is ollama running?", "daemon-down"),
            ("Error: model not found, try pulling it first", "model-missing"),
            ("Error: runtime crashed", "runtime: ollama exited 1"),
        ]
        for stderr_text, expected_note in cases:
            with self.subTest(expected_note=expected_note):
                def fake_popen(cmd, **kwargs):
                    return FakeProcess(returncode=1, stderr_text=stderr_text).bind_handles(
                        kwargs["stdout"],
                        kwargs["stderr"],
                    )

                job = FakeJob(template_vars={"prompt": "test"})
                with patch("scheduler.adapters.ollama.subprocess.Popen", side_effect=fake_popen):
                    result = self.adapter.fire(job, {"model": "qwen3:4b"}, self.tmpdir)

                self.assertFalse(result.ok)
                self.assertEqual(result.error_kind, "nonzero_exit")
                self.assertIn(expected_note, result.notes)


if __name__ == "__main__":
    unittest.main()
