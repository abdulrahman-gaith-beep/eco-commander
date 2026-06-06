"""Tests for scheduler.cli — the eco-scheduler CLI surface.

Covers:
- cmd_status: human-readable and --json output
- cmd_add: YAML file parsing, missing file error
- cmd_run_once: delegates to tick(), returns JSON summary
- cmd_tail: finds most recent attempt log, handles missing
- main(): argparse dispatch
"""

import json
import sys
import tempfile
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "src"))

import yaml

from scheduler.queue import Attempt, Job, QueueLoadError, safe_log_path


def model_preference():
    return [{"provider": "gemini", "model": "gemini-3-flash-preview", "meter": "gemini.tiers.flash"}]


class TestMainArgparse(unittest.TestCase):
    """main(): argparse dispatch and error handling."""

    def test_status_subcommand(self):
        from scheduler.cli import main
        tmpdir = tempfile.mkdtemp()
        qp = Path(tmpdir) / "jobs.yaml"
        try:
            with patch("scheduler.cli.DEFAULT_QUEUE_PATH", qp), \
                 patch("scheduler.cli._load_state", return_value={"meters": {}}), \
                 patch("scheduler.queue.DEFAULT_QUEUE_PATH", qp), \
                 patch("sys.stdout", new_callable=StringIO):
                rc = main(["status"])
                self.assertEqual(rc, 0)
        finally:
            import shutil
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_add_requires_file_flag(self):
        """add without --file should exit 2."""
        from scheduler.cli import main
        with self.assertRaises(SystemExit) as ctx:
            main(["add"])
        self.assertEqual(ctx.exception.code, 2)

    def test_unknown_subcommand_exits(self):
        from scheduler.cli import main
        with self.assertRaises(SystemExit):
            main(["nonexistent-cmd"])

    def test_no_subcommand_exits(self):
        from scheduler.cli import main
        with self.assertRaises(SystemExit):
            main([])

    def test_run_once_rejects_zero_max_jobs(self):
        from scheduler.cli import main
        with self.assertRaises(SystemExit) as ctx:
            main(["run-once", "--max-jobs", "0"])
        self.assertEqual(ctx.exception.code, 2)


