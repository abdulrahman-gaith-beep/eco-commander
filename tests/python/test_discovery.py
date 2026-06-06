"""Stdlib-only tests for src/poller/discovery.py.

Run via:
    python3 tests/python/test_discovery.py
"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from poller import discovery


class DiscoveryTests(unittest.TestCase):

    # ------- detect_user -------

    def test_detect_user_returns_string(self):
        u = discovery.detect_user()
        self.assertIsInstance(u, str)
        self.assertGreater(len(u), 0)

    # ------- home_paths -------

    def test_home_paths_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_home = Path(tmp)
            with patch("poller.discovery.Path.home", return_value=fake_home):
                p = discovery.home_paths()
            self.assertEqual(set(p.keys()), {"home", "eco", "claude", "gemini", "codex"})
            self.assertEqual(p["home"], fake_home)
            self.assertEqual(p["eco"], p["home"] / ".eco")
            self.assertEqual(p["claude"], p["home"] / ".claude")
            self.assertEqual(p["gemini"], p["home"] / ".gemini")
            self.assertEqual(p["codex"], p["home"] / ".codex")

    # ------- detect_accounts -------

    def test_detect_accounts_unknown_tool_returns_zero(self):
        self.assertEqual(discovery.detect_accounts("nonexistent"), 0)

    def test_detect_accounts_gemini_counts_fixture_filesystem(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_home = Path(tmp)
            (fake_home / ".gemini" / "accounts").mkdir(parents=True)
            (fake_home / ".gemini" / "oauth_creds.json").write_text("{}", encoding="utf-8")
            (fake_home / ".gemini" / "accounts" / "oauth_creds.second.json").write_text(
                "{}", encoding="utf-8"
            )
            with patch("poller.discovery.Path.home", return_value=fake_home):
                self.assertEqual(discovery.detect_accounts("gemini"), 2)

    def test_detect_accounts_codex_counts_fixture_filesystem(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_home = Path(tmp)
            with patch("poller.discovery.Path.home", return_value=fake_home):
                self.assertEqual(discovery.detect_accounts("codex"), 0)
            (fake_home / ".codex").mkdir()
            (fake_home / ".codex" / "auth.json").write_text("{}", encoding="utf-8")
            with patch("poller.discovery.Path.home", return_value=fake_home):
                self.assertEqual(discovery.detect_accounts("codex"), 1)

    def test_detect_accounts_claude_default_is_zero(self):
        # Without config override, claude is not enumerable and stays neutral.
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"ECO_HOME": tmp}):
                self.assertEqual(discovery.detect_accounts("claude"), 0)

    def test_detect_accounts_claude_config_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"ECO_HOME": tmp}):
                cfg = Path(tmp) / "config.json"
                cfg.write_text(json.dumps({"claude": {"accounts": 3}}))
                self.assertEqual(discovery.detect_accounts("claude"), 3)

    # ------- detect_plans -------

    def test_detect_plans_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"ECO_HOME": tmp}):
                plans = discovery.detect_plans()
                self.assertEqual(set(plans.keys()), {"claude", "gemini", "codex"})
                # All entries must have plan + accounts + source
                for _tool, info in plans.items():
                    self.assertIn(info["source"], ("config", "default", "api"))
                    self.assertEqual(info["plan"], "Unknown")
                    self.assertIsInstance(info["plan"], str)
                    self.assertIsInstance(info["accounts"], int)

    def test_detect_plans_config_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"ECO_HOME": tmp}):
                cfg = Path(tmp) / "config.json"
                cfg.write_text(json.dumps({"claude": {"plan": "Configured locally"}}))
                plans = discovery.detect_plans()
                self.assertEqual(plans["claude"]["plan"], "Configured locally")
                self.assertEqual(plans["claude"]["source"], "config")
                # Defaults for unconfigured tools
                self.assertEqual(plans["gemini"]["source"], "default")

    def test_detect_plans_corrupt_config_falls_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"ECO_HOME": tmp}):
                cfg = Path(tmp) / "config.json"
                cfg.write_text("not valid json {{{ ")
                plans = discovery.detect_plans()
                # Should not raise; should fall back to defaults
                self.assertEqual(plans["claude"]["source"], "default")

    def test_wrong_shaped_tool_config_falls_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"ECO_HOME": tmp}):
                cfg = Path(tmp) / "config.json"
                cfg.write_text(
                    json.dumps({"claude": {"accounts": "many"}, "gemini": "not-a-dict"}),
                    encoding="utf-8",
                )
                self.assertEqual(discovery.detect_accounts("claude"), 0)
                plans = discovery.detect_plans()
                self.assertEqual(plans["gemini"]["plan"], "Unknown")
                self.assertEqual(plans["gemini"]["source"], "default")

    # ------- server_truth_enabled -------

    def test_server_truth_enabled_default_false(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"ECO_HOME": tmp}):
                self.assertFalse(discovery.server_truth_enabled("claude"))
                self.assertFalse(discovery.server_truth_enabled("codex"))
                self.assertFalse(discovery.server_truth_enabled("gemini"))

    def test_server_truth_enabled_per_tool_flag(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"ECO_HOME": tmp}):
                cfg = Path(tmp) / "config.json"
                cfg.write_text(json.dumps({"server_truth": {"claude": True}}))
                self.assertTrue(discovery.server_truth_enabled("claude"))
                self.assertFalse(discovery.server_truth_enabled("codex"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
