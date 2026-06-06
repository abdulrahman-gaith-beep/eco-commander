"""Unit tests for src/poller/notify.py."""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Make `import poller.notify` work whether invoked from repo root or tests dir.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from poller.notify import (
    _as_string_literal,
    _classify,
    _format_body,
    _resolve,
    _should_fire,
    evaluate,
)


class TestNotify(unittest.TestCase):
    def test_classify_hard_wall(self):
        # pct >= 95
        meter = {"pct": 95, "target_pct": 50, "pace_delta_pp": 45}
        self.assertEqual(_classify(meter), 'hard_wall')

    def test_classify_throttle(self):
        # pct>=80, target<=60, delta>=25
        meter = {"pct": 85, "target_pct": 50, "pace_delta_pp": 35}
        self.assertEqual(_classify(meter), 'throttle')

    def test_classify_use_it_or_lose_it(self):
        # target>=80, delta<=-15, remaining>=15
        # remaining = 100 - pct. So pct must be <= 85.
        meter = {"pct": 60, "target_pct": 80, "pace_delta_pp": -20}
        self.assertEqual(_classify(meter), 'use_it_or_lose_it')

    def test_classify_healthy(self):
        meter = {"pct": 20, "target_pct": 20, "pace_delta_pp": 0}
        self.assertIsNone(_classify(meter))

    def test_should_fire_debounce(self):
        now = 1000000.0
        # DEBOUNCE_HOURS = {"use_it_or_lose_it": 12, "throttle": 4, "hard_wall": 1}

        # hard_wall: 1 hour = 3600s
        meter_state = {"last_fired_ts": now - 3500}
        self.assertFalse(_should_fire(meter_state, "hard_wall", now))

        meter_state = {"last_fired_ts": now - 3700}
        self.assertTrue(_should_fire(meter_state, "hard_wall", now))

    def test_hard_wall_preempts_lower_severity_cooldown(self):
        now = 1000000.0
        meter_state = {
            "last_kind": "throttle",
            "last_fired_ts": now - 10,
            "last_fired_by_kind": {"throttle": now - 10},
        }
        self.assertTrue(_should_fire(meter_state, "hard_wall", now))

    def test_applescript_string_literal_escapes_quotes(self):
        self.assertEqual(_as_string_literal('say "hi" \\ ok'), '"say \\"hi\\" \\\\ ok"')

    @patch.dict(os.environ, {"ECO_NOTIFICATIONS": "0"})
    def test_evaluate_disabled(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"ECO_HOME": tmp, "ECO_NOTIFICATIONS": "0"}):
                res = evaluate({})
                self.assertTrue(res.get("skipped_global"))

    def test_evaluate_disabled_still_writes_meter_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            merged = {
                "codex": {
                    "session": {
                        "pct": 96,
                        "target_pct": 50,
                        "pace_delta_pp": 46,
                        "reset_epoch": 2000000,
                    }
                }
            }
            with patch.dict(os.environ, {"ECO_HOME": tmp, "ECO_NOTIFICATIONS": "0"}):
                res = evaluate(merged)
                self.assertTrue(res.get("skipped_global"))

            state_path = Path(tmp) / "state" / "notify.json"
            state = json.loads(state_path.read_text(encoding="utf-8"))
            meter = state["meters"]["codex.session"]
            self.assertEqual(meter["last_kind"], "hard_wall")
            self.assertEqual(meter["current_kind"], "hard_wall")

    def test_format_body_resets_in(self):
        meta = {"tool": "Claude", "meter": "Session", "model_class": "Opus"}

        # No 'Resets in' when resets_in is '—'
        data_no_reset = {"pct": 50, "target_pct": 50, "resets_in": "—"}
        body_no_reset = _format_body(meta, data_no_reset, "hard_wall")
        self.assertNotIn("Resets in", body_no_reset)

        # DOES include 'Resets in' when resets_in is '4h 33m'
        data_with_reset = {"pct": 50, "target_pct": 50, "resets_in": "4h 33m"}
        body_with_reset = _format_body(meta, data_with_reset, "use_it_or_lose_it")
        self.assertIn("Resets in 4h 33m", body_with_reset)

    def test_resolve_nested(self):
        merged = {"gemini": {"tiers": {"pro": {"pct": 42}}}}
        resolved = _resolve(merged, "gemini.tiers.pro")
        self.assertEqual(resolved, {"pct": 42})

    def test_resolve_missing(self):
        merged = {"a": {"b": 1}}
        self.assertIsNone(_resolve(merged, "a.c"))
        self.assertIsNone(_resolve(merged, "x.y"))

if __name__ == "__main__":
    unittest.main(verbosity=2)