class TestCmdStatus(unittest.TestCase):
    """cmd_status: human-readable and JSON output."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="eco-cli-test-")
        self.queue_path = Path(self.tmpdir) / "jobs.yaml"

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_human_output_with_empty_queue(self):
        from scheduler.cli import cmd_status
        ns = MagicMock()
        ns.json = False
        with patch("scheduler.cli.DEFAULT_QUEUE_PATH", self.queue_path), \
             patch("scheduler.cli._load_state", return_value={"meters": {}}), \
             patch("scheduler.cli.load_queue", return_value=[]), \
             patch("sys.stdout", new_callable=StringIO):
            rc = cmd_status(ns)
        self.assertEqual(rc, 0)

    def test_json_output_with_jobs(self):
        from scheduler.cli import cmd_status
        jobs = [
            Job(id="j1", status="pending"),
            Job(id="j2", status="completed"),
        ]

        ns = MagicMock()
        ns.json = True
        with patch("scheduler.cli.DEFAULT_QUEUE_PATH", self.queue_path), \
             patch("scheduler.cli._load_state", return_value={"meters": {}}), \
             patch("scheduler.cli.load_queue", return_value=jobs), \
             patch("sys.stdout", new_callable=StringIO) as mock_out:
            rc = cmd_status(ns)
        self.assertEqual(rc, 0)
        output = mock_out.getvalue()
        data = json.loads(output)
        self.assertEqual(data["total_jobs"], 2)
        self.assertIn("by_status", data)
        self.assertEqual(data["by_status"]["pending"], 1)
        self.assertEqual(data["by_status"]["completed"], 1)

    def test_status_queue_load_error_returns_2(self):
        from scheduler.cli import cmd_status
        ns = MagicMock()
        ns.json = False
        err = QueueLoadError(self.queue_path, "invalid YAML")
        with patch("scheduler.cli._load_state", return_value={"meters": {}}), \
             patch("scheduler.cli.load_queue", side_effect=err), \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_status(ns)
        self.assertEqual(rc, 2)
        self.assertIn("cannot load scheduler queue", mock_err.getvalue())


class TestCmdAdd(unittest.TestCase):
    """cmd_add: YAML file parsing."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="eco-cli-test-")
        self.queue_path = Path(self.tmpdir) / "jobs.yaml"

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_adds_from_yaml_file(self):
        from scheduler.cli import cmd_add
        yaml_file = Path(self.tmpdir) / "input.yaml"
        yaml_file.write_text(yaml.dump({
            "jobs": [
                {"id": "yaml-job-1", "priority": "P0", "model_preference": model_preference()},
                {"id": "yaml-job-2", "priority": "P2", "model_preference": model_preference()},
            ]
        }))

        ns = MagicMock()
        ns.file = str(yaml_file)
        with patch("scheduler.cli.add_jobs", return_value=2) as mock_add, \
             patch("sys.stdout", new_callable=StringIO):
            rc = cmd_add(ns)
        self.assertEqual(rc, 0)
        mock_add.assert_called_once()
        added_jobs = mock_add.call_args[0][0]
        self.assertEqual(len(added_jobs), 2)
        self.assertEqual(added_jobs[0].id, "yaml-job-1")

    def test_errors_on_missing_file(self):
        from scheduler.cli import cmd_add
        ns = MagicMock()
        ns.file = "/nonexistent/file.yaml"
        with patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_add(ns)
        self.assertEqual(rc, 2)
        self.assertIn("error: /nonexistent/file.yaml: file not found", mock_err.getvalue())

    def test_errors_on_invalid_yaml(self):
        from scheduler.cli import cmd_add
        yaml_file = Path(self.tmpdir) / "bad.yaml"
        yaml_file.write_text("jobs: [\n")

        ns = MagicMock()
        ns.file = str(yaml_file)
        with patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_add(ns)
        self.assertEqual(rc, 2)
        self.assertIn(f"error: {yaml_file}: invalid YAML", mock_err.getvalue())

    def test_errors_on_invalid_job_validation(self):
        from scheduler.cli import cmd_add
        yaml_file = Path(self.tmpdir) / "invalid-job.yaml"
        yaml_file.write_text(
            yaml.safe_dump({"jobs": [{"id": "bad", "model_preference": model_preference(), "earliest_iso": 123}]})
        )

        ns = MagicMock()
        ns.file = str(yaml_file)
        with patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_add(ns)
        self.assertEqual(rc, 2)
        self.assertIn(f"error: {yaml_file}: jobs[0]: earliest_iso must be a string", mock_err.getvalue())

    def test_errors_on_existing_queue_load_error(self):
        from scheduler.cli import cmd_add
        from scheduler.queue import QueueLoadError
        yaml_file = Path(self.tmpdir) / "input.yaml"
        yaml_file.write_text(yaml.safe_dump({"jobs": [{"id": "valid", "model_preference": model_preference()}]}))
        queue_file = Path(self.tmpdir) / "queue.yaml"

        ns = MagicMock()
        ns.file = str(yaml_file)
        with patch("scheduler.cli.add_jobs", side_effect=QueueLoadError(queue_file, "jobs must be a list")), \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_add(ns)
        self.assertEqual(rc, 2)
        self.assertIn(f"error: {queue_file}: jobs must be a list", mock_err.getvalue())


