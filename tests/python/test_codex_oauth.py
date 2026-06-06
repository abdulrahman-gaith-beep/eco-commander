"""Tests for src/poller/codex_oauth.py.
Run via: python3 -m pytest tests/python/test_codex_oauth.py

Updated 2026-05-14 for the post-W2 rewrite:
  - _read_auth_token → _read_auth_data (returns (token, account_id) tuple)
  - usage.five_hour.remaining_percentage → rate_limit.primary_window.used_percent
  - usage.weekly.remaining_percentage   → rate_limit.secondary_window.used_percent
  - pct is now used_percent directly (no remaining→used inversion)
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from poller.codex_oauth import _read_auth_data, collect


class TestReadAuthData(unittest.TestCase):
    """Tests for _read_auth_data() — returns (token, account_id) tuple.

    AUTH_PATH is evaluated at import time from Path.home(), so we patch
    the module-level variable directly rather than relying on HOME env override.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def _auth_path(self):
        return Path(self.tmp.name) / ".codex" / "auth.json"

    def test_missing_file(self):
        missing = Path(self.tmp.name) / ".codex" / "auth.json"
        with patch("poller.codex_oauth.AUTH_PATH", missing):
            self.assertEqual(_read_auth_data(), (None, None))

    def test_malformed_json(self):
        p = self._auth_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("invalid json", encoding="utf-8")
        with patch("poller.codex_oauth.AUTH_PATH", p):
            self.assertEqual(_read_auth_data(), (None, None))

    def test_token_only(self):
        p = self._auth_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps({"tokens": {"access_token": "secret"}}),
                     encoding="utf-8")
        with patch("poller.codex_oauth.AUTH_PATH", p):
            token, account_id = _read_auth_data()
        self.assertEqual(token, "secret")
        self.assertIsNone(account_id)

    def test_token_with_top_level_account_id(self):
        p = self._auth_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps({
            "tokens": {"access_token": "secret"},
            "account_id": "acc-123",
        }), encoding="utf-8")
        with patch("poller.codex_oauth.AUTH_PATH", p):
            token, account_id = _read_auth_data()
        self.assertEqual(token, "secret")
        self.assertEqual(account_id, "acc-123")

    def test_token_with_nested_account_id(self):
        """account_id can also live inside tokens dict (fallback path)."""
        p = self._auth_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps({
            "tokens": {"access_token": "secret", "account_id": "acc-nested"},
        }), encoding="utf-8")
        with patch("poller.codex_oauth.AUTH_PATH", p):
            token, account_id = _read_auth_data()
        self.assertEqual(token, "secret")
        self.assertEqual(account_id, "acc-nested")

    def test_missing_tokens_key(self):
        p = self._auth_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps({"other": "data"}), encoding="utf-8")
        with patch("poller.codex_oauth.AUTH_PATH", p):
            self.assertEqual(_read_auth_data(), (None, None))

    def test_empty_access_token(self):
        p = self._auth_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps({"tokens": {"access_token": ""}}),
                     encoding="utf-8")
        with patch("poller.codex_oauth.AUTH_PATH", p):
            token, _ = _read_auth_data()
        self.assertIsNone(token)


