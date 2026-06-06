"""Tests for src/poller/claude.py multi-account iteration (collect_multi).

Run via:
    pytest tests/python/test_claude_multi_account.py -v
    python3 tests/python/test_claude_multi_account.py
"""
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from poller import claude

_STUB_COLLECT = {
    "tool": "claude",
    "ok": True,
    "source": "jsonl",
    "session": {"pct": 12.3, "input_tokens": 1000, "output_tokens": 500,
                "cache_creation_tokens": 0, "cache_read_tokens": 0,
                "by_model": {"sonnet": 1500}},
    "weekly": {"pct": 45.6, "input_tokens": 10000, "output_tokens": 5000,
               "cache_creation_tokens": 100, "cache_read_tokens": 200,
               "by_model": {"opus": 4000, "sonnet": 11000}},
    "last_event_ts": 1700000000,
}


class ClaudeMultiAccountTests(unittest.TestCase):

    def setUp(self):
        # Ensure deterministic slug list and default server-truth state.
        self._tmp = tempfile.TemporaryDirectory()
        self._env = patch.dict(
            os.environ,
            {"ECO_CLAUDE_ACCOUNTS": "primary,secondary", "ECO_HOME": self._tmp.name},
        )
        self._env.start()

    def tearDown(self):
        self._env.stop()
        self._tmp.cleanup()

    @patch("poller.claude.collect", return_value=dict(_STUB_COLLECT))
    def test_collect_multi_returns_two_accounts(self, _mock_collect):
        result = claude.collect_multi()
        self.assertIn("per_account", result)
        accounts = result["per_account"]
        self.assertEqual(len(accounts), 2)

        # Same top-level shape as collect() — widget shouldn't break.
        self.assertEqual(result["tool"], "claude")
        self.assertTrue(result["ok"])
        self.assertIn("session", result)
        self.assertIn("weekly", result)

    @patch("poller.claude.collect", return_value=dict(_STUB_COLLECT))
    def test_primary_account_carries_real_data(self, _mock_collect):
        result = claude.collect_multi()
        primary = result["per_account"][0]
        self.assertEqual(primary["slug"], "primary")
        self.assertEqual(primary["plan"], "Unknown")
        self.assertTrue(primary["ok"])
        self.assertEqual(primary["source"], "jsonl")
        self.assertIsNotNone(primary["session"])
        self.assertIsNotNone(primary["weekly"])

    @patch("poller.claude.collect", return_value=dict(_STUB_COLLECT))
    def test_secondary_account_marked_auth_not_present(self, _mock_collect):
        result = claude.collect_multi()
        secondary = result["per_account"][1]
        self.assertEqual(secondary["slug"], "secondary")
        self.assertEqual(secondary["plan"], "Unknown")
        self.assertFalse(secondary["ok"])
        self.assertEqual(secondary["source"], "auth-not-present")
        self.assertIn("note", secondary)
        self.assertIn("swap", secondary["note"].lower())

    @patch("poller.claude.collect", return_value=dict(_STUB_COLLECT))
    def test_env_override_changes_slug_order(self, _mock_collect):
        os.environ["ECO_CLAUDE_ACCOUNTS"] = "secondary,primary"
        result = claude.collect_multi()
        self.assertEqual(result["per_account"][0]["slug"], "secondary")
        self.assertEqual(result["per_account"][1]["slug"], "primary")
        # The first slug always gets the real data, regardless of name.
        self.assertTrue(result["per_account"][0]["ok"])

    @patch("subprocess.run")
    @patch("poller.claude.collect", return_value=dict(_STUB_COLLECT))
    def test_suffixed_keychain_advertised_when_server_truth_enabled(
        self, _mock_collect, mock_run
    ):
        # If server-truth is explicitly enabled and a per-slug Keychain entry
        # exists, we surface "auth-suffixed".
        (Path(self._tmp.name) / "config.json").write_text(
            '{"server_truth": {"claude": true}}',
            encoding="utf-8",
        )
        mock_run.return_value = MagicMock(returncode=0)
        result = claude.collect_multi()
        secondary = result["per_account"][1]
        self.assertEqual(secondary["source"], "auth-suffixed")
        mock_run.assert_called_once_with(
            ["security", "find-generic-password", "-s", "Claude Code-credentials-secondary"],
            capture_output=True, text=True, timeout=3, check=False,
        )

    @patch("subprocess.run")
    @patch("poller.claude.collect", return_value=dict(_STUB_COLLECT))
    def test_collect_multi_default_does_not_probe_keychain(self, _mock_collect, mock_run):
        result = claude.collect_multi()
        self.assertEqual(result["per_account"][1]["source"], "auth-not-present")
        mock_run.assert_not_called()

    @patch("subprocess.run")
    def test_keychain_probe_default_disabled(self, mock_run):
        self.assertFalse(claude._keychain_present_for("secondary"))
        mock_run.assert_not_called()

    def test_account_slugs_defaults(self):
        os.environ.pop("ECO_CLAUDE_ACCOUNTS", None)
        slugs = claude._account_slugs()
        self.assertEqual(slugs, ["primary"])

    def test_account_slugs_empty_env_falls_back(self):
        os.environ["ECO_CLAUDE_ACCOUNTS"] = "   "
        slugs = claude._account_slugs()
        self.assertEqual(slugs, ["primary"])

    @patch("poller.claude.collect", side_effect=Exception("boom"))
    def test_collect_multi_does_not_swallow_collect_exception(self, _mock):
        # collect() raising propagates — main.py wraps collect_multi in
        # _safe_collect so the poller continues. This test pins that
        # contract: we don't silently swallow inner errors.
        with self.assertRaises(Exception):
            claude.collect_multi()

    def test_collect_unknown_cap_emits_null_percentages(self):
        now = datetime(2026, 6, 6, 12, 0, tzinfo=timezone.utc).timestamp()
        project_dir = Path(self._tmp.name) / "claude-projects" / "repo"
        project_dir.mkdir(parents=True)
        record = {
            "type": "assistant",
            "timestamp": datetime.fromtimestamp(now - 60, timezone.utc)
            .isoformat()
            .replace("+00:00", "Z"),
            "message": {
                "id": "msg-1",
                "model": "claude-sonnet-4-6",
                "usage": {
                    "input_tokens": 1000,
                    "output_tokens": 500,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0,
                },
            },
        }
        (project_dir / "events.jsonl").write_text(
            json.dumps(record) + "\n",
            encoding="utf-8",
        )

        with patch.object(claude, "CLAUDE_PROJECTS_DIR", project_dir.parent), \
             patch("time.time", return_value=now), \
             patch.object(claude, "_next_monday_1am_local",
                          return_value=now + 7 * 24 * 3600):
            result = claude.collect()

        self.assertTrue(result["ok"])
        self.assertEqual(result["session"]["tokens"], 1500)
        self.assertIsNone(result["session"]["pct"])
        self.assertEqual(result["session"]["pct_display"], "—")
        self.assertEqual(result["session"]["cap_status"], "unknown")
        self.assertEqual(result["session"]["pace_label"], "unknown")
        self.assertIsNone(result["weekly"]["pct"])
        self.assertIsNone(result["weekly"]["pct_all"])
        self.assertIsNone(result["weekly"]["pct_sonnet"])
        self.assertEqual(result["weekly"]["pct_display"], "—")
        self.assertEqual(result["weekly"]["cap_status"], "unknown")


if __name__ == "__main__":
    unittest.main(verbosity=2)
