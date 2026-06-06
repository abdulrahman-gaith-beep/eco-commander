"""Tests for src/poller/value.py.

The repository must not embed subscription spend or rate-card figures. These
tests cover the safe default behavior when no canonical financial model export
is provided.
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from poller import value


def _claude_payload(ok=True):
    return {
        "tool": "claude",
        "ok": ok,
        "source": "jsonl",
        "session": {
            "input_tokens": 1000,
            "output_tokens": 1000,
            "cache_creation_tokens": 0,
            "cache_read_tokens": 0,
        },
        "weekly": {
            "input_tokens": 1000,
            "output_tokens": 1000,
            "cache_creation_tokens": 0,
            "cache_read_tokens": 0,
            "by_model": {"sonnet": 2000},
        },
    }


class ValueComputeTests(unittest.TestCase):
    def test_all_tools_missing_returns_no_data_without_model(self):
        with patch.dict(os.environ, {"ECO_VALUE_MODEL_JSON": ""}):
            result = value.compute({})

        self.assertEqual(result["by_tool"]["claude"], "no data")
        self.assertEqual(result["by_tool"]["gemini"], "no data")
        self.assertEqual(result["by_tool"]["codex"], "no data")
        self.assertEqual(result["total_usd_7d"], 0.0)
        self.assertEqual(result["total_usd_30d"], 0.0)
        self.assertEqual(result["multiplier"], 0.0)
        self.assertIsNone(result["subscription_cost_monthly"])
        self.assertEqual(result["codex_credit_rates"], {})
        self.assertIn("Financial value unavailable", result["note"])

    def test_token_payloads_are_not_priced_without_financial_model(self):
        merged = {"claude": _claude_payload()}
        with patch.dict(os.environ, {"ECO_VALUE_MODEL_JSON": ""}):
            result = value.compute(merged)

        self.assertEqual(result["by_tool"]["claude"], "no data")
        self.assertEqual(result["by_model"], {})
        self.assertEqual(result["total_usd_7d"], 0.0)

    def test_malformed_financial_model_is_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            model_path = Path(tmp) / "financial-model.json"
            model_path.write_text("{not-json", encoding="utf-8")
            with patch.dict(os.environ, {"ECO_VALUE_MODEL_JSON": str(model_path)}):
                result = value.compute({"claude": _claude_payload()})

        self.assertEqual(result["by_tool"]["claude"], "no data")
        self.assertEqual(result["multiplier"], 0.0)

    def test_claude_not_ok_treated_as_no_data(self):
        with patch.dict(os.environ, {"ECO_VALUE_MODEL_JSON": ""}):
            result = value.compute({"claude": _claude_payload(ok=False)})

        self.assertEqual(result["by_tool"]["claude"], "no data")
        self.assertEqual(result["total_usd_7d"], 0.0)

    def test_codex_credits_require_external_model(self):
        merged = {
            "codex": {
                "tool": "codex",
                "ok": True,
                "weekly": {
                    "input_tokens": 1000,
                    "cached_input_tokens": 1000,
                    "output_tokens": 1000,
                },
            }
        }
        with patch.dict(os.environ, {"ECO_VALUE_MODEL_JSON": ""}):
            result = value.compute(merged)

        self.assertEqual(result["by_tool"]["codex"], "no data")
        self.assertEqual(result["codex_credits_7d"], 0.0)

    def test_oauth_only_claude_payload_skipped(self):
        merged = {
            "claude": {
                "tool": "claude",
                "ok": True,
                "source": "api",
                "session": {"pct": 50.0},
                "weekly": {"pct": 30.0, "pct_all": 30.0, "pct_sonnet": 20.0},
            }
        }
        with patch.dict(os.environ, {"ECO_VALUE_MODEL_JSON": ""}):
            result = value.compute(merged)

        self.assertEqual(result["by_tool"]["claude"], "no data")


if __name__ == "__main__":
    unittest.main(verbosity=2)
