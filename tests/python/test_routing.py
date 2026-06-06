"""Regression tests for defensive scheduler routing."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "src"))

from scheduler.routing import meter_status


class TestDefensiveMeterStatus(unittest.TestCase):
    def test_non_dict_meters_is_unknown_available(self):
        status = meter_status({"meters": ["bad"]}, "gemini.flash", now=100.0)
        self.assertTrue(status.available)
        self.assertEqual(status.kind, "unknown")

    def test_non_dict_meter_entry_is_unknown_available(self):
        status = meter_status({"meters": {"gemini.flash": "bad"}}, "gemini.flash", now=100.0)
        self.assertTrue(status.available)
        self.assertEqual(status.kind, "unknown")

    def test_non_numeric_meter_fields_fall_back_to_zero(self):
        status = meter_status(
            {
                "meters": {
                    "gemini.flash": {
                        "last_kind": "hard_wall",
                        "last_reset_epoch": "not-a-number",
                        "last_fired_ts": object(),
                    }
                }
            },
            "gemini.flash",
            now=100.0,
        )
        self.assertTrue(status.available)
        self.assertEqual(status.last_reset_epoch, 0.0)
        self.assertEqual(status.last_fired_ts, 0.0)

    def test_throttle_blocks_until_cooldown(self):
        status = meter_status(
            {"meters": {"gemini.flash": {"last_kind": "throttle", "last_fired_ts": 90}}},
            "gemini.flash",
            now=100.0,
        )
        self.assertFalse(status.available)
        self.assertEqual(status.reason, "throttle_cooldown")
        self.assertEqual(status.seconds_until_available, 50)

    def test_hard_wall_blocks_until_reset(self):
        status = meter_status(
            {"meters": {"gemini.flash": {"last_kind": "hard_wall", "last_reset_epoch": 160}}},
            "gemini.flash",
            now=100.0,
        )
        self.assertFalse(status.available)
        self.assertEqual(status.reason, "hard_wall")
        self.assertEqual(status.seconds_until_available, 60)


if __name__ == "__main__":
    unittest.main()
