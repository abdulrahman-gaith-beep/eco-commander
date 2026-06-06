"""Tests for src/poller/gemini.py — multi-account + source-name conventions.

Focus is on the post-W14 contract: source is "api" on success, "error" on
real failure, and "jsonl-estimate" for neutral local estimates (NEVER "stub");
per_account always populated; accounts count matches.

Run via: python3 -m pytest tests/python/test_gemini.py
"""
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from poller import gemini


class TestOAuthClientEnv(unittest.TestCase):
    def test_secret_from_env(self):
        env = {
            gemini.GEMINI_CLIENT_ID_ENV: "local-client-id",
            gemini.GEMINI_CLIENT_SECRET_ENV: "local-client-secret",
        }
        with patch.dict(os.environ, env, clear=True):
            creds = gemini._oauth_client_credentials()
        self.assertEqual(creds, ("local-client-id", "local-client-secret"))

    def test_credentials_missing_when_unset(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(gemini._oauth_client_credentials())
            self.assertEqual(
                gemini._missing_oauth_client_env(),
                [gemini.GEMINI_CLIENT_ID_ENV, gemini.GEMINI_CLIENT_SECRET_ENV],
            )


class TestEnumerateAccounts(unittest.TestCase):
    def test_missing_registry_returns_empty(self):
        with patch.object(gemini, "ACCOUNTS_REGISTRY", Path("/no/such/path.json")):
            active, old = gemini._enumerate_accounts()
        self.assertIsNone(active)
        self.assertEqual(old, [])

    def test_valid_registry(self):
        fake = Path("/fake/google_accounts.json")
        with patch.object(gemini, "ACCOUNTS_REGISTRY", fake), \
             patch.object(Path, "exists", return_value=True), \
             patch.object(Path, "read_text",
                          return_value=json.dumps({
                              "active": "a@example.com",
                              "old": ["b@example.com", "c@example.com"],
                          })):
            active, old = gemini._enumerate_accounts()
        self.assertEqual(active, "a@example.com")
        self.assertEqual(old, ["b@example.com", "c@example.com"])

    def test_malformed_registry_returns_empty(self):
        with patch.object(Path, "exists", return_value=True), \
             patch.object(Path, "read_text", return_value="{not json"):
            active, old = gemini._enumerate_accounts()
        self.assertIsNone(active)
        self.assertEqual(old, [])


class TestErrorPayload(unittest.TestCase):
    def test_never_uses_word_stub(self):
        with patch.object(gemini, "_enumerate_accounts", return_value=(None, [])):
            p = gemini._error_payload("any reason")
        self.assertEqual(p["source"], "error")
        self.assertFalse(p["ok"])
        self.assertNotIn("stub", json.dumps(p))

    def test_includes_per_account(self):
        with patch.object(gemini, "_enumerate_accounts",
                          return_value=("a@example.com", ["b@example.com"])):
            p = gemini._error_payload("auth missing")
        self.assertEqual(p["accounts"], 2)
        self.assertEqual(len(p["per_account"]), 2)
        self.assertEqual([e["slug"] for e in p["per_account"]], ["primary", "account-2"])
        self.assertNotIn("a@example.com", json.dumps(p))
        self.assertNotIn("b@example.com", json.dumps(p))
        for entry in p["per_account"]:
            self.assertEqual(entry["source"], "error")
            self.assertFalse(entry["ok"])

    def test_fallback_slug_when_no_registry(self):
        with patch.object(gemini, "_enumerate_accounts", return_value=(None, [])):
            p = gemini._error_payload("auth missing")
        self.assertEqual(p["accounts"], 1)
        self.assertEqual(p["per_account"][0]["slug"], "primary")


class TestCollectFailurePaths(unittest.TestCase):
    """Ensure real failure paths return source='error', never 'stub'."""

    def test_missing_oauth_returns_error_source(self):
        env = {
            gemini.GEMINI_CLIENT_ID_ENV: "local-client-id",
            gemini.GEMINI_CLIENT_SECRET_ENV: "local-client-secret",
        }
        with patch.dict(os.environ, env, clear=True), \
             patch.object(gemini, "_server_truth_enabled", return_value=True), \
             patch.object(gemini, "_load_oauth",
                          return_value=(None, "oauth missing")):
            p = gemini.collect()
        self.assertEqual(p["source"], "error")
        self.assertFalse(p["ok"])

    def test_refresh_failure_returns_error_source(self):
        env = {
            gemini.GEMINI_CLIENT_ID_ENV: "local-client-id",
            gemini.GEMINI_CLIENT_SECRET_ENV: "local-client-secret",
        }
        with patch.dict(os.environ, env, clear=True), \
             patch.object(gemini, "_server_truth_enabled", return_value=True), \
             patch.object(gemini, "_load_oauth",
                          return_value=({"access_token": "x"}, None)), \
             patch.object(gemini, "_refresh_if_needed",
                          return_value=(None, "refresh failed")):
            p = gemini.collect()
        self.assertEqual(p["source"], "error")

    def test_server_truth_disabled_returns_jsonl_estimate_not_error(self):
        with patch.dict(os.environ, {}, clear=True), \
             patch.object(gemini, "_server_truth_enabled", return_value=False), \
             patch.object(gemini, "_load_oauth",
                          side_effect=AssertionError("_load_oauth should not run")):
            p = gemini.collect()
        self.assertTrue(p["ok"])
        self.assertEqual(p["source"], "jsonl-estimate")
        self.assertIn("server-truth disabled", p["note"])
        self.assertNotIn("error", p)
        self.assertTrue(p["per_account"][0]["ok"])
        self.assertEqual(p["per_account"][0]["source"], "jsonl-estimate")

    def test_oauth_client_env_unset_returns_neutral_estimate(self):
        with patch.dict(os.environ, {}, clear=True), \
             patch.object(gemini, "_server_truth_enabled", return_value=True), \
             patch.object(gemini, "_load_oauth",
                          side_effect=AssertionError("_load_oauth should not run")):
            p = gemini.collect()
        self.assertEqual(p["source"], "jsonl-estimate")
        self.assertTrue(p["ok"])
        self.assertIn(gemini.GEMINI_CLIENT_SECRET_ENV, p["note"])
        self.assertNotIn("error", p)

    def test_success_payload_uses_non_email_slugs(self):
        env = {
            gemini.GEMINI_CLIENT_ID_ENV: "local-client-id",
            gemini.GEMINI_CLIENT_SECRET_ENV: "local-client-secret",
        }
        quota = {
            "buckets": [
                {
                    "modelId": "gemini-3-pro-preview",
                    "remainingFraction": 0.5,
                    "remainingAmount": "50",
                    "resetTime": "2099-01-01T00:00:00Z",
                }
            ]
        }
        with patch.dict(os.environ, env, clear=True), \
             patch.object(gemini, "_server_truth_enabled", return_value=True), \
             patch.object(gemini, "_load_oauth",
                          return_value=({"access_token": "token"}, None)), \
             patch.object(gemini, "_refresh_if_needed",
                          return_value=({"access_token": "token"}, None)), \
             patch.object(gemini, "_get_project_id",
                          return_value=("project", {"currentTier": {"id": "test-tier"}}, None)), \
             patch.object(gemini, "_post", return_value=(quota, None)), \
             patch.object(gemini, "_enumerate_accounts",
                          return_value=("a@example.com", ["b@example.com"])):
            p = gemini.collect()
        self.assertTrue(p["ok"])
        self.assertEqual(p["source"], "api")
        self.assertIsNone(p["user_tier"])
        self.assertEqual([e["slug"] for e in p["per_account"]], ["primary", "account-2"])
        self.assertNotIn("test-tier", json.dumps(p))
        self.assertNotIn("a@example.com", json.dumps(p))
        self.assertNotIn("b@example.com", json.dumps(p))


class TestDebugPrivacy(unittest.TestCase):
    def test_http_error_body_is_not_returned(self):
        with patch("poller.gemini.urllib.request.urlopen", side_effect=gemini.urllib.error.HTTPError(
            "url", 403, "Forbidden", {}, None
        )):
            data, message = gemini._post("https://example.test", "token", {})
        self.assertIsNone(data)
        self.assertEqual(message, "HTTP 403")

    def test_raw_dump_disabled_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            dump = Path(tmp) / "gemini.json"
            response = unittest.mock.MagicMock()
            response.read.return_value = b'{"ok": true}'
            response.__enter__ = lambda s: s
            response.__exit__ = unittest.mock.MagicMock(return_value=False)
            with patch("poller.gemini.urllib.request.urlopen", return_value=response), \
                 patch.object(gemini, "_debug_dump_enabled", return_value=False):
                data, message = gemini._post("https://example.test", "token", {}, dump_path=dump)
        self.assertEqual(data, {"ok": True})
        self.assertIsNone(message)
        self.assertFalse(dump.exists())

    def test_save_oauth_writes_private_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            oauth_path = Path(tmp) / "oauth_creds.json"
            with patch.object(gemini, "OAUTH_PATH", oauth_path):
                gemini._save_oauth({"access_token": "new-token"})
            self.assertEqual(json.loads(oauth_path.read_text()), {"access_token": "new-token"})
            self.assertEqual(stat.S_IMODE(oauth_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(oauth_path.parent.stat().st_mode), 0o700)


if __name__ == "__main__":
    unittest.main()
