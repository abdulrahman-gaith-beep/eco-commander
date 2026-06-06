"""Integration test: poller output → widget CLI rendering.

Verifies that the data shape produced by poller.main is correctly consumed
by the eco-commander.15s.sh widget in --cli mode. This catches schema
mismatches between the Python poller and the bash renderer.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "src"))


class TestPollerWidgetIntegration(unittest.TestCase):
    """Feed synthetic poller output into the widget and verify coherent rendering."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="eco-integ-test-")
        self.eco_dir = Path(self.tmpdir) / ".eco"
        self.current = self.eco_dir / "current"
        self.current.mkdir(parents=True)

        # Minimal skeleton for the widget
        (self.eco_dir / "bin").mkdir()
        (self.eco_dir / "recipes").mkdir()
        self.stub_bin = Path(self.tmpdir) / "stubs"
        self.stub_bin.mkdir()
        curl_stub = self.stub_bin / "curl"
        curl_stub.write_text('#!/bin/sh\nexit "${STUB_CURL_EXIT:-0}"\n')
        curl_stub.chmod(0o755)

        # Create profiles dir
        profiles = Path(self.tmpdir) / ".ai-ecosystem" / "profiles"
        profiles.mkdir(parents=True)
        (Path(self.tmpdir) / ".ai-ecosystem" / ".current-profile").write_text("core")

        # Create a dummy state.json
        state = {
            "snapshot_id": "integ-test",
            "generated_at": "2026-05-20T12:00:00Z",
            "layers": {"Linf_wiring": {"issues": []}},
        }
        (self.current / "state.json").write_text(json.dumps(state))
        (self.current / "dashboard.html").write_text("<html>dashboard</html>")
        (self.current / "map.md").write_text("# map")

        # Repo root
        self.repo_root = str(Path(__file__).resolve().parent.parent.parent)
        self.widget = os.path.join(self.repo_root, "src", "bin", "eco-commander.15s.sh")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _write_usage(self, data: dict):
        (self.current / "usage.json").write_text(json.dumps(data))

    def _run_widget_cli(self) -> tuple[int, str]:
        """Run the widget in --cli mode with sandboxed HOME."""
        env = os.environ.copy()
        env["HOME"] = self.tmpdir
        env["ECO_HOME"] = str(self.eco_dir)
        env["ECO_COMMANDER_REPO"] = self.repo_root
        # Disable live service probes
        env["STUB_CURL_EXIT"] = "1"
        env["PATH"] = f"{self.stub_bin}{os.pathsep}{env.get('PATH', '')}"

        result = subprocess.run(
            ["bash", self.widget, "--cli"],
            capture_output=True,
            text=True,
            timeout=15,
            env=env,
        )
        return result.returncode, result.stdout

    def test_healthy_usage_renders_green(self):
        """Healthy usage data → widget renders without errors."""
        import time
        self._write_usage({
            "ts": int(time.time()),
            "version": 1,
            "claude": {
                "ok": True, "source": "jsonl", "plan": "Local config", "accounts": 0,
                "session": {"pct": 10, "resets_in": "4h 30m"},
                "weekly": {"pct": 25, "resets_in": "5d 2h",
                           "pct_all": 25, "pct_sonnet": 5},
            },
            "gemini": {
                "ok": True, "plan": "Local config", "accounts": 0,
                "tiers": {
                    "flash": {"pct": 5, "resets_in": "23h"},
                    "flash_lite": {"pct": 2, "resets_in": "23h"},
                    "pro": {"pct": 8, "resets_in": "23h"},
                },
            },
            "codex": {
                "ok": True, "source": "jsonl", "plan": "Local config", "accounts": 0,
                "session": {"pct": 15, "resets_in": "3h 10m"},
                "weekly": {"pct": 20, "resets_in": "6d 1h"},
            },
        })

        rc, output = self._run_widget_cli()
        self.assertEqual(rc, 0, f"widget exited non-zero: {output}")
        self.assertGreater(len(output.splitlines()), 10,
                           "widget output suspiciously short")

        # Should contain all three tool sections
        self.assertIn("Claude", output)
        self.assertIn("Gemini", output)
        self.assertIn("Codex", output)

        # Should show status icon
        self.assertIn("Status:", output)

    def test_error_state_renders_without_crash(self):
        """All tools in error state → widget still renders, no crash."""
        import time
        self._write_usage({
            "ts": int(time.time()),
            "version": 1,
            "claude": {"ok": False, "error": "RuntimeError"},
            "gemini": {"ok": False, "error": "TimeoutError"},
            "codex": {"ok": False, "error": "FileNotFoundError"},
        })

        rc, output = self._run_widget_cli()
        self.assertEqual(rc, 0, f"widget crashed on error state: {output}")

    def test_missing_usage_json_renders(self):
        """No usage.json at all → widget renders with guidance."""
        rc, output = self._run_widget_cli()
        self.assertEqual(rc, 0, f"widget crashed without usage.json: {output}")

    def test_stale_usage_shows_warning(self):
        """Usage data older than STALE_AFTER_SECS → widget shows stale indicator."""
        self._write_usage({
            "ts": 1000000,  # Very old
            "version": 1,
            "claude": {"ok": True, "source": "jsonl", "plan": "Local config", "accounts": 0,
                       "session": {"pct": 10, "resets_in": "4h"},
                       "weekly": {"pct": 20, "resets_in": "5d", "pct_all": 20, "pct_sonnet": 5}},
            "gemini": {"ok": False, "error": "stub"},
            "codex": {"ok": False, "error": "stub"},
        })

        rc, output = self._run_widget_cli()
        self.assertEqual(rc, 0)
        # Should mention staleness
        self.assertTrue(
            "STALE" in output or "stale" in output.lower(),
            f"Expected stale warning in output: {output[:500]}"
        )


if __name__ == "__main__":
    unittest.main()
