"""Tests for src/poller/comments.py.
Run via: python3 tests/python/test_comments.py
"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from poller.comments import evaluate

# ---------------------------------------------------------------------------
# Helpers: build minimal merged_usage / prev_usage dicts that comments.py
# can resolve via _resolve().  The only key that matters for triggering is
# claude.session.pct (one real METER key is enough for most tests).
# ---------------------------------------------------------------------------

def _usage(pct: float) -> dict:
    """Return a merged-usage dict with claude.session.pct set to *pct*."""
    return {"claude": {"session": {"pct": pct}}}


# A catalog that has at least one entry per tier so the function never returns
# None due to an empty options list.
FAKE_CATALOG = '{"tiers": {"gentle": ["gentle-msg"], "bold": ["bold-msg"], "alarmed": ["alarmed-msg"]}}'


class TestComments(unittest.TestCase):

    def setUp(self):
        os.environ["ECO_COMMENTS"] = "1"

    def tearDown(self):
        os.environ.pop("ECO_COMMENTS", None)

    # ------------------------------------------------------------------
    # Gate tests (no catalog needed)
    # ------------------------------------------------------------------

    def test_evaluate_disabled(self):
        """Feature flag off → always None."""
        del os.environ["ECO_COMMENTS"]
        self.assertIsNone(evaluate(_usage(50.0), _usage(40.0), {}))

    def test_evaluate_no_prev(self):
        """No previous snapshot → None."""
        self.assertIsNone(evaluate(_usage(50.0), None, {}))

    def test_evaluate_no_trigger(self):
        """Delta < 5 → no comment."""
        self.assertIsNone(evaluate(_usage(43.0), _usage(40.0), {}))

    # ------------------------------------------------------------------
    # Tier-selection tests  (mock catalog + stable time)
    # ------------------------------------------------------------------

    @patch("poller.comments.time.time", return_value=1_000_000.0)
    @patch("pathlib.Path.read_text", return_value=FAKE_CATALOG)
    @patch("pathlib.Path.exists", return_value=False)   # force bundled path
    def test_evaluate_gentle(self, _exists, _read, _time):
        """Delta 7 → gentle tier."""
        res = evaluate(_usage(47.0), _usage(40.0), {})
        self.assertEqual(res, "gentle-msg")

    @patch("poller.comments.time.time", return_value=1_000_000.0)
    @patch("pathlib.Path.read_text", return_value=FAKE_CATALOG)
    @patch("pathlib.Path.exists", return_value=False)
    def test_evaluate_bold(self, _exists, _read, _time):
        """Delta 15 → bold tier."""
        res = evaluate(_usage(55.0), _usage(40.0), {})
        self.assertEqual(res, "bold-msg")

    @patch("poller.comments.time.time", return_value=1_000_000.0)
    @patch("pathlib.Path.read_text", return_value=FAKE_CATALOG)
    @patch("pathlib.Path.exists", return_value=False)
    def test_evaluate_alarmed(self, _exists, _read, _time):
        """Delta 25 → alarmed tier."""
        res = evaluate(_usage(65.0), _usage(40.0), {})
        self.assertEqual(res, "alarmed-msg")

    # ------------------------------------------------------------------
    # Cooldown tests
    # ------------------------------------------------------------------

    @patch("poller.comments.time.time", return_value=1_000_000.0)
    @patch("pathlib.Path.read_text", return_value=FAKE_CATALOG)
    @patch("pathlib.Path.exists", return_value=False)
    def test_evaluate_gentle_cooldown(self, _exists, _read, mock_time):
        """After a gentle comment, the same tier is suppressed within 30 min."""
        # gentle fired 100s ago (well inside 1800s window) → suppressed
        now = 1_000_000.0
        state = {"last_comment_ts": {"gentle": now - 100, "bold": 0.0, "alarmed": 0.0}}
        res = evaluate(_usage(47.0), _usage(40.0), state)
        self.assertIsNone(res)

    @patch("poller.comments.time.time", return_value=1_000_000.0)
    @patch("pathlib.Path.read_text", return_value=FAKE_CATALOG)
    @patch("pathlib.Path.exists", return_value=False)
    def test_evaluate_alarmed_preempts_gentle_cooldown(self, _exists, _read, mock_time):
        """alarmed tier ignores gentle cooldown; fires if its own 5m window is clear."""
        # gentle fired 100s ago → last_any blocks non-alarmed (< 300s)
        # alarmed's own cooldown last fired >300s ago → should still fire
        now = 1_000_000.0
        state = {"last_comment_ts": {"gentle": now - 100, "bold": 0.0, "alarmed": now - 400}}
        res = evaluate(_usage(65.0), _usage(40.0), state)
        self.assertEqual(res, "alarmed-msg")

    @patch("poller.comments.time.time", return_value=1_000_000.0)
    @patch("pathlib.Path.read_text", return_value=FAKE_CATALOG)
    @patch("pathlib.Path.exists", return_value=False)
    def test_evaluate_alarmed_cooldown_respected(self, _exists, _read, mock_time):
        """alarmed fires within its own 5-min window → suppressed."""
        now = 1_000_000.0
        state = {"last_comment_ts": {"gentle": 0.0, "bold": 0.0, "alarmed": now - 100}}
        res = evaluate(_usage(65.0), _usage(40.0), state)
        self.assertIsNone(res)

    # ------------------------------------------------------------------
    # State mutation test
    # ------------------------------------------------------------------

    @patch("poller.comments.time.time", return_value=1_000_000.0)
    @patch("pathlib.Path.read_text", return_value=FAKE_CATALOG)
    @patch("pathlib.Path.exists", return_value=False)
    def test_state_updated_after_comment(self, _exists, _read, mock_time):
        """evaluate() updates last_comment_ts[tier] and last_comment_text in state."""
        state = {}
        evaluate(_usage(47.0), _usage(40.0), state)
        self.assertIn("last_comment_ts", state)
        self.assertAlmostEqual(state["last_comment_ts"]["gentle"], 1_000_000.0)
        self.assertEqual(state.get("last_comment_text"), "gentle-msg")

    @patch("poller.comments.time.time", return_value=1_000_000.0)
    def test_user_catalog_respects_eco_home(self, _time):
        """User comments override is read from ECO_HOME, not hardcoded ~/.eco."""
        previous = os.environ.get("ECO_HOME")
        with tempfile.TemporaryDirectory() as tmp:
            os.environ["ECO_HOME"] = tmp
            cfg_dir = Path(tmp) / "config"
            cfg_dir.mkdir()
            (cfg_dir / "comments.json").write_text(
                json.dumps({"tiers": {"gentle": ["eco-home-msg"], "bold": [], "alarmed": []}}),
                encoding="utf-8",
            )
            try:
                self.assertEqual(evaluate(_usage(47.0), _usage(40.0), {}), "eco-home-msg")
            finally:
                if previous is None:
                    os.environ.pop("ECO_HOME", None)
                else:
                    os.environ["ECO_HOME"] = previous


if __name__ == "__main__":
    unittest.main(verbosity=2)
