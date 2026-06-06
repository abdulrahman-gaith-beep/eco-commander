"""Runtime config template and fixture contract tests."""

import importlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

EcoConfig = importlib.import_module("common.config").EcoConfig


REPO_ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = REPO_ROOT / "config"
FIXTURES_DIR = REPO_ROOT / "tests" / "fixtures"


class RuntimeConfigTemplateTests(unittest.TestCase):
    def test_config_example_matches_runtime_contract(self):
        data = json.loads((CONFIG_DIR / "config.example.json").read_text(encoding="utf-8"))

        self.assertEqual(set(data["server_truth"]), {"claude", "gemini", "codex"})
        self.assertIsInstance(data["claude"]["accounts"], int)
        for tool in ("claude", "gemini", "codex"):
            self.assertIsInstance(data[tool]["plan"], str)
            self.assertIsInstance(data["server_truth"][tool], bool)

    def test_comments_example_has_required_tiers(self):
        data = json.loads((CONFIG_DIR / "comments.example.json").read_text(encoding="utf-8"))

        self.assertEqual(data["version"], 1)
        self.assertEqual(set(data["tiers"]), {"gentle", "bold", "alarmed"})
        for messages in data["tiers"].values():
            self.assertGreaterEqual(len(messages), 1)
            self.assertTrue(all(isinstance(message, str) and message for message in messages))

    def test_fixture_files_parse(self):
        import yaml

        for name in ("config.json.example", "notify.json.good", "usage.json.healthy"):
            with self.subTest(name=name):
                parsed = json.loads((FIXTURES_DIR / name).read_text(encoding="utf-8"))
                self.assertIsInstance(parsed, dict)

        jobs = yaml.safe_load((FIXTURES_DIR / "jobs.yaml.good").read_text(encoding="utf-8"))
        self.assertIsInstance(jobs["jobs"], list)
        self.assertGreaterEqual(len(jobs["jobs"]), 1)

    def test_eco_config_points_to_runtime_config_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            previous = os.environ.get("ECO_HOME")
            os.environ["ECO_HOME"] = tmp
            try:
                config = EcoConfig.from_env()
                self.assertEqual(config.eco_home, Path(tmp))
                self.assertEqual(config.config_path, Path(tmp) / "config.json")
            finally:
                if previous is None:
                    os.environ.pop("ECO_HOME", None)
                else:
                    os.environ["ECO_HOME"] = previous


if __name__ == "__main__":
    unittest.main(verbosity=2)