class TestCmdTail(unittest.TestCase):
    """cmd_tail: print most recent attempt log."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="eco-cli-test-")
        self.queue_path = Path(self.tmpdir) / "jobs.yaml"

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_no_attempts_returns_1(self):
        from scheduler.cli import cmd_tail
        ns = MagicMock()
        ns.id = None
        with patch("scheduler.cli.load_queue", return_value=[Job(id="no-attempts")]), \
             patch("sys.stderr", new_callable=StringIO):
            rc = cmd_tail(ns)
        self.assertEqual(rc, 1)

    def test_specific_job_id(self):
        from scheduler.cli import cmd_tail
        log_dir = Path(self.tmpdir) / "logs"
        log_dir.mkdir()
        log_path = safe_log_path(log_dir, "with-log", "gemini", "stdout")
        log_path.write_text("test output\n")

        job = Job(
            id="with-log",
            attempts=[Attempt(
                iso="2026-05-20T12:00:00+00:00",
                provider="gemini",
                model="flash",
                meter="g.f",
                ok=True,
                log_path=str(log_path),
            )],
        )

        ns = MagicMock()
        ns.id = "with-log"
        with patch("scheduler.cli.load_queue", return_value=[job]), \
             patch("scheduler.cli.DEFAULT_RESULTS_DIR", log_dir), \
             patch("sys.stdout", new_callable=StringIO) as mock_out:
            rc = cmd_tail(ns)
        self.assertEqual(rc, 0)
        self.assertIn("test output", mock_out.getvalue())

    def test_missing_log_file_returns_1(self):
        from scheduler.cli import cmd_tail
        job = Job(
            id="missing-log",
            attempts=[Attempt(
                iso="2026-05-20T12:00:00+00:00",
                provider="gemini",
                model="flash",
                meter="g.f",
                ok=True,
                log_path="/nonexistent/path.log",
            )],
        )

        ns = MagicMock()
        ns.id = "missing-log"
        with patch("scheduler.cli.load_queue", return_value=[job]), \
             patch("scheduler.cli.DEFAULT_RESULTS_DIR", Path(self.tmpdir) / "logs"), \
             patch("sys.stderr", new_callable=StringIO):
            rc = cmd_tail(ns)
        self.assertEqual(rc, 1)

    def test_tail_refuses_outside_stored_log_path_even_when_missing(self):
        from scheduler.cli import cmd_tail
        job = Job(
            id="outside-log",
            attempts=[Attempt(
                iso="2026-05-20T12:00:00+00:00",
                provider="gemini",
                model="flash",
                meter="g.f",
                ok=True,
                log_path="/tmp/not-eco-scheduler.log",
            )],
        )

        ns = MagicMock()
        ns.id = "outside-log"
        with patch("scheduler.cli.load_queue", return_value=[job]), \
             patch("scheduler.cli.DEFAULT_RESULTS_DIR", Path(self.tmpdir) / "logs"), \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_tail(ns)
        self.assertEqual(rc, 1)
        self.assertIn("refusing log path outside scheduler log dir", mock_err.getvalue())

    def test_tail_refuses_unsafe_provider(self):
        from scheduler.cli import cmd_tail
        job = Job(
            id="bad-log",
            attempts=[Attempt(
                iso="2026-05-20T12:00:00+00:00",
                provider="../escape",
                model="flash",
                meter="g.f",
                ok=True,
                log_path="/etc/passwd",
            )],
        )
        ns = MagicMock()
        ns.id = "bad-log"
        with patch("scheduler.cli.load_queue", return_value=[job]), \
             patch("scheduler.cli.DEFAULT_RESULTS_DIR", Path(self.tmpdir) / "logs"), \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_tail(ns)
        self.assertEqual(rc, 1)
        self.assertIn("unsafe scheduler log path", mock_err.getvalue())

    def test_tail_queue_load_error_returns_2(self):
        from scheduler.cli import cmd_tail
        ns = MagicMock()
        ns.id = None
        err = QueueLoadError(self.queue_path, "invalid YAML")
        with patch("scheduler.cli.load_queue", side_effect=err), \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_tail(ns)
        self.assertEqual(rc, 2)
        self.assertIn("cannot load scheduler queue", mock_err.getvalue())


class TestCmdRunOnce(unittest.TestCase):
    """cmd_run_once: delegates to tick()."""

    def test_prints_summary_json(self):
        from scheduler.cli import cmd_run_once
        mock_summary = {
            "tick_iso": "2026-05-20T12:00:00+00:00",
            "total_jobs": 0,
            "fired": [],
            "gated": [],
        }

        ns = MagicMock()
        ns.max_jobs = 1
        with patch("scheduler.cli.tick", return_value=mock_summary), \
             patch("sys.stdout", new_callable=StringIO) as mock_out:
            rc = cmd_run_once(ns)
        self.assertEqual(rc, 0)
        data = json.loads(mock_out.getvalue())
        self.assertIn("tick_iso", data)

    def test_returns_nonzero_when_attempt_failed(self):
        from scheduler.cli import cmd_run_once
        mock_summary = {
            "tick_iso": "2026-05-20T12:00:00+00:00",
            "total_jobs": 1,
            "fired": [{"id": "bad", "ok": False, "error_kind": "io_error"}],
            "gated": [],
        }

        ns = MagicMock()
        ns.max_jobs = 1
        with patch("scheduler.cli.tick", return_value=mock_summary), \
             patch("sys.stdout", new_callable=StringIO):
            rc = cmd_run_once(ns)
        self.assertEqual(rc, 1)

    def test_queue_load_error_returns_2(self):
        from scheduler.cli import cmd_run_once
        ns = MagicMock()
        ns.max_jobs = 1
        err = QueueLoadError(Path("/tmp/jobs.yaml"), "invalid YAML")
        with patch("scheduler.cli.tick", side_effect=err), \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_run_once(ns)
        self.assertEqual(rc, 2)
        self.assertIn("error: cannot load scheduler queue:", mock_err.getvalue())
        self.assertIn("invalid YAML", mock_err.getvalue())

    def test_rejects_non_positive_max_jobs(self):
        from scheduler.cli import cmd_run_once
        ns = MagicMock()
        ns.max_jobs = 0
        with patch("scheduler.cli.tick") as mock_tick, \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_run_once(ns)
        self.assertEqual(rc, 2)
        mock_tick.assert_not_called()
        self.assertIn("--max-jobs", mock_err.getvalue())


class TestCmdDrainSeedCancel(unittest.TestCase):
    """cmd_drain/cmd_seed/cmd_cancel behavior."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="eco-cli-test-")
        self.queue_path = Path(self.tmpdir) / "jobs.yaml"

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_drain_returns_nonzero_on_failed_attempt(self):
        from scheduler.cli import cmd_drain
        ns = MagicMock()
        ns.max_ticks = 3
        ns.interval_s = 0
        summary = {"fired": [{"id": "bad", "ok": False}], "gated": []}
        with patch("scheduler.cli.tick", return_value=summary), \
             patch("sys.stdout", new_callable=StringIO), \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_drain(ns)
        self.assertEqual(rc, 1)
        self.assertIn("scheduler attempt failed", mock_err.getvalue())

    def test_drain_exits_when_queue_idle(self):
        from scheduler.cli import cmd_drain
        ns = MagicMock()
        ns.max_ticks = 3
        ns.interval_s = 0
        summary = {"fired": [], "gated": []}
        with patch("scheduler.cli.tick", return_value=summary), \
             patch("sys.stdout", new_callable=StringIO):
            rc = cmd_drain(ns)
        self.assertEqual(rc, 0)

    def test_drain_queue_load_error_returns_2(self):
        from scheduler.cli import cmd_drain
        ns = MagicMock()
        ns.max_ticks = 3
        ns.interval_s = 0
        err = QueueLoadError(Path("/tmp/jobs.yaml"), "jobs must be a list")
        with patch("scheduler.cli.tick", side_effect=err), \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_drain(ns)
        self.assertEqual(rc, 2)
        self.assertIn("error: cannot load scheduler queue:", mock_err.getvalue())
        self.assertIn("jobs must be a list", mock_err.getvalue())

    def test_drain_rejects_invalid_tick_arguments(self):
        from scheduler.cli import cmd_drain
        ns = MagicMock()
        ns.max_ticks = 0
        ns.interval_s = -1
        with patch("scheduler.cli.tick") as mock_tick, \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_drain(ns)
        self.assertEqual(rc, 2)
        mock_tick.assert_not_called()
        self.assertIn("--max-ticks", mock_err.getvalue())

    def test_seed_imports_yaml_files(self):
        from scheduler.cli import cmd_seed
        seed_dir = Path(self.tmpdir) / "seeds"
        seed_dir.mkdir()
        (seed_dir / "jobs.yaml").write_text(
            yaml.safe_dump({"jobs": [{"id": "seed-job", "model_preference": model_preference()}]})
        )
        ns = MagicMock()
        ns.dir = str(seed_dir)
        with patch("scheduler.cli.add_jobs", return_value=1) as mock_add, \
             patch("sys.stdout", new_callable=StringIO) as mock_out:
            rc = cmd_seed(ns)
        self.assertEqual(rc, 0)
        mock_add.assert_called_once()
        self.assertIn("Seed complete", mock_out.getvalue())

    def test_seed_queue_load_error_returns_2(self):
        from scheduler.cli import cmd_seed
        seed_dir = Path(self.tmpdir) / "seeds"
        seed_dir.mkdir()
        (seed_dir / "jobs.yaml").write_text(
            yaml.safe_dump({"jobs": [{"id": "seed-job", "model_preference": model_preference()}]})
        )
        ns = MagicMock()
        ns.dir = str(seed_dir)
        err = QueueLoadError(self.queue_path, "invalid YAML")
        with patch("scheduler.cli.add_jobs", side_effect=err), \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_seed(ns)
        self.assertEqual(rc, 2)
        self.assertIn("cannot load scheduler queue", mock_err.getvalue())

    def test_seed_returns_nonzero_on_bad_job_entry(self):
        from scheduler.cli import cmd_seed
        seed_dir = Path(self.tmpdir) / "seeds"
        seed_dir.mkdir()
        (seed_dir / "jobs.yaml").write_text(yaml.safe_dump({"jobs": [{"id": "bad-seed"}]}))

        ns = MagicMock()
        ns.dir = str(seed_dir)
        with patch("scheduler.cli.add_jobs") as mock_add, \
             patch("sys.stdout", new_callable=StringIO) as mock_out, \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_seed(ns)

        self.assertEqual(rc, 1)
        mock_add.assert_not_called()
        self.assertIn("invalid", mock_out.getvalue())
        self.assertIn("bad job entry 0", mock_err.getvalue())

    def test_seed_returns_nonzero_on_parse_error(self):
        from scheduler.cli import cmd_seed
        seed_dir = Path(self.tmpdir) / "seeds"
        seed_dir.mkdir()
        (seed_dir / "bad.yaml").write_text("jobs: [\n")

        ns = MagicMock()
        ns.dir = str(seed_dir)
        with patch("sys.stdout", new_callable=StringIO) as mock_out, \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_seed(ns)

        self.assertEqual(rc, 1)
        self.assertIn("invalid", mock_out.getvalue())
        self.assertIn("parse error", mock_err.getvalue())

    def test_cancel_marks_job_cancelled(self):
        from scheduler.cli import cmd_cancel
        job = Job(id="cancel-me", status="pending")
        ns = MagicMock()
        ns.id = "cancel-me"
        ns.force = False
        with patch("scheduler.cli.load_queue", return_value=[job]), \
             patch("scheduler.cli.save_queue") as mock_save, \
             patch("sys.stdout", new_callable=StringIO) as mock_out:
            rc = cmd_cancel(ns)
        self.assertEqual(rc, 0)
        self.assertEqual(job.status, "cancelled")
        mock_save.assert_called_once()
        self.assertIn("cancelled job", mock_out.getvalue())

    def test_cancel_queue_load_error_returns_2(self):
        from scheduler.cli import cmd_cancel
        ns = MagicMock()
        ns.id = "cancel-me"
        ns.force = False
        err = QueueLoadError(self.queue_path, "invalid YAML")
        with patch("scheduler.cli.load_queue", side_effect=err), \
             patch("sys.stderr", new_callable=StringIO) as mock_err:
            rc = cmd_cancel(ns)
        self.assertEqual(rc, 2)
        self.assertIn("cannot load scheduler queue", mock_err.getvalue())


if __name__ == "__main__":
    unittest.main()
