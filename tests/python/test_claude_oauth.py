"""Tests for src/poller/claude_oauth.py.
Run via: python3 tests/python/test_claude_oauth.py
"""
import ssl
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from poller.claude_oauth import _extract_access_token, _read_keychain_token, collect
from poller.main import _pick_collector

_GOOD_PAYLOAD = (
    b'{"five_hour":{"utilization":50.0,"reset_at":"2026-05-10T12:00:00Z"},'
    b'"seven_day":{"utilization":30.0,"reset_at":"2026-05-16T12:00:00Z"},'
    b'"seven_day_sonnet":{"utilization":20.0}}'
)


class TestClaudeOAuth(unittest.TestCase):

    @patch("poller.main.discovery.server_truth_enabled", return_value=False)
    @patch("poller.claude_oauth.subprocess.run")
    def test_default_picker_does_not_touch_keychain(self, mock_run, _mock_enabled):
        result = _pick_collector(
            "claude",
            collect,
            lambda: {"tool": "claude", "ok": True, "source": "jsonl"},
        )
        self.assertEqual(result["source"], "jsonl")
        mock_run.assert_not_called()

    @patch("poller.claude_oauth.subprocess.run")
    def test_read_keychain_token_failure(self, mock_run):
        mock_run.return_value = MagicMock(returncode=1)
        self.assertIsNone(_read_keychain_token())

    @patch("poller.claude_oauth.subprocess.run")
    def test_read_keychain_token_timeout(self, mock_run):
        mock_run.side_effect = subprocess.TimeoutExpired(cmd="test", timeout=1)
        self.assertIsNone(_read_keychain_token())

    @patch("poller.claude_oauth.subprocess.run")
    def test_read_keychain_token_success(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout="x" * 16 + "\n")
        self.assertEqual(_read_keychain_token(), "x" * 16)

    def test_extract_access_token_from_nested_json(self):
        raw = '{"claudeAiOauth":{"accessToken":"access-token-123","refreshToken":"refresh","expiresAt":1}}'
        self.assertEqual(_extract_access_token(raw), "access-token-123")

    def test_extract_access_token_from_top_level_json(self):
        raw = '{"accessToken":"access-token-123","refreshToken":"refresh","expiresAt":1}'
        self.assertEqual(_extract_access_token(raw), "access-token-123")

    def test_malformed_json_like_keychain_payload_is_rejected(self):
        self.assertIsNone(_extract_access_token('{"claudeAiOauth":'))

    def test_malformed_json_payload_is_not_used_as_token(self):
        raw = '{"accessToken":'
        self.assertIsNone(_extract_access_token(raw))

    def test_raw_token_rejects_whitespace_and_short_values(self):
        self.assertIsNone(_extract_access_token("short"))
        self.assertIsNone(_extract_access_token("valid-looking-token\nsecond-line"))
        self.assertEqual(_extract_access_token("valid-looking-token-123"), "valid-looking-token-123")

    @patch("poller.claude_oauth._read_keychain_token")
    def test_collect_no_token(self, mock_read):
        mock_read.return_value = None
        result = collect()
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "no_keychain_token")
        self.assertEqual(result["tool"], "claude")

    @patch("poller.claude_oauth._read_keychain_token")
    @patch("poller.claude_oauth.urllib.request.urlopen")
    def test_collect_valid(self, mock_urlopen, mock_read):
        mock_read.return_value = "token"
        mock_resp = MagicMock()
        mock_resp.read.return_value = _GOOD_PAYLOAD
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = collect()
        self.assertTrue(result["ok"])
        self.assertEqual(result["tool"], "claude")
        self.assertIn("session", result)
        self.assertIn("weekly", result)
        self.assertAlmostEqual(result["session"]["pct"], 50.0, places=1)

    @patch("poller.claude_oauth._read_keychain_token")
    @patch("poller.claude_oauth.urllib.request.urlopen")
    def test_collect_accepts_percent_and_resets_at(self, mock_urlopen, mock_read):
        mock_read.return_value = "token"
        mock_resp = MagicMock()
        mock_resp.read.return_value = (
            b'{"five_hour":{"utilization":50.0,"resets_at":"2026-05-10T12:00:00Z"},'
            b'"seven_day":{"utilization":30.0,"resets_at":"2026-05-16T12:00:00Z"},'
            b'"seven_day_sonnet":{"utilization":20.0}}'
        )
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = collect()
        self.assertTrue(result["ok"])
        self.assertAlmostEqual(result["session"]["pct"], 50.0, places=1)
        self.assertAlmostEqual(result["weekly"]["pct_all"], 30.0, places=1)

    @patch("poller.claude_oauth._read_keychain_token")
    @patch("poller.claude_oauth.urllib.request.urlopen")
    def test_collect_sub_one_percent_not_inflated(self, mock_urlopen, mock_read):
        # Regression: prior heuristic treated utilization <= 1.0 as a 0-1
        # fraction and multiplied by 100. Real values from the API: 1.0 = 1%.
        mock_read.return_value = "token"
        mock_resp = MagicMock()
        mock_resp.read.return_value = (
            b'{"five_hour":{"utilization":4.0,"resets_at":"2026-05-11T05:00:00Z"},'
            b'"seven_day":{"utilization":1.0,"resets_at":"2026-05-17T22:00:00Z"},'
            b'"seven_day_sonnet":{"utilization":0.0,"resets_at":"2026-05-17T22:00:00Z"}}'
        )
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = collect()
        self.assertTrue(result["ok"])
        self.assertAlmostEqual(result["session"]["pct"], 4.0, places=1)
        self.assertAlmostEqual(result["weekly"]["pct_all"], 1.0, places=1)
        self.assertAlmostEqual(result["weekly"]["pct_sonnet"], 0.0, places=1)
        self.assertAlmostEqual(result["weekly"]["pct"], 1.0, places=1)

    @patch("poller.claude_oauth._read_keychain_token")
    @patch("poller.claude_oauth.urllib.request.urlopen")
    def test_collect_schema_error(self, mock_urlopen, mock_read):
        mock_read.return_value = "token"
        mock_resp = MagicMock()
        mock_resp.read.return_value = b'["unexpected"]'
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = collect()
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "schema")

    @patch("poller.claude_oauth._read_keychain_token")
    @patch("poller.claude_oauth.urllib.request.urlopen")
    def test_collect_401(self, mock_urlopen, mock_read):
        mock_read.return_value = "token"
        mock_urlopen.side_effect = HTTPError("url", 401, "Unauthorized", {}, None)
        result = collect()
        self.assertFalse(result["ok"])
        self.assertIn("error", result)
        self.assertEqual(result["error"], "http_401")

    @patch("poller.claude_oauth._read_keychain_token")
    @patch("poller.claude_oauth.urllib.request.urlopen")
    def test_collect_ssl_error(self, mock_urlopen, mock_read):
        mock_read.return_value = "token"
        mock_urlopen.side_effect = ssl.SSLError("TLS failed")
        result = collect()
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "tls_failure")
        self.assertEqual(result["tool"], "claude")


if __name__ == "__main__":
    unittest.main(verbosity=2)