class TestCollect(unittest.TestCase):
    """Tests for collect()."""

    def _make_urlopen_cm(self, body_bytes):
        mock_resp = MagicMock()
        mock_resp.read.return_value = body_bytes
        mock_cm = MagicMock()
        mock_cm.__enter__ = MagicMock(return_value=mock_resp)
        mock_cm.__exit__ = MagicMock(return_value=False)
        return mock_cm

    def _payload(self, primary_used=50, secondary_used=50,
                 primary_reset_after=None, secondary_reset_after=None,
                 primary_window=None, secondary_window=None):
        pw: dict = {"used_percent": primary_used}
        sw: dict = {"used_percent": secondary_used}
        if primary_reset_after is not None:
            pw["reset_after_seconds"] = primary_reset_after
        if secondary_reset_after is not None:
            sw["reset_after_seconds"] = secondary_reset_after
        if primary_window is not None:
            pw["limit_window_seconds"] = primary_window
        if secondary_window is not None:
            sw["limit_window_seconds"] = secondary_window
        return {"rate_limit": {"primary_window": pw, "secondary_window": sw}}

    @patch("poller.codex_oauth._read_auth_data", return_value=(None, None))
    def test_collect_no_token(self, _mock):
        result = collect()
        self.assertFalse(result["ok"])
        self.assertIn("error", result)

    @patch("poller.codex_oauth._read_auth_data", return_value=("tok", "acc-1"))
    @patch("urllib.request.urlopen")
    def test_collect_used_percent_passthrough(self, mock_urlopen, _mock_read):
        """primary_window.used_percent=80 -> session.pct == 80 (no inversion)."""
        mock_urlopen.return_value = self._make_urlopen_cm(
            json.dumps(self._payload(primary_used=80, secondary_used=60)).encode()
        )
        result = collect()
        self.assertTrue(result["ok"])
        self.assertEqual(result["session"]["pct"], 80.0)
        self.assertEqual(result["weekly"]["pct"], 60.0)

    @patch("poller.codex_oauth._read_auth_data", return_value=("tok", "acc-1"))
    @patch("urllib.request.urlopen")
    def test_collect_uses_reset_after_seconds(self, mock_urlopen, _mock_read):
        """reset_after_seconds drives session.reset_epoch."""
        mock_urlopen.return_value = self._make_urlopen_cm(
            json.dumps(self._payload(primary_used=50, secondary_used=50,
                                     primary_reset_after=3600)).encode()
        )
        with patch("time.time", return_value=1_000_000.0):
            result = collect()
        self.assertTrue(result["ok"])
        self.assertEqual(result["session"]["reset_epoch"], 1_000_000 + 3600)

    @patch("poller.codex_oauth._read_auth_data", return_value=("tok", "acc-1"))
    @patch("urllib.request.urlopen")
    def test_collect_sends_account_id_header(self, mock_urlopen, _mock_read):
        mock_urlopen.return_value = self._make_urlopen_cm(
            json.dumps(self._payload(primary_used=20, secondary_used=10)).encode()
        )
        collect()
        req = mock_urlopen.call_args.args[0]
        self.assertEqual(req.headers.get("Chatgpt-account-id"), "acc-1")

    @patch("poller.codex_oauth._read_auth_data", return_value=("tok", "acc-1"))
    @patch("urllib.request.urlopen")
    def test_collect_fallback_5h_window(self, mock_urlopen, _mock_read):
        """Without reset_after_seconds, session window falls back to 5h."""
        mock_urlopen.return_value = self._make_urlopen_cm(
            json.dumps(self._payload(primary_used=50, secondary_used=50)).encode()
        )
        with patch("time.time", return_value=1_000_000.0):
            result = collect()
        self.assertTrue(result["ok"])
        self.assertEqual(result["session"]["reset_epoch"], 1_000_000 + 5 * 3600)

    @patch("poller.codex_oauth._read_auth_data", return_value=("tok", "acc-1"))
    @patch("urllib.request.urlopen")
    def test_collect_401(self, mock_urlopen, _mock_read):
        from urllib.error import HTTPError
        mock_urlopen.side_effect = HTTPError("url", 401, "Unauthorized", {}, None)
        result = collect()
        self.assertFalse(result["ok"])
        self.assertIn("401", result["error"])

    @patch("poller.codex_oauth._read_auth_data", return_value=("tok", "acc-1"))
    @patch("urllib.request.urlopen")
    def test_collect_429(self, mock_urlopen, _mock_read):
        from urllib.error import HTTPError
        mock_urlopen.side_effect = HTTPError("url", 429, "Too Many Requests", {}, None)
        result = collect()
        self.assertFalse(result["ok"])
        self.assertIn("429", result["error"])
        self.assertEqual(result["error_code"], "http_429")

    @patch("poller.codex_oauth._read_auth_data", return_value=("tok", "acc-1"))
    @patch("urllib.request.urlopen")
    def test_collect_ssl_error(self, mock_urlopen, _mock_read):
        import ssl
        mock_urlopen.side_effect = ssl.SSLError("TLS failed")
        result = collect()
        self.assertFalse(result["ok"])

    @patch("poller.codex_oauth._read_auth_data", return_value=("tok", "acc-1"))
    @patch("urllib.request.urlopen")
    def test_collect_malformed_percentages(self, mock_urlopen, _mock_read):
        """Non-numeric used_percent values return ok=False."""
        payload = {"rate_limit": {"primary_window": {"used_percent": "bad"},
                                   "secondary_window": {"used_percent": None}}}
        mock_urlopen.return_value = self._make_urlopen_cm(
            json.dumps(payload).encode()
        )
        result = collect()
        self.assertFalse(result["ok"])
        self.assertEqual(result["error_code"], "schema")

    @patch("poller.codex_oauth._read_auth_data", return_value=("tok", "acc-1"))
    @patch("urllib.request.urlopen")
    def test_collect_missing_rate_limit_is_schema_error(self, mock_urlopen, _mock_read):
        mock_urlopen.return_value = self._make_urlopen_cm(b'{"ok": true}')
        result = collect()
        self.assertFalse(result["ok"])
        self.assertEqual(result["error_code"], "schema")

    @patch("poller.codex_oauth._read_auth_data", return_value=("tok", "acc-1"))
    @patch("urllib.request.urlopen")
    def test_collect_result_shape(self, mock_urlopen, _mock_read):
        mock_urlopen.return_value = self._make_urlopen_cm(
            json.dumps(self._payload(primary_used=30, secondary_used=10)).encode()
        )
        result = collect()
        self.assertTrue(result["ok"])
        self.assertEqual(result["tool"], "codex")
        self.assertEqual(result["source"], "api")
        for meter in ("session", "weekly"):
            self.assertIn("pct", result[meter])
            self.assertIn("resets_in", result[meter])
            self.assertIn("reset_epoch", result[meter])
        self.assertIn("last_event_ts", result)


if __name__ == "__main__":
    unittest.main(verbosity=2)
