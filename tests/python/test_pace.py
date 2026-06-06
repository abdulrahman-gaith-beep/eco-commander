"""Plain-Python (no pytest dep) tests for src/poller/pace.py.

Run via:
    python3 tests/python/test_pace.py
or:
    PYTHONPATH=src python3 -m unittest discover -s tests/python -p 'test_*.py' -v
"""
import sys
import unittest
from pathlib import Path

# Make `import poller.pace` work whether invoked from repo root or tests dir.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from poller.pace import (
    THRESHOLDS,
    build_pace_fields,
    classify_pace,
    cycle_elapsed_pct,
)


class PaceTests(unittest.TestCase):
    def test_cycle_elapsed_pct_edge_cases(self):
        self.assertEqual(cycle_elapsed_pct(100, 100, 110), 0.0)  # start>=end
        self.assertEqual(cycle_elapsed_pct(200, 100, 150), 0.0)  # span<0
        self.assertEqual(cycle_elapsed_pct(100, 200, 90), 0.0)   # now<start
        self.assertEqual(cycle_elapsed_pct(100, 200, 100), 0.0)
        self.assertEqual(cycle_elapsed_pct(100, 200, 200), 100.0)  # now>=end
        self.assertEqual(cycle_elapsed_pct(100, 200, 210), 100.0)
        self.assertEqual(cycle_elapsed_pct(100, 50, 75), 0.0)    # span<=0
        self.assertEqual(cycle_elapsed_pct(100, 200, 150), 50.0)  # normal

    def test_classify_pace_idle(self):
        res = classify_pace(0.5, 4.9)
        self.assertEqual(res["label"], "idle")
        self.assertEqual(res["glyph"], "💤")

    def test_classify_pace_ahead(self):
        res = classify_pace(50.0, 30.0)
        self.assertEqual(res["label"], "ahead")
        self.assertEqual(res["glyph"], "🐎")
        self.assertEqual(res["delta_pp"], 20.0)

    def test_classify_pace_behind(self):
        res = classify_pace(30.0, 50.0)
        self.assertEqual(res["label"], "behind")
        self.assertEqual(res["glyph"], "🐢")
        self.assertEqual(res["delta_pp"], -20.0)

    def test_classify_pace_on_pace(self):
        res = classify_pace(45.0, 50.0)
        self.assertEqual(res["label"], "on-pace")
        self.assertEqual(res["glyph"], "🟢")

    def test_build_pace_fields(self):
        fields = build_pace_fields(50.0, 1000, 2000, 1500)
        self.assertEqual(fields["target_pct"], 50.0)
        self.assertEqual(fields["reset_epoch"], 2000)
        self.assertEqual(fields["pace_label"], "on-pace")

    def test_thresholds_locked(self):
        self.assertEqual(THRESHOLDS["use_it_or_lose_it"]["delta_pp_max"], -15.0)
        self.assertEqual(THRESHOLDS["throttle"]["delta_pp_min"], 25.0)
        self.assertEqual(THRESHOLDS["hard_wall"]["pct_min"], 95.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
