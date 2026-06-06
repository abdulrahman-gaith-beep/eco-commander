"""Tests for scheduler.queue — YAML-backed job queue.

Covers:
- Job.from_dict / to_dict roundtrip
- Unknown keys dropped (forward compat)
- load_queue / save_queue with atomic writes
- add_jobs deduplication
- update_job raises KeyError on missing
- pending_ready_jobs: earliest_iso, deps, priority sort, gated_by_quota
"""

import stat
import sys
import tempfile
import unittest
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "src"))

import yaml

from scheduler.queue import (
    Attempt,
    Job,
    QueueLoadError,
    add_jobs,
    load_queue,
    pending_ready_jobs,
    safe_log_path,
    save_queue,
    update_job,
    validate_timeout_s,
    validate_workdir,
)


def model_preference():
    return [{"provider": "gemini", "model": "gemini-3-flash-preview", "meter": "gemini.tiers.flash"}]


class TestJobSerialization(unittest.TestCase):
    """Job.from_dict / to_dict roundtrip and edge cases."""

    def test_roundtrip_minimal(self):
        job = Job(id="test-1")
        d = job.to_dict()
        restored = Job.from_dict(d)
        self.assertEqual(restored.id, "test-1")
        self.assertEqual(restored.status, "pending")
        self.assertEqual(restored.priority, "P2")

    def test_roundtrip_full(self):
        job = Job(
            id="full-job",
            project="eco-commander",
            workdir="/tmp/test",
            template="research",
            template_vars={"prompt": "analyze this"},
            model_preference=[{"provider": "gemini", "model": "flash", "meter": "gemini.flash"}],
            earliest_iso="2026-05-20T12:00:00+00:00",
            priority="P0",
            timeout_s=300,
            retry={"max": 5, "backoff_s": [30, 60]},
            status="pending",
            notes="test note",
            requires_confirm=True,
            depends_on_jobs=["dep-1", "dep-2"],
        )
        d = job.to_dict()
        restored = Job.from_dict(d)
        self.assertEqual(restored.id, "full-job")
        self.assertEqual(restored.project, "eco-commander")
        self.assertEqual(restored.priority, "P0")
        self.assertEqual(restored.timeout_s, 300)
        self.assertTrue(restored.requires_confirm)
        self.assertEqual(restored.depends_on_jobs, ["dep-1", "dep-2"])
        self.assertEqual(len(restored.model_preference), 1)

    def test_unknown_keys_dropped(self):
        """Forward compat: future schema fields don't crash old code."""
        d = {
            "id": "compat-test",
            "model_preference": model_preference(),
            "unknown_future_field": True,
            "another_new_thing": [1, 2, 3],
        }
        job = Job.from_dict(d)
        self.assertEqual(job.id, "compat-test")
        self.assertFalse(hasattr(job, "unknown_future_field"))

    def test_to_dict_drops_empty_fields(self):
        """Compact YAML: empty strings and empty lists are pruned."""
        job = Job(id="compact")
        d = job.to_dict()
        self.assertNotIn("started_iso", d)
        self.assertNotIn("completed_iso", d)
        self.assertNotIn("last_error", d)
        self.assertNotIn("attempts", d)
        self.assertNotIn("depends_on_jobs", d)
        self.assertNotIn("requires_confirm", d)

    def test_attempts_deserialized(self):
        d = {
            "id": "with-attempts",
            "model_preference": model_preference(),
            "attempts": [
                {
                    "iso": "2026-05-20T12:00:00+00:00",
                    "provider": "gemini",
                    "model": "flash",
                    "meter": "gemini.flash",
                    "ok": True,
                    "duration_s": 45.2,
                },
                {
                    "iso": "2026-05-20T13:00:00+00:00",
                    "provider": "codex",
                    "model": "gpt-5.5",
                    "meter": "codex.session",
                    "ok": False,
                    "error_kind": "hard_wall",
                },
            ],
        }
        job = Job.from_dict(d)
        self.assertEqual(len(job.attempts), 2)
        self.assertIsInstance(job.attempts[0], Attempt)
        self.assertTrue(job.attempts[0].ok)
        self.assertEqual(job.attempts[1].error_kind, "hard_wall")

    def test_rejects_non_list_model_preference(self):
        with self.assertRaises(ValueError) as ctx:
            Job.from_dict({"id": "bad-ladder", "model_preference": {"provider": "gemini"}})
        self.assertIn("model_preference must be a list", str(ctx.exception))

    def test_rejects_missing_or_empty_model_preference(self):
        with self.assertRaises(ValueError) as ctx:
            Job.from_dict({"id": "missing-ladder"})
        self.assertIn("model_preference is required", str(ctx.exception))

        with self.assertRaises(ValueError) as ctx:
            Job(id="empty-ladder", model_preference=[])
        self.assertIn("model_preference must contain at least one provider", str(ctx.exception))

    def test_rejects_invalid_model_preference_rung(self):
        invalid_ladders = [
            ["gemini"],
            [{"provider": "gemini", "model": "flash", "meter": 123}],
            [{"provider": "gemini", "model": None, "meter": "g.f"}],
            [{"provider": 42, "model": "flash", "meter": "g.f"}],
            [{"provider": "gemini", "model": "", "meter": "g.f"}],
            [{"provider": "gemini", "model": "flash\nmalformed", "meter": "g.f"}],
        ]
        for ladder in invalid_ladders:
            with self.subTest(ladder=ladder):
                with self.assertRaises(ValueError):
                    Job.from_dict({"id": "bad-ladder", "model_preference": ladder})

    def test_rejects_non_string_earliest_iso(self):
        with self.assertRaises(ValueError) as ctx:
            Job.from_dict({"id": "bad-earliest", "model_preference": model_preference(), "earliest_iso": 123})
        self.assertIn("earliest_iso must be a string", str(ctx.exception))

    def test_rejects_non_mapping_template_vars(self):
        for value in (["prompt"], "prompt", 42):
            with self.subTest(value=value):
                with self.assertRaises(ValueError) as ctx:
                    Job.from_dict(
                        {"id": "bad-template-vars", "model_preference": model_preference(), "template_vars": value}
                    )
                self.assertIn("template_vars must be a mapping", str(ctx.exception))

    def test_rejects_malformed_depends_on_jobs(self):
        invalid_values = [
            "dep-1",
            {"id": "dep-1"},
            [123],
            ["dep-1", None],
            ["../escape"],
        ]
        for value in invalid_values:
            with self.subTest(value=value):
                with self.assertRaises(ValueError) as ctx:
                    Job.from_dict({"id": "bad-deps", "model_preference": model_preference(), "depends_on_jobs": value})
                self.assertIn("depends_on_jobs", str(ctx.exception))

    def test_rejects_path_traversal_job_id(self):
        with self.assertRaises(ValueError):
            Job(id="../escape")

    def test_rejects_empty_or_slash_job_id(self):
        for value in ("", "bad/id", ".hidden"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    Job(id=value)

    def test_normalizes_string_timeout(self):
        job = Job(id="timeout-string", timeout_s="30")
        self.assertEqual(job.timeout_s, 30)

    def test_rejects_timeout_outside_bounds(self):
        for value in (0, -1, 21601, "oops"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    validate_timeout_s(value)

    def test_safe_log_path_rejects_traversal(self):
        with tempfile.TemporaryDirectory(prefix="eco-log-test-") as tmp:
            with self.assertRaises(ValueError):
                safe_log_path(tmp, "../escape", "gemini", "stdout")

    def test_workdir_rejects_prohibited_paths_textually(self):
        with tempfile.TemporaryDirectory(prefix="eco-home-test-") as tmp_home:
            home = Path(tmp_home)
            with patch("pathlib.Path.home", return_value=home):
                for path in (
                    home / "Library" / "Mobile Documents" / "example",
                    home / "Library" / "CloudStorage" / "iCloud Drive" / "example",
                    home / ".ssh" / "config",
                    Path("/Users") / "tg" / "example",
                ):
                    with self.subTest(path=str(path)):
                        with self.assertRaises(ValueError):
                            validate_workdir(str(path))


class TestQueuePersistence(unittest.TestCase):
    """load_queue / save_queue: YAML file, atomic writes."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="eco-queue-test-")
        self.queue_path = Path(self.tmpdir) / "jobs.yaml"

    def tearDown(self):
        import shutil

        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_load_empty_returns_empty_list(self):
        jobs = load_queue(self.queue_path)
        self.assertEqual(jobs, [])

    def test_save_then_load_roundtrip(self):
        jobs = [
            Job(id="j1", priority="P0"),
            Job(id="j2", priority="P2", status="completed"),
        ]
        save_queue(jobs, self.queue_path)
        loaded = load_queue(self.queue_path)
        self.assertEqual(len(loaded), 2)
        self.assertEqual(loaded[0].id, "j1")
        self.assertEqual(loaded[0].priority, "P0")
        self.assertEqual(loaded[1].status, "completed")

    def test_file_permissions_0600(self):
        save_queue([Job(id="perm-test")], self.queue_path)
        mode = stat.S_IMODE(self.queue_path.stat().st_mode)
        self.assertEqual(mode, 0o600, f"expected 0o600, got {oct(mode)}")

    def test_lock_file_permissions_0600(self):
        save_queue([Job(id="lock-perm")], self.queue_path)
        lock = self.queue_path.with_suffix(self.queue_path.suffix + ".lock")
        mode = stat.S_IMODE(lock.stat().st_mode)
        self.assertEqual(mode, 0o600, f"expected 0o600, got {oct(mode)}")

    def test_overwrite_existing(self):
        save_queue([Job(id="v1")], self.queue_path)
        save_queue([Job(id="v2"), Job(id="v3")], self.queue_path)
        loaded = load_queue(self.queue_path)
        self.assertEqual(len(loaded), 2)
        self.assertEqual(loaded[0].id, "v2")

    def test_load_empty_yaml_file(self):
        self.queue_path.parent.mkdir(parents=True, exist_ok=True)
        self.queue_path.write_text("")
        jobs = load_queue(self.queue_path)
        self.assertEqual(jobs, [])

    def test_load_queue_wraps_yaml_errors(self):
        self.queue_path.parent.mkdir(parents=True, exist_ok=True)
        self.queue_path.write_text("jobs: [\n")
        with self.assertRaises(QueueLoadError) as ctx:
            load_queue(self.queue_path)
        self.assertEqual(ctx.exception.path, self.queue_path)
        self.assertIn("invalid YAML", ctx.exception.reason)

    def test_load_queue_wraps_validation_errors(self):
        self.queue_path.parent.mkdir(parents=True, exist_ok=True)
        self.queue_path.write_text(
            yaml.safe_dump({"jobs": [{"id": "bad", "model_preference": model_preference(), "earliest_iso": 123}]})
        )
        with self.assertRaises(QueueLoadError) as ctx:
            load_queue(self.queue_path)
        self.assertEqual(ctx.exception.path, self.queue_path)
        self.assertIn("jobs[0]: earliest_iso must be a string", ctx.exception.reason)

    def test_yaml_format_is_readable(self):
        save_queue([Job(id="readable")], self.queue_path)
        raw = self.queue_path.read_text()
        data = yaml.safe_load(raw)
        self.assertIn("version", data)
        self.assertEqual(data["version"], 1)
        self.assertIn("jobs", data)


class TestAddJobs(unittest.TestCase):
    """add_jobs: deduplication, count returned."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="eco-queue-test-")
        self.queue_path = Path(self.tmpdir) / "jobs.yaml"

    def tearDown(self):
        import shutil

        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_adds_to_empty_queue(self):
        count = add_jobs([Job(id="new-1"), Job(id="new-2")], self.queue_path)
        self.assertEqual(count, 2)
        self.assertEqual(len(load_queue(self.queue_path)), 2)

    def test_skips_duplicate_ids(self):
        save_queue([Job(id="existing")], self.queue_path)
        count = add_jobs(
            [Job(id="existing"), Job(id="fresh")],
            self.queue_path,
        )
        self.assertEqual(count, 1)  # only "fresh" added
        self.assertEqual(len(load_queue(self.queue_path)), 2)

    def test_all_duplicates_returns_zero(self):
        save_queue([Job(id="a"), Job(id="b")], self.queue_path)
        count = add_jobs([Job(id="a"), Job(id="b")], self.queue_path)
        self.assertEqual(count, 0)

    def test_add_jobs_holds_single_lock_across_load_and_save(self):
        from scheduler import queue as queue_mod

        state = {"locked": False, "lock_entries": 0}

        @contextmanager
        def fake_flock(_path):
            self.assertFalse(state["locked"])
            state["locked"] = True
            state["lock_entries"] += 1
            try:
                yield
            finally:
                state["locked"] = False

        def fake_load(_path):
            self.assertTrue(state["locked"])
            return [Job(id="existing")]

        def fake_save(jobs, _path):
            self.assertTrue(state["locked"])
            self.assertEqual([j.id for j in jobs], ["existing", "fresh"])

        with patch.object(queue_mod, "_flock", fake_flock), \
             patch.object(queue_mod, "_load_queue_unlocked", side_effect=fake_load), \
             patch.object(queue_mod, "_save_queue_unlocked", side_effect=fake_save):
            count = queue_mod.add_jobs([Job(id="existing"), Job(id="fresh")], self.queue_path)

        self.assertEqual(count, 1)
        self.assertEqual(state["lock_entries"], 1)


class TestUpdateJob(unittest.TestCase):
    """update_job: replace by id, KeyError on missing."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="eco-queue-test-")
        self.queue_path = Path(self.tmpdir) / "jobs.yaml"

    def tearDown(self):
        import shutil

        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_updates_existing_job(self):
        save_queue([Job(id="target", status="pending")], self.queue_path)
        updated = Job(id="target", status="completed")
        update_job(updated, self.queue_path)
        loaded = load_queue(self.queue_path)
        self.assertEqual(loaded[0].status, "completed")

    def test_raises_keyerror_on_missing(self):
        save_queue([Job(id="other")], self.queue_path)
        with self.assertRaises(KeyError) as ctx:
            update_job(Job(id="nonexistent"), self.queue_path)
        self.assertIn("nonexistent", str(ctx.exception))

    def test_update_job_holds_single_lock_across_load_and_save(self):
        from scheduler import queue as queue_mod

        state = {"locked": False, "lock_entries": 0}

        @contextmanager
        def fake_flock(_path):
            self.assertFalse(state["locked"])
            state["locked"] = True
            state["lock_entries"] += 1
            try:
                yield
            finally:
                state["locked"] = False

        def fake_load(_path):
            self.assertTrue(state["locked"])
            return [Job(id="target", status="pending")]

        def fake_save(jobs, _path):
            self.assertTrue(state["locked"])
            self.assertEqual(jobs[0].status, "completed")

        with patch.object(queue_mod, "_flock", fake_flock), \
             patch.object(queue_mod, "_load_queue_unlocked", side_effect=fake_load), \
             patch.object(queue_mod, "_save_queue_unlocked", side_effect=fake_save):
            queue_mod.update_job(Job(id="target", status="completed"), self.queue_path)

        self.assertEqual(state["lock_entries"], 1)


class TestPendingReadyJobs(unittest.TestCase):
    """pending_ready_jobs: filtering, dependency resolution, priority sort."""

    def _now(self):
        return 1716200000.0  # fixed epoch for determinism

    def test_returns_pending_jobs(self):
        jobs = [
            Job(id="pending", status="pending"),
            Job(id="completed", status="completed"),
            Job(id="running", status="running"),
        ]
        ready = pending_ready_jobs(jobs, now=self._now())
        ids = [j.id for j in ready]
        self.assertIn("pending", ids)
        self.assertNotIn("completed", ids)
        self.assertNotIn("running", ids)

    def test_includes_gated_by_quota(self):
        """gated_by_quota jobs should be re-evaluated."""
        jobs = [Job(id="gated", status="gated_by_quota")]
        ready = pending_ready_jobs(jobs, now=self._now())
        self.assertEqual(len(ready), 1)

    def test_respects_earliest_iso_in_future(self):
        future = datetime(2099, 1, 1, tzinfo=timezone.utc).isoformat()
        jobs = [Job(id="future", status="pending", earliest_iso=future)]
        ready = pending_ready_jobs(jobs, now=self._now())
        self.assertEqual(len(ready), 0)

    def test_allows_earliest_iso_in_past(self):
        past = datetime(2020, 1, 1, tzinfo=timezone.utc).isoformat()
        jobs = [Job(id="past", status="pending", earliest_iso=past)]
        ready = pending_ready_jobs(jobs, now=self._now())
        self.assertEqual(len(ready), 1)

    def test_respects_dependencies(self):
        jobs = [
            Job(id="dep", status="completed"),
            Job(id="blocked", status="pending", depends_on_jobs=["dep", "missing"]),
            Job(id="unblocked", status="pending", depends_on_jobs=["dep"]),
        ]
        ready = pending_ready_jobs(jobs, now=self._now())
        ids = [j.id for j in ready]
        self.assertNotIn("blocked", ids)
        self.assertIn("unblocked", ids)

    def test_priority_sort(self):
        jobs = [
            Job(id="p2", status="pending", priority="P2"),
            Job(id="p0", status="pending", priority="P0"),
            Job(id="p1", status="pending", priority="P1"),
        ]
        ready = pending_ready_jobs(jobs, now=self._now())
        self.assertEqual(ready[0].id, "p0")
        self.assertEqual(ready[1].id, "p1")
        self.assertEqual(ready[2].id, "p2")

    def test_empty_list(self):
        ready = pending_ready_jobs([], now=self._now())
        self.assertEqual(len(ready), 0)

    def test_invalid_earliest_iso_marks_failed(self):
        jobs = [Job(id="bad-iso", status="pending", earliest_iso="not-a-date")]
        ready = pending_ready_jobs(jobs, now=self._now())
        self.assertEqual(len(ready), 0)
        self.assertEqual(jobs[0].status, "failed")
        self.assertIn("invalid earliest_iso", jobs[0].last_error)


if __name__ == "__main__":
    unittest.main()
