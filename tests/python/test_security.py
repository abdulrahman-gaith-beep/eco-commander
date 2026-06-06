"""Security and hardening tests for the eco-commander poller.

P2 hardening:
- _safe_collect never leaks bearer tokens, API keys, URLs into JSON
- _atomic_write always sets 0o600 permissions
- _log_private isolates secrets from public JSON output
- Concurrent-write resilience for queue.py
"""

import json
import os
import stat
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "src"))

from poller.main import _atomic_write, _log_private, _safe_collect


class TestSecretLeakPrevention(unittest.TestCase):
    """Exhaustive secret-leak prevention for _safe_collect.

    The poller writes usage.json at ~/.eco/current/usage.json which is
    readable by all processes. Exception messages can contain bearer tokens,
    API keys, or OAuth URLs. This test class ensures NONE of those ever
    appear in the returned dict.
    """

    SECRET_PATTERNS = [
        "sk-ant-api03-FAKESECRET123",
        "Bearer eyJhbGciOiJIUzI1NiJ9.fake.token",
        "https://api.anthropic.com/v1/oauth?code=secret_code_123",
        "AIzaSyFAKEGOOGLEKEY1234567890",
        "ghp_FakeGitHubPersonalAccessToken12345",
        "xoxb-fake-slack-token-12345",
        "$HOME/.claude/oauth_credentials.json",
    ]

    def test_no_secret_in_error_field(self):
        """The 'error' field must contain ONLY the exception class name."""
        for secret in self.SECRET_PATTERNS:
            with self.subTest(secret=secret[:20]):
                def boom():
                    raise RuntimeError(f"Failed: {secret}")
                result = _safe_collect("test", boom)
                self.assertEqual(result["error"], "RuntimeError",
                                 f"error field should be class name only, got: {result['error']}")

    def test_no_secret_in_any_field(self):
        """No field in the returned dict should contain the secret."""
        for secret in self.SECRET_PATTERNS:
            with self.subTest(secret=secret[:20]):
                def boom():
                    raise ValueError(f"Connection to {secret} failed")
                result = _safe_collect("test", boom)
                result_str = json.dumps(result)
                self.assertNotIn(secret, result_str,
                                 f"SECURITY: secret leaked into result: {result_str}")

    def test_no_traceback_in_result(self):
        """Stack traces can contain file paths with secrets in variable names."""
        def deep_call():
            api_key = "sk-secret-key-99999"
            raise TypeError(f"bad type with {api_key}")

        result = _safe_collect("test", deep_call)
        result_str = json.dumps(result)
        self.assertNotIn("sk-secret", result_str)
        self.assertNotIn("Traceback", result_str)
        self.assertNotIn("File \"", result_str)


class TestFilePermissions(unittest.TestCase):
    """All files written by the poller must have restrictive permissions."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="eco-perm-test-")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_atomic_write_sets_0600(self):
        path = Path(self.tmpdir) / "test.json"
        _atomic_write(path, {"data": "value"})
        mode = stat.S_IMODE(path.stat().st_mode)
        self.assertEqual(mode, 0o600,
                         f"Expected 0o600 but got {oct(mode)}")

    def test_atomic_write_overwrites_keep_0600(self):
        """Even if file previously had wider perms, overwrite resets to 0o600."""
        path = Path(self.tmpdir) / "test.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("{}")
        os.chmod(path, 0o644)  # Deliberately widen

        _atomic_write(path, {"v": 2})
        mode = stat.S_IMODE(path.stat().st_mode)
        self.assertEqual(mode, 0o600)

    def test_log_private_creates_0600_log(self):
        with patch.dict(os.environ, {"ECO_HOME": self.tmpdir}):
            try:
                raise RuntimeError("test")
            except RuntimeError as exc:
                _log_private("test", exc)

        log = Path(self.tmpdir) / "logs" / "poller.log"
        mode = stat.S_IMODE(log.stat().st_mode)
        self.assertEqual(mode, 0o600)


class TestConcurrentQueueWrites(unittest.TestCase):
    """Queue YAML file should survive concurrent writes without corruption."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="eco-concurrent-test-")
        self.queue_path = Path(self.tmpdir) / "jobs.yaml"

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_concurrent_add_jobs_no_corruption(self):
        """Multiple threads adding jobs should not corrupt the YAML file."""
        from scheduler.queue import Job, add_jobs, load_queue

        errors = []
        def add_batch(batch_id):
            try:
                jobs = [Job(id=f"batch-{batch_id}-job-{i}") for i in range(5)]
                add_jobs(jobs, self.queue_path)
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=add_batch, args=(i,)) for i in range(4)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)

        self.assertEqual(len(errors), 0, f"Concurrent write errors: {errors}")

        # File should be parseable YAML
        jobs = load_queue(self.queue_path)
        # At least some jobs should have been added (exact count depends on locking)
        self.assertGreater(len(jobs), 0,
                           "No jobs were persisted after concurrent writes")

    def test_concurrent_save_no_partial_writes(self):
        """Concurrent save_queue calls should never produce partial/corrupt YAML."""
        import yaml

        from scheduler.queue import Job, save_queue

        errors = []
        def save_batch(batch_id):
            try:
                jobs = [Job(id=f"save-{batch_id}-{i}") for i in range(3)]
                save_queue(jobs, self.queue_path)
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=save_batch, args=(i,)) for i in range(6)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)

        self.assertEqual(len(errors), 0, f"Concurrent save errors: {errors}")

        # The file must be valid YAML regardless of which thread won last
        raw = self.queue_path.read_text()
        data = yaml.safe_load(raw)
        self.assertIsInstance(data, dict)
        self.assertIn("jobs", data)


if __name__ == "__main__":
    unittest.main()
