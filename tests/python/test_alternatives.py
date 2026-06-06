"""Unit tests for src/poller/alternatives.py."""
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

# Make `import poller.alternatives` work whether invoked from repo root or tests dir.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from poller.alternatives import _ollama_models, collect


class TestAlternatives(unittest.TestCase):
    def test_collect_structure(self):
        with patch("poller.alternatives.shutil.which", return_value=None):
            res = collect()
        self.assertEqual(len(res), 4)
        for key in ["antigravity", "cursor", "vs_code", "ollama"]:
            self.assertIn(key, res)
            self.assertIn("ok", res[key])
            self.assertIn("status", res[key])
            self.assertIn("note", res[key])

    def test_collect_statuses(self):
        with (
            patch("poller.alternatives.shutil.which", return_value="/usr/local/bin/ollama"),
            patch("poller.alternatives._ollama_models", return_value=[]),
        ):
            res = collect()
        self.assertEqual(res["antigravity"]["status"], "stub")
        self.assertEqual(res["cursor"]["status"], "stub")
        self.assertEqual(res["vs_code"]["status"], "always_available")
        self.assertEqual(res["ollama"]["status"], "always_available")

    def test_collect_ollama_present(self):
        models = [{"name": "llama3.2:latest", "size": "2.0 GB"}]
        with (
            patch("poller.alternatives.shutil.which", return_value="/usr/local/bin/ollama"),
            patch("poller.alternatives._ollama_models", return_value=models) as mock_models,
        ):
            res = collect()

        self.assertTrue(res["ollama"]["ok"])
        self.assertEqual(res["ollama"]["status"], "always_available")
        self.assertEqual(res["ollama"]["models"], models)
        mock_models.assert_called_once_with()

    def test_collect_ollama_missing(self):
        with (
            patch("poller.alternatives.shutil.which", return_value=None),
            patch("poller.alternatives._ollama_models") as mock_models,
        ):
            res = collect()

        self.assertFalse(res["ollama"]["ok"])
        self.assertEqual(res["ollama"]["status"], "missing_binary")
        self.assertEqual(res["ollama"]["models"], [])
        self.assertIn("not found", res["ollama"]["note"])
        mock_models.assert_not_called()

    @patch("poller.alternatives.shutil.which")
    def test_ollama_models_missing_binary(self, mock_which):
        mock_which.return_value = None
        self.assertEqual(_ollama_models(), [])

    @patch("poller.alternatives.shutil.which")
    @patch("poller.alternatives.subprocess.run")
    def test_ollama_models_timeout(self, mock_run, mock_which):
        mock_which.return_value = "/usr/local/bin/ollama"
        mock_run.side_effect = subprocess.TimeoutExpired(cmd=["ollama", "list"], timeout=3)
        self.assertEqual(_ollama_models(), [])

if __name__ == "__main__":
    unittest.main(verbosity=2)
