"""Tests for src/poller/codex.py JSONL token accounting.

Expanded 2026-05-22: 13 tests covering window boundaries, edge cases,
empty files, malformed data, multi-session aggregation, and output shape.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from poller import (
    caps,
    codex,
)


def _iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat().replace("+00:00", "Z")


def _line(ts: float, total: int, inp: int, out: int, cached: int = 0,
          reasoning: int = 0) -> str:
    return json.dumps({
        "timestamp": _iso(ts),
        "total_tokens": total,
        "input_tokens": inp,
        "output_tokens": out,
        "cached_input_tokens": cached,
        "reasoning_output_tokens": reasoning,
    })


class CodexJsonlTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.sessions = Path(self.tmp.name) / "sessions"
        self.sessions.mkdir()
        self.now = datetime(2026, 5, 22, 12, 0, tzinfo=timezone.utc).timestamp()

    def tearDown(self):
        self.tmp.cleanup()

    def _write_session(self, name: str, lines: list[str]) -> None:
        path = self.sessions / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def test_window_boundaries_subtract_pre_window_baselines(self):
        week_since = self.now - 7 * 24 * 3600
        session_since = self.now - 5 * 3600
        self._write_session("one.jsonl", [
            _line(week_since - 100, 1000, 500, 500, 0, 0),
            _line(session_since - 100, 1500, 800, 600, 100, 50),
            _line(self.now - 100, 2000, 1000, 800, 200, 80),
        ])

        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions), \
             patch("time.time", return_value=self.now):
            result = codex.collect()

        self.assertTrue(result["ok"])
        self.assertEqual(result["weekly"]["tokens"], 1000)
        self.assertEqual(result["weekly"]["input_tokens"], 500)
        self.assertEqual(result["weekly"]["output_tokens"], 300)
        self.assertEqual(result["weekly"]["cached_input_tokens"], 200)
        self.assertEqual(result["weekly"]["reasoning_output_tokens"], 80)

        self.assertEqual(result["session"]["tokens"], 500)
        self.assertEqual(result["session"]["input_tokens"], 200)
        self.assertEqual(result["session"]["output_tokens"], 200)
        self.assertEqual(result["session"]["cached_input_tokens"], 100)
        self.assertEqual(result["session"]["reasoning_output_tokens"], 30)

    def test_session_baseline_can_precede_week_window(self):
        week_since = self.now - 7 * 24 * 3600
        self._write_session("long-running.jsonl", [
            _line(week_since - 3600, 10_000, 6_000, 3_000, 1_000, 100),
            _line(self.now - 100, 10_500, 6_200, 3_200, 1_100, 120),
        ])

        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions), \
             patch("time.time", return_value=self.now):
            result = codex.collect()

        self.assertTrue(result["ok"])
        self.assertEqual(result["weekly"]["tokens"], 500)
        self.assertEqual(result["session"]["tokens"], 500)
        self.assertEqual(result["session"]["input_tokens"], 200)
        self.assertEqual(result["session"]["output_tokens"], 200)
        self.assertEqual(result["session"]["cached_input_tokens"], 100)
        self.assertEqual(result["session"]["reasoning_output_tokens"], 20)

    def test_missing_sessions_dir_returns_empty_error(self):
        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions / "missing"):
            result = codex.collect()
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "sessions dir missing")

    # ── New tests (T-002 audit task) ──────────────────────────────

    def test_empty_jsonl_file_returns_zero_tokens(self):
        """An empty JSONL file should not crash and should produce zero tokens."""
        self._write_session("empty.jsonl", [""])
        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions), \
             patch("time.time", return_value=self.now):
            result = codex.collect()
        self.assertTrue(result["ok"])
        self.assertEqual(result["session"]["tokens"], 0)
        self.assertEqual(result["weekly"]["tokens"], 0)

    def test_malformed_jsonl_lines_are_skipped(self):
        """Lines that aren't valid JSON should be silently skipped."""
        self._write_session("bad.jsonl", [
            "NOT VALID JSON {{{",
            '{"garbage": true}',
            _line(self.now - 60, 500, 300, 200, 0, 0),
        ])
        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions), \
             patch("time.time", return_value=self.now):
            result = codex.collect()
        self.assertTrue(result["ok"])
        self.assertGreater(result["weekly"]["tokens"], 0)

    def test_lines_without_total_tokens_are_skipped(self):
        """Lines that have a timestamp but no total_tokens should be ignored."""
        self._write_session("no_total.jsonl", [
            json.dumps({"timestamp": _iso(self.now - 60), "input_tokens": 100}),
            _line(self.now - 30, 200, 100, 100, 0, 0),
        ])
        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions), \
             patch("time.time", return_value=self.now):
            result = codex.collect()
        self.assertTrue(result["ok"])
        # Only the valid line should count
        self.assertGreater(result["weekly"]["tokens"], 0)

    def test_lines_with_only_total_tokens(self):
        """Older session files may only have total_tokens — no breakdown fields."""
        self._write_session("minimal.jsonl", [
            json.dumps({
                "timestamp": _iso(self.now - 60),
                "total_tokens": 1000,
            }),
        ])
        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions), \
             patch("time.time", return_value=self.now):
            result = codex.collect()
        self.assertTrue(result["ok"])
        self.assertGreater(result["weekly"]["tokens"], 0)
        # Breakdown fields should default to 0
        self.assertEqual(result["weekly"]["input_tokens"], 0)

    def test_multiple_session_files_aggregated(self):
        """Tokens from multiple session files should sum together."""
        self._write_session("session1.jsonl", [
            _line(self.now - 100, 500, 300, 200, 0, 0),
        ])
        self._write_session("session2.jsonl", [
            _line(self.now - 50, 800, 400, 400, 0, 0),
        ])
        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions), \
             patch("time.time", return_value=self.now):
            result = codex.collect()
        self.assertTrue(result["ok"])
        self.assertEqual(result["weekly"]["tokens"], 1300)

    def test_subdirectory_sessions_discovered(self):
        """Sessions in subdirectories should be found (recursive glob)."""
        subdir = self.sessions / "subproject" / "abc123"
        subdir.mkdir(parents=True)
        (subdir / "events.jsonl").write_text(
            _line(self.now - 60, 750, 400, 350, 0, 0) + "\n"
        )
        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions), \
             patch("time.time", return_value=self.now):
            result = codex.collect()
        self.assertTrue(result["ok"])
        self.assertEqual(result["weekly"]["tokens"], 750)

    def test_unknown_cap_emits_null_percentage(self):
        """Public unknown caps should not produce bogus percentages."""
        huge = caps.CODEX_PRO_WEEKLY_TOKENS * 10
        self._write_session("huge.jsonl", [
            _line(self.now - 60, huge, huge // 2, huge // 2, 0, 0),
        ])
        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions), \
             patch("time.time", return_value=self.now):
            result = codex.collect()
        self.assertTrue(result["ok"])
        self.assertEqual(result["weekly"]["tokens"], huge)
        self.assertIsNone(result["session"]["pct"])
        self.assertIsNone(result["weekly"]["pct"])
        self.assertEqual(result["session"]["pct_display"], "—")
        self.assertEqual(result["weekly"]["pct_display"], "—")
        self.assertEqual(result["session"]["cap_status"], "unknown")
        self.assertEqual(result["weekly"]["cap_status"], "unknown")
        self.assertEqual(result["session"]["pace_label"], "unknown")
        self.assertEqual(result["weekly"]["pace_label"], "unknown")

    def test_output_shape_has_required_fields(self):
        """Verify the output dict shape matches widget expectations."""
        self._write_session("shape.jsonl", [
            _line(self.now - 60, 100, 50, 50, 0, 0),
        ])
        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions), \
             patch("time.time", return_value=self.now):
            result = codex.collect()
        # Top-level required keys
        self.assertIn("tool", result)
        self.assertEqual(result["tool"], "codex")
        self.assertIn("ok", result)
        self.assertIn("source", result)
        self.assertEqual(result["source"], "jsonl")
        self.assertIn("session", result)
        self.assertIn("weekly", result)
        self.assertIn("last_event_ts", result)
        # Per-window required keys
        for window in ("session", "weekly"):
            w = result[window]
            self.assertIn("tokens", w)
            self.assertIn("pct", w)
            self.assertIn("resets_in", w)
            self.assertIn("cap", w)
            self.assertIn("input_tokens", w)
            self.assertIn("output_tokens", w)
            self.assertIn("cached_input_tokens", w)
            self.assertIn("reasoning_output_tokens", w)

    def test_error_shape_matches_collect_shape(self):
        """Error responses should have the same top-level keys for widget compat."""
        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions / "missing"):
            result = codex.collect()
        self.assertFalse(result["ok"])
        self.assertIn("session", result)
        self.assertIn("weekly", result)
        self.assertIn("last_event_ts", result)
        self.assertEqual(result["session"]["tokens"], 0)
        self.assertEqual(result["weekly"]["tokens"], 0)

    def test_all_events_before_windows_produce_zero(self):
        """If all JSONL events are older than both windows, tokens should be 0."""
        old_ts = self.now - 30 * 24 * 3600  # 30 days ago
        self._write_session("old.jsonl", [
            _line(old_ts, 5000, 2500, 2500, 0, 0),
        ])
        with patch.object(codex, "CODEX_SESSIONS_DIR", self.sessions), \
             patch("time.time", return_value=self.now):
            result = codex.collect()
        self.assertTrue(result["ok"])
        self.assertEqual(result["weekly"]["tokens"], 0)
        self.assertEqual(result["session"]["tokens"], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
