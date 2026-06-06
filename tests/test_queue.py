"""Tests for eco-commander scheduler.queue — validates security-critical
input validation, path traversal protection, and atomic write behavior.
"""

import os
import stat
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest
import yaml

# Bootstrap PYTHONPATH for queue imports
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from scheduler.queue import (
    DEFAULT_MODEL_PREFERENCE,
    Job,
    QueueLoadError,
    _default_model_preference,
    load_queue,
    pending_ready_jobs,
    safe_log_path,
    save_queue,
    validate_job_id,
    validate_model_preference,
    validate_timeout_s,
    validate_workdir,
)


# ---------------------------------------------------------------------------
# validate_job_id — prevents path traversal in log filenames
# ---------------------------------------------------------------------------

class TestValidateJobId:
    def test_simple_id(self):
        assert validate_job_id("my-job.01") == "my-job.01"

    def test_rejects_empty(self):
        with pytest.raises(ValueError):
            validate_job_id("")

    def test_rejects_dot_dot(self):
        with pytest.raises(ValueError):
            validate_job_id("a..b")

    def test_rejects_slashes(self):
        with pytest.raises(ValueError):
            validate_job_id("../../etc/passwd")

    def test_rejects_spaces(self):
        with pytest.raises(ValueError):
            validate_job_id("my job")

    def test_rejects_too_long(self):
        with pytest.raises(ValueError):
            validate_job_id("a" * 200)

    def test_rejects_non_string(self):
        with pytest.raises(ValueError):
            validate_job_id(42)


# ---------------------------------------------------------------------------
# validate_timeout_s — bounds enforcement
# ---------------------------------------------------------------------------

class TestValidateTimeout:
    def test_normal(self):
        assert validate_timeout_s(300) == 300

    def test_minimum(self):
        assert validate_timeout_s(1) == 1

    def test_rejects_zero(self):
        with pytest.raises(ValueError):
            validate_timeout_s(0)

    def test_rejects_negative(self):
        with pytest.raises(ValueError):
            validate_timeout_s(-1)

    def test_rejects_too_large(self):
        with pytest.raises(ValueError):
            validate_timeout_s(999_999)

    def test_rejects_boolean(self):
        with pytest.raises(ValueError):
            validate_timeout_s(True)

    def test_coerces_string(self):
        assert validate_timeout_s("600") == 600


# ---------------------------------------------------------------------------
# validate_workdir — privacy surface blocklist
# ---------------------------------------------------------------------------

class TestValidateWorkdir:
    def test_normal_path(self, tmp_path):
        assert validate_workdir(str(tmp_path)) == tmp_path.resolve()

    def test_rejects_icloud(self):
        icloud = str(Path.home() / "Library" / "Mobile Documents" / "test")
        with pytest.raises(ValueError, match="prohibited"):
            validate_workdir(icloud)

    def test_rejects_ssh(self):
        ssh = str(Path.home() / ".ssh" / "keys")
        with pytest.raises(ValueError, match="prohibited"):
            validate_workdir(ssh)

    def test_rejects_sibling_user(self):
        with pytest.raises(ValueError, match="prohibited"):
            validate_workdir("/Users/tg/projects")

    def test_rejects_keychains(self):
        with pytest.raises(ValueError, match="prohibited"):
            validate_workdir(str(Path.home() / "Library" / "Keychains"))


# ---------------------------------------------------------------------------
# safe_log_path — prevents path escape
# ---------------------------------------------------------------------------

class TestSafeLogPath:
    def test_normal(self, tmp_path):
        p = safe_log_path(tmp_path, "job-01", "gemini", "stdout")
        assert p.parent == tmp_path
        assert "job-01" in p.name
        assert p.name.endswith(".stdout")

    def test_rejects_traversal_in_job_id(self, tmp_path):
        with pytest.raises(ValueError):
            safe_log_path(tmp_path, "../../../etc/passwd", "gemini", "stdout")

    def test_rejects_traversal_in_provider(self, tmp_path):
        with pytest.raises(ValueError):
            safe_log_path(tmp_path, "job-01", "../../../etc", "stdout")

    def test_rejects_invalid_stream(self, tmp_path):
        with pytest.raises(ValueError, match="stream must be stdout or stderr"):
            safe_log_path(tmp_path, "job-01", "gemini", "stdin")


