"""Tests for scheduler.dispatcher — the scheduler tick engine.

Covers:
- _reset_stale_running: resets stuck jobs past timeout
- tick: job lifecycle (pending → running → completed/failed)
- Retry logic: hard_wall exemption, max retries → failed
- gated_by_quota when all ladder rungs blocked
- requires_confirm skips job
- Unknown provider → job failed
"""

import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from io import StringIO
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "src"))

from scheduler.adapters.base import AdapterResult
from scheduler.dispatcher import _reset_stale_running, tick
from scheduler.queue import Job, QueueLoadError, load_queue, save_queue


class TestResetStaleRunning(unittest.TestCase):
    """_reset_stale_running: resets jobs stuck past timeout + grace."""

    def test_resets_stuck_job(self):
        # Job started 2 hours ago with 600s timeout
        started = (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat(timespec="seconds")
        jobs = [Job(id="stuck", status="running", started_iso=started, timeout_s=600)]
        count = _reset_stale_running(jobs, grace_s=60)
        self.assertEqual(count, 1)
        self.assertEqual(jobs[0].status, "pending")
        self.assertIn("reset_stale_running", jobs[0].last_error)

    def test_ignores_recently_started(self):
        started = datetime.now(timezone.utc).isoformat(timespec="seconds")
        jobs = [Job(id="recent", status="running", started_iso=started, timeout_s=600)]
        count = _reset_stale_running(jobs, grace_s=60)
        self.assertEqual(count, 0)
        self.assertEqual(jobs[0].status, "running")

    def test_ignores_non_running(self):
        jobs = [
            Job(id="pending", status="pending"),
            Job(id="completed", status="completed"),
            Job(id="failed", status="failed"),
        ]
        count = _reset_stale_running(jobs, grace_s=60)
        self.assertEqual(count, 0)

    def test_handles_missing_started_iso(self):
        jobs = [Job(id="no-start", status="running", started_iso="")]
        count = _reset_stale_running(jobs, grace_s=60)
        self.assertEqual(count, 0)  # Can't determine age, leave alone

    def test_invalid_timeout_falls_back_safely(self):
        started = (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat(timespec="seconds")
        job = Job(id="bad-timeout", status="running", started_iso=started, timeout_s=600)
        job.timeout_s = "not-an-int"  # simulate old/corrupt queue data
        jobs = [job]
        count = _reset_stale_running(jobs, grace_s=60)
        self.assertEqual(count, 1)
        self.assertEqual(jobs[0].status, "pending")


class TestTick(unittest.TestCase):
    """tick: one scheduler pass — fires jobs, records outcomes."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="eco-tick-test-")
        self.env_patcher = patch.dict(os.environ, {"ECO_HOME": self.tmpdir})
        self.env_patcher.start()
        self.queue_path = Path(self.tmpdir) / "jobs.yaml"
        self.log_dir = Path(self.tmpdir) / "logs"
        self.log_dir.mkdir()

    def tearDown(self):
        import shutil

        self.env_patcher.stop()
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _save_jobs(self, jobs):
        save_queue(jobs, self.queue_path)

    def _mock_state(self, meters=None):
        return {"meters": meters or {}}

    @patch("scheduler.dispatcher.get_adapter")
    def test_fires_ready_job_successfully(self, mock_get):
        """pending job → running → completed on success."""
        mock_adapter = MagicMock()
        mock_adapter.fire.return_value = AdapterResult.success("/tmp/log", 2.5)
        mock_get.return_value = mock_adapter

        self._save_jobs([
            Job(
                id="fire-me",
                status="pending",
                model_preference=[{"provider": "gemini", "model": "flash", "meter": "gemini.flash"}],
            )
        ])

        summary = tick(
            queue_path=self.queue_path,
            log_dir=self.log_dir,
            state=self._mock_state(),
        )

        self.assertEqual(len(summary["fired"]), 1)
        self.assertTrue(summary["fired"][0]["ok"])
        self.assertEqual(summary["fired"][0]["status_after"], "completed")

        # Verify persisted state
        jobs = load_queue(self.queue_path)
        self.assertEqual(jobs[0].status, "completed")

    @patch("scheduler.dispatcher.get_adapter")
    def test_job_fails_after_max_retries(self, mock_get):
        """Non-wall failures exhaust retries → status=failed."""
        mock_adapter = MagicMock()
        mock_adapter.fire.return_value = AdapterResult.failure("nonzero_exit", notes="exit 1")
        mock_get.return_value = mock_adapter

        self._save_jobs([
            Job(
                id="fail-me",
                status="pending",
                retry={"max": 1, "backoff_s": [0]},
                model_preference=[{"provider": "codex", "model": "gpt-5.5", "meter": "codex.session"}],
            )
        ])

        summary = tick(
            queue_path=self.queue_path,
            log_dir=self.log_dir,
            state=self._mock_state(),
        )

        self.assertEqual(summary["fired"][0]["status_after"], "failed")
        jobs = load_queue(self.queue_path)
        self.assertEqual(jobs[0].status, "failed")

    @patch("scheduler.dispatcher.get_adapter")
    def test_retry_backoff_sets_next_earliest_iso(self, mock_get):
        """Retryable failures are delayed by retry.backoff_s."""
        mock_adapter = MagicMock()
        mock_adapter.fire.return_value = AdapterResult.failure("nonzero_exit", notes="exit 1")
        mock_get.return_value = mock_adapter

        self._save_jobs([
            Job(
                id="backoff-me",
                status="pending",
                retry={"max": 2, "backoff_s": [120]},
                model_preference=[{"provider": "codex", "model": "gpt-5.5", "meter": "codex.session"}],
            )
        ])

        before = datetime.now(timezone.utc).timestamp()
        summary = tick(
            queue_path=self.queue_path,
            log_dir=self.log_dir,
            state=self._mock_state(),
        )

        self.assertEqual(summary["fired"][0]["status_after"], "pending")
        jobs = load_queue(self.queue_path)
        self.assertEqual(jobs[0].status, "pending")
        self.assertGreaterEqual(datetime.fromisoformat(jobs[0].earliest_iso).timestamp(), before + 100)
        self.assertIn("retry after 120s", jobs[0].last_error)

    @patch("scheduler.dispatcher.get_adapter")
    def test_invalid_retry_max_defaults_safely(self, mock_get):
        """Malformed retry.max does not crash the tick."""
        mock_adapter = MagicMock()
        mock_adapter.fire.return_value = AdapterResult.failure("nonzero_exit", notes="exit 1")
        mock_get.return_value = mock_adapter

        self._save_jobs([
            Job(
                id="bad-retry-max",
                status="pending",
                retry={"max": "not-an-int", "backoff_s": [0]},
                model_preference=[{"provider": "codex", "model": "gpt-5.5", "meter": "codex.session"}],
            )
        ])

        summary = tick(
            queue_path=self.queue_path,
            log_dir=self.log_dir,
            state=self._mock_state(),
        )

        self.assertEqual(summary["fired"][0]["status_after"], "pending")
        jobs = load_queue(self.queue_path)
        self.assertIn("attempt 1/3", jobs[0].last_error)

    @patch("scheduler.dispatcher.get_adapter")
    def test_failed_attempt_keeps_sanitized_notes(self, mock_get):
        """Failure summaries and last_error preserve adapter diagnostics."""
        mock_adapter = MagicMock()
        mock_adapter.fire.return_value = AdapterResult.failure(
            "io_error",
            notes=f"claude not in PATH under {Path.home()} Authorization: Bearer secret-token",
        )
        mock_get.return_value = mock_adapter

        self._save_jobs([
            Job(
                id="note-me",
                status="pending",
                retry={"max": 2, "backoff_s": [0]},
                model_preference=[{"provider": "claude", "model": "sonnet", "meter": "claude.session"}],
            )
        ])

        summary = tick(
            queue_path=self.queue_path,
            log_dir=self.log_dir,
            state=self._mock_state(),
        )

        fired = summary["fired"][0]
        self.assertEqual(fired["status_after"], "pending")
        self.assertIn("claude not in PATH", fired["notes"])
        self.assertIn("claude not in PATH", fired["last_error"])
        self.assertNotIn(str(Path.home()), fired["notes"])
        self.assertNotIn("secret-token", fired["notes"])

        jobs = load_queue(self.queue_path)
        self.assertEqual(jobs[0].status, "pending")
        self.assertIn("claude not in PATH", jobs[0].last_error)
        self.assertNotIn(str(Path.home()), jobs[0].last_error)
        self.assertNotIn("secret-token", jobs[0].last_error)

    @patch("scheduler.dispatcher.get_adapter")
    def test_hard_wall_does_not_count_against_retry(self, mock_get):
        """hard_wall errors go back to pending, not counted toward max retries."""
        mock_adapter = MagicMock()
        mock_adapter.fire.return_value = AdapterResult.failure("hard_wall", notes="quota exhausted")
        mock_get.return_value = mock_adapter

        self._save_jobs([
            Job(
                id="wall-me",
                status="pending",
                retry={"max": 1, "backoff_s": [0]},
                model_preference=[{"provider": "gemini", "model": "flash", "meter": "gemini.flash"}],
            )
        ])

        summary = tick(
            queue_path=self.queue_path,
            log_dir=self.log_dir,
            state=self._mock_state(),
        )

        # Should go back to pending, NOT failed
        self.assertEqual(summary["fired"][0]["status_after"], "pending")
        jobs = load_queue(self.queue_path)
        self.assertEqual(jobs[0].status, "pending")

    @patch("scheduler.dispatcher.get_adapter")
    def test_quota_failures_update_meter_state(self, mock_get):
        """hard_wall/throttle adapter results are visible to routing state."""
        for error_kind in ("hard_wall", "throttle"):
            with self.subTest(error_kind=error_kind):
                mock_adapter = MagicMock()
                mock_adapter.fire.return_value = AdapterResult.failure(error_kind, notes="quota")
                mock_get.return_value = mock_adapter
                state = {"meters": {"gemini.flash": {"last_kind": "use_it_or_lose_it"}}}
                queue_path = Path(self.tmpdir) / f"{error_kind}.yaml"

                save_queue([
                    Job(
                        id=f"{error_kind}-job",
                        status="pending",
                        retry={"max": 2, "backoff_s": [30]},
                        model_preference=[{"provider": "gemini", "model": "flash", "meter": "gemini.flash"}],
                    )
                ], queue_path)

                tick(queue_path=queue_path, log_dir=self.log_dir, state=state)

                meter = state["meters"]["gemini.flash"]
                self.assertEqual(meter["last_kind"], error_kind)
                self.assertGreater(meter["last_fired_ts"], 0)
                if error_kind == "hard_wall":
                    self.assertGreater(meter["last_reset_epoch"], meter["last_fired_ts"])

    @patch("scheduler.dispatcher.get_adapter")
    def test_state_write_failure_is_reported(self, mock_get):
        """State persistence failures must not be hidden as a clean tick."""
        mock_adapter = MagicMock()
        mock_adapter.fire.return_value = AdapterResult.success("/tmp/log", 1.0)
        mock_get.return_value = mock_adapter

        self._save_jobs([
            Job(
                id="state-save-error",
                status="pending",
                model_preference=[{"provider": "gemini", "model": "flash", "meter": "gemini.flash"}],
            )
        ])

        with patch("scheduler.dispatcher._save_state", side_effect=OSError("disk full")):
            summary = tick(
                queue_path=self.queue_path,
                log_dir=self.log_dir,
                state=self._mock_state(),
            )

        self.assertEqual(summary["fired"][0]["status_after"], "completed")
        self.assertIn("errors", summary)
        self.assertIn("state write failed", summary["errors"][0]["message"])
        jobs = load_queue(self.queue_path)
        self.assertEqual(jobs[0].status, "completed")

    def test_requires_confirm_job_is_gated(self):
        """Jobs with requires_confirm=True are skipped."""
        self._save_jobs([
            Job(
                id="confirm-me",
                status="pending",
                requires_confirm=True,
                model_preference=[{"provider": "gemini", "model": "flash", "meter": "gemini.flash"}],
            )
        ])

        summary = tick(
            queue_path=self.queue_path,
            log_dir=self.log_dir,
            state=self._mock_state(),
        )

        self.assertEqual(len(summary["fired"]), 0)
        self.assertEqual(len(summary["gated"]), 1)
        self.assertEqual(summary["gated"][0]["reason"], "requires_confirm")

    def test_all_meters_blocked_gates_job(self):
        """When all ladder rungs are blocked, job is gated_by_quota."""
        import time

        blocked_state = {
            "meters": {
                "gemini.flash": {
                    "last_kind": "hard_wall",
                    "last_reset_epoch": time.time() + 3600,
                    "last_fired_ts": 0,
                },
            }
        }

        self._save_jobs([
            Job(
                id="blocked",
                status="pending",
                model_preference=[{"provider": "gemini", "model": "flash", "meter": "gemini.flash"}],
            )
        ])

        summary = tick(
            queue_path=self.queue_path,
            log_dir=self.log_dir,
            state=blocked_state,
        )

        self.assertEqual(len(summary["fired"]), 0)
        self.assertEqual(len(summary["gated"]), 1)
        self.assertEqual(summary["gated"][0]["reason"], "all_meters_blocked")

        jobs = load_queue(self.queue_path)
        self.assertEqual(jobs[0].status, "gated_by_quota")

    def test_unknown_provider_fails_immediately(self):
        """Unknown provider → job status=failed, no adapter call."""
        self._save_jobs([
            Job(
                id="bad-provider",
                status="pending",
                model_preference=[{"provider": "nonexistent_llm", "model": "v1", "meter": "fake"}],
            )
        ])

        summary = tick(
            queue_path=self.queue_path,
            log_dir=self.log_dir,
            state=self._mock_state(),
        )

        self.assertEqual(len(summary["fired"]), 1)
        self.assertFalse(summary["fired"][0]["ok"])
        self.assertIn("unknown provider", summary["fired"][0]["last_error"])
        self.assertIn("unknown provider", summary["fired"][0]["notes"])
        jobs = load_queue(self.queue_path)
        self.assertEqual(jobs[0].status, "failed")
        self.assertIn("unknown provider", jobs[0].last_error)

    @patch("scheduler.dispatcher.get_adapter")
    def test_respects_max_jobs_per_tick(self, mock_get):
        """Only max_jobs_per_tick jobs should fire per tick."""
        mock_adapter = MagicMock()
        mock_adapter.fire.return_value = AdapterResult.success("/tmp/log", 1.0)
        mock_get.return_value = mock_adapter

        self._save_jobs([
            Job(id=f"job-{i}", status="pending",
                model_preference=[{"provider": "gemini", "model": "flash", "meter": "g.f"}])
            for i in range(5)
        ])

        summary = tick(
            queue_path=self.queue_path,
            log_dir=self.log_dir,
            max_jobs_per_tick=2,
            state=self._mock_state(),
        )

        self.assertEqual(len(summary["fired"]), 2)

    def test_empty_queue_returns_summary(self):
        """Empty queue → valid summary with zero counts."""
        summary = tick(
            queue_path=self.queue_path,
            log_dir=self.log_dir,
            state=self._mock_state(),
        )
        self.assertEqual(summary["total_jobs"], 0)
        self.assertEqual(summary["ready_now"], 0)
        self.assertEqual(len(summary["fired"]), 0)


class TestDispatcherMain(unittest.TestCase):
    """dispatcher.main: process exit status mirrors fired attempt failures."""

    def test_main_returns_nonzero_when_attempt_failed(self):
        from scheduler import dispatcher

        summary = {
            "tick_iso": "2026-05-20T12:00:00+00:00",
            "total_jobs": 1,
            "fired": [{"id": "bad", "ok": False, "error_kind": "io_error"}],
            "gated": [],
        }
        with patch("scheduler.dispatcher.tick", return_value=summary), \
             patch("sys.stdout", new_callable=StringIO) as mock_out:
            rc = dispatcher.main()

        self.assertEqual(rc, 1)
        self.assertEqual(json.loads(mock_out.getvalue())["fired"][0]["id"], "bad")

    def test_main_rejects_invalid_max_jobs_env(self):
        from scheduler import dispatcher

        with patch.dict(os.environ, {"ECO_MAX_JOBS_PER_TICK": "0"}), \
             patch("scheduler.dispatcher.tick") as mock_tick, \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = dispatcher.main()

        self.assertEqual(rc, 2)
        mock_tick.assert_not_called()
        self.assertIn("ECO_MAX_JOBS_PER_TICK", mock_err.getvalue())

    def test_main_queue_load_error_returns_2(self):
        from scheduler import dispatcher

        err = QueueLoadError(Path("/tmp/jobs.yaml"), "invalid YAML")
        with patch("scheduler.dispatcher.tick", side_effect=err), \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = dispatcher.main()

        self.assertEqual(rc, 2)
        self.assertIn("error: cannot load scheduler queue:", mock_err.getvalue())
        self.assertIn("invalid YAML", mock_err.getvalue())


if __name__ == "__main__":
    unittest.main()
