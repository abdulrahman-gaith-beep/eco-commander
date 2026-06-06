"""Tests for scheduler.routing — meter_status + pick_candidate."""

from __future__ import annotations

import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from scheduler.routing import meter_available, meter_status, pick_candidate


def _state(meters: dict) -> dict:
    return {"meters": meters}


class MeterStatusTests(unittest.TestCase):
    def test_unknown_meter_optimistic_available(self) -> None:
        s = meter_status({"meters": {}}, "nonexistent.tier")
        self.assertTrue(s.available)
        self.assertEqual(s.kind, "unknown")

    def test_hard_wall_blocks_until_reset(self) -> None:
        future = time.time() + 3600
        s = meter_status(
            _state({"gemini.tiers.pro": {"last_kind": "hard_wall", "last_reset_epoch": future}}),
            "gemini.tiers.pro",
        )
        self.assertFalse(s.available)
        self.assertEqual(s.reason, "hard_wall")
        self.assertGreater(s.seconds_until_available, 3500)

    def test_hard_wall_clears_after_reset_epoch(self) -> None:
        past = time.time() - 60
        s = meter_status(
            _state({"x.y": {"last_kind": "hard_wall", "last_reset_epoch": past}}),
            "x.y",
        )
        # Logic: if reset_epoch <= now, even hard_wall is treated as cleared
        self.assertTrue(s.available)

    def test_throttle_cooldown_60s(self) -> None:
        s = meter_status(
            _state(
                {
                    "codex.weekly": {
                        "last_kind": "throttle",
                        "last_fired_ts": time.time() - 10,
                        "last_reset_epoch": time.time() + 100,
                    }
                }
            ),
            "codex.weekly",
        )
        self.assertFalse(s.available)
        self.assertEqual(s.reason, "throttle_cooldown")

    def test_throttle_clears_after_60s(self) -> None:
        s = meter_status(
            _state(
                {
                    "codex.weekly": {
                        "last_kind": "throttle",
                        "last_fired_ts": time.time() - 120,
                        "last_reset_epoch": time.time() + 100,
                    }
                }
            ),
            "codex.weekly",
        )
        self.assertTrue(s.available)

    def test_use_it_or_lose_it_always_available(self) -> None:
        s = meter_status(
            _state(
                {
                    "claude.session": {
                        "last_kind": "use_it_or_lose_it",
                        "last_fired_ts": time.time(),
                        "last_reset_epoch": time.time() - 1000,
                    }
                }
            ),
            "claude.session",
        )
        self.assertTrue(s.available)

    def test_meter_available_shortcut(self) -> None:
        self.assertTrue(meter_available({"meters": {}}, "any"))


class PickCandidateTests(unittest.TestCase):
    LADDER = [
        {"provider": "codex", "model": "gpt-5.5", "meter": "codex.session"},
        {"provider": "gemini", "model": "gemini-3.1-pro-preview", "meter": "gemini.tiers.pro"},
        {"provider": "claude", "model": "sonnet", "meter": "claude.session"},
    ]

    def test_picks_first_available_rung(self) -> None:
        state = _state(
            {
                "codex.session": {"last_kind": "use_it_or_lose_it", "last_reset_epoch": 0},
                "gemini.tiers.pro": {"last_kind": "hard_wall", "last_reset_epoch": time.time() + 3600},
                "claude.session": {"last_kind": "use_it_or_lose_it", "last_reset_epoch": 0},
            }
        )
        choice = pick_candidate(self.LADDER, state)
        self.assertIsNotNone(choice.candidate)
        candidate = choice.candidate
        assert candidate is not None
        self.assertEqual(candidate["provider"], "codex")
        self.assertEqual(choice.skipped, [])

    def test_skips_walled_falls_to_next(self) -> None:
        state = _state(
            {
                "codex.session": {"last_kind": "hard_wall", "last_reset_epoch": time.time() + 1800},
                "gemini.tiers.pro": {"last_kind": "hard_wall", "last_reset_epoch": time.time() + 3600},
                "claude.session": {"last_kind": "use_it_or_lose_it", "last_reset_epoch": 0},
            }
        )
        choice = pick_candidate(self.LADDER, state)
        self.assertIsNotNone(choice.candidate)
        candidate = choice.candidate
        assert candidate is not None
        self.assertEqual(candidate["provider"], "claude")
        self.assertEqual(len(choice.skipped), 2)

    def test_all_walled_returns_none_and_min_wait(self) -> None:
        state = _state(
            {
                "codex.session": {"last_kind": "hard_wall", "last_reset_epoch": time.time() + 1000},
                "gemini.tiers.pro": {"last_kind": "hard_wall", "last_reset_epoch": time.time() + 5000},
                "claude.session": {"last_kind": "hard_wall", "last_reset_epoch": time.time() + 200},
            }
        )
        choice = pick_candidate(self.LADDER, state)
        self.assertIsNone(choice.candidate)
        # Shortest wait wins → claude.session at ~200s
        self.assertLess(choice.next_available_in_s, 300)
        self.assertGreater(choice.next_available_in_s, 100)


class QueueTests(unittest.TestCase):
    """Round-trip Job ↔ YAML + pending-job filtering."""

    def test_pending_ready_respects_earliest_iso(self) -> None:
        from scheduler.queue import Job, pending_ready_jobs

        future = "2099-01-01T00:00:00+00:00"
        past = "2000-01-01T00:00:00+00:00"
        jobs = [
            Job(id="a", earliest_iso=past, priority="P1"),
            Job(id="b", earliest_iso=future, priority="P0"),
            Job(id="c", earliest_iso="", priority="P2"),
        ]
        ready = pending_ready_jobs(jobs)
        ids = {j.id for j in ready}
        self.assertIn("a", ids)
        self.assertIn("c", ids)
        self.assertNotIn("b", ids)

    def test_pending_ready_respects_dependencies(self) -> None:
        from scheduler.queue import Job, pending_ready_jobs

        jobs = [
            Job(id="a", status="pending"),
            Job(id="b", status="pending", depends_on_jobs=["a"]),
            Job(id="c", status="completed"),
            Job(id="d", status="pending", depends_on_jobs=["c"]),
        ]
        ready = pending_ready_jobs(jobs)
        ids = {j.id for j in ready}
        self.assertIn("a", ids)
        self.assertNotIn("b", ids)  # a is not yet completed
        self.assertIn("d", ids)  # c is completed

    def test_gated_by_quota_jobs_are_re_eligible(self) -> None:
        """Regression: gated_by_quota must be re-checked each tick.

        Before the fix, pending_ready_jobs only matched status=='pending',
        meaning a job set to 'gated_by_quota' was stuck forever.
        """
        from scheduler.queue import Job, pending_ready_jobs

        jobs = [
            Job(id="normal", status="pending"),
            Job(id="gated", status="gated_by_quota"),
            Job(id="done", status="completed"),
            Job(id="dead", status="failed"),
            Job(id="active", status="running"),
        ]
        ready = pending_ready_jobs(jobs)
        ids = {j.id for j in ready}
        self.assertIn("normal", ids)
        self.assertIn("gated", ids, "gated_by_quota jobs must be re-eligible")
        self.assertNotIn("done", ids)
        self.assertNotIn("dead", ids)
        self.assertNotIn("active", ids)


if __name__ == "__main__":
    unittest.main(verbosity=2)