# ---------------------------------------------------------------------------
# Job round-trip — YAML serialization preserves data
# ---------------------------------------------------------------------------

class TestJobRoundTrip:
    def test_from_dict_minimal(self):
        j = Job.from_dict({
            "id": "test-001",
            "model_preference": [
                {"provider": "gemini", "model": "gemini-3-flash-preview", "meter": "gemini.tiers.flash"}
            ],
        })
        assert j.id == "test-001"
        assert j.status == "pending"
        assert j.timeout_s == 600

    def test_round_trip(self):
        original = Job.from_dict({
            "id": "rt-001",
            "project": "test-project",
            "template": "audit",
            "template_vars": {"target_path": "/tmp/test"},
            "model_preference": [
                {"provider": "gemini", "model": "gemini-3-flash-preview", "meter": "gemini.tiers.flash"}
            ],
            "priority": "P1",
            "timeout_s": 300,
        })
        d = original.to_dict()
        restored = Job.from_dict(d)
        assert restored.id == original.id
        assert restored.project == original.project
        assert restored.priority == original.priority

    def test_rejects_missing_model_preference(self):
        with pytest.raises(ValueError, match="model_preference"):
            Job.from_dict({"id": "bad-001"})


# ---------------------------------------------------------------------------
# Queue file I/O
# ---------------------------------------------------------------------------

class TestQueueIO:
    def test_load_missing_returns_empty(self, tmp_path):
        result = load_queue(tmp_path / "nonexistent.yaml")
        assert result == []

    def test_save_and_load(self, tmp_path):
        queue_path = tmp_path / "jobs.yaml"
        jobs = [Job.from_dict({
            "id": "io-001",
            "model_preference": _default_model_preference(),
        })]
        save_queue(jobs, queue_path)
        loaded = load_queue(queue_path)
        assert len(loaded) == 1
        assert loaded[0].id == "io-001"

    def test_load_invalid_yaml_raises(self, tmp_path):
        bad_path = tmp_path / "bad.yaml"
        bad_path.write_text(":::\nnot valid yaml: [[[", encoding="utf-8")
        with pytest.raises(QueueLoadError):
            load_queue(bad_path)

    def test_save_creates_parent_dirs(self, tmp_path):
        deep = tmp_path / "a" / "b" / "c" / "jobs.yaml"
        save_queue([], deep)
        assert deep.exists()


# ---------------------------------------------------------------------------
# pending_ready_jobs — scheduling logic
# ---------------------------------------------------------------------------

class TestPendingReadyJobs:
    def _make_job(self, id, status="pending", **kw):
        return Job.from_dict({
            "id": id,
            "model_preference": _default_model_preference(),
            "status": status,
            **kw,
        })

    def test_pending_returned(self):
        jobs = [self._make_job("a")]
        assert len(pending_ready_jobs(jobs)) == 1

    def test_completed_not_returned(self):
        jobs = [self._make_job("a", status="completed")]
        assert len(pending_ready_jobs(jobs)) == 0

    def test_priority_ordering(self):
        jobs = [
            self._make_job("low", priority="P3"),
            self._make_job("high", priority="P0"),
            self._make_job("mid", priority="P2"),
        ]
        ready = pending_ready_jobs(jobs)
        assert [j.id for j in ready] == ["high", "mid", "low"]

    def test_deps_block_until_completed(self):
        jobs = [
            self._make_job("dep", status="completed"),
            self._make_job("child", depends_on_jobs=["dep"]),
            self._make_job("blocked", depends_on_jobs=["missing"]),
        ]
        ready = pending_ready_jobs(jobs)
        assert len(ready) == 1
        assert ready[0].id == "child"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
