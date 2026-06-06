"""Tests for src/poller/accounts.py — account context and subscription metadata.

Covers:
- tool_context: deep-copy isolation, days_until injection, unknown-tool fallback
- stamp: payload enrichment, collector-owned account counts, plan_events
- _days_until: date parsing, edge cases, None handling
- _account_slugs: implicit via tool_context structure
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "src"))

from poller.accounts import _CONTEXT, _days_until, stamp, tool_context


class IsolatedEcoHomeMixin:
    """Point account-config lookups at an empty local runtime dir."""

    def setUp(self):
        super().setUp()
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.eco_home = Path(self._tmp.name)
        self._env = patch.dict(os.environ, {"ECO_HOME": str(self.eco_home)})
        self._env.start()
        self.addCleanup(self._env.stop)

    def write_accounts_config(self, data: dict) -> None:
        (self.eco_home / "accounts.json").write_text(json.dumps(data), encoding="utf-8")


class TestDaysUntil(unittest.TestCase):
    """_days_until: calendar math helper."""

    def test_future_date_returns_positive(self):
        result = _days_until("2026-06-01", today=date(2026, 5, 22))
        self.assertEqual(result, 10)

    def test_past_date_returns_negative(self):
        result = _days_until("2026-05-01", today=date(2026, 5, 22))
        self.assertEqual(result, -21)

    def test_same_date_returns_zero(self):
        result = _days_until("2026-05-22", today=date(2026, 5, 22))
        self.assertEqual(result, 0)

    def test_invalid_date_returns_none(self):
        self.assertIsNone(_days_until("not-a-date"))

    def test_empty_string_returns_none(self):
        self.assertIsNone(_days_until(""))

    def test_none_input_returns_none(self):
        self.assertIsNone(_days_until(None))

    def test_partial_date_returns_none(self):
        self.assertIsNone(_days_until("2026-05"))


class TestToolContext(IsolatedEcoHomeMixin, unittest.TestCase):
    """tool_context: deep-copied context blocks for known and unknown tools."""

    def test_known_tools_return_neutral_defaults(self):
        for tool in ("claude", "gemini", "codex"):
            with self.subTest(tool=tool):
                ctx = tool_context(tool)
                self.assertEqual(ctx["plan"], "Unknown")
                self.assertEqual(ctx["configured_accounts"], 0)
                self.assertEqual(ctx["account_inventory"], [])

    def test_unknown_tool_returns_defaults(self):
        ctx = tool_context("nonexistent")
        self.assertEqual(ctx["plan"], "Unknown")
        self.assertEqual(ctx["configured_accounts"], 0)
        self.assertEqual(ctx["account_inventory"], [])

    def test_returns_deep_copy_not_reference(self):
        """Mutating the returned context must not affect the internal store."""
        ctx1 = tool_context("claude")
        ctx1["plan"] = "MUTATED"
        ctx1["account_inventory"].append({"slug": "fake"})
        ctx2 = tool_context("claude")
        self.assertEqual(ctx2["plan"], "Unknown")
        self.assertEqual(ctx2["account_inventory"], [])

    def test_neutral_account_inventory_is_empty(self):
        ctx = tool_context("gemini")
        self.assertEqual(ctx["account_inventory"], [])

    def test_local_accounts_json_overrides_neutral_defaults(self):
        self.write_accounts_config({
            "tools": {
                "gemini": {
                    "plan": "Configured locally",
                    "configured_accounts": "2",
                    "plan_aliases": ["Local alias"],
                    "account_inventory": [{"slug": "primary", "priority": 10}],
                },
            },
        })
        ctx = tool_context("gemini", today=date(2026, 5, 22))
        self.assertEqual(ctx["plan"], "Configured locally")
        self.assertEqual(ctx["configured_accounts"], 2)
        self.assertEqual(ctx["plan_aliases"], ["Local alias"])
        self.assertEqual(ctx["account_inventory"], [{"slug": "primary", "priority": 10}])

    def test_local_plan_events_have_days_until(self):
        self.write_accounts_config({
            "gemini": {
                "plan_events": [
                    {"kind": "local", "label": "Local event", "effective_date": "2026-06-01"},
                ],
            },
        })
        ctx = tool_context("gemini", today=date(2026, 5, 22))
        event = ctx["plan_events"][0]
        self.assertEqual(event["days_until"], 10)
        self.assertFalse(event["expired"])
        self.assertTrue(event["imminent"])

    def test_plan_events_without_effective_date_skip_days_until(self):
        """Events that have no effective_date should NOT get days_until."""
        self.write_accounts_config({
            "gemini": {
                "plan_events": [
                    {"kind": "local", "label": "No date"},
                ],
            },
        })
        ctx = tool_context("gemini", today=date(2026, 5, 22))
        for event in ctx.get("plan_events", []):
            if "effective_date" not in event:
                self.assertNotIn("days_until", event)

    def test_codex_has_no_plan_events_by_default(self):
        ctx = tool_context("codex")
        self.assertNotIn("plan_events", ctx)

    def test_claude_has_no_plan_events(self):
        """Claude has no shipped plan_events — verify the neutral shape."""
        ctx = tool_context("claude")
        self.assertNotIn("plan_events", ctx)


class TestStamp(IsolatedEcoHomeMixin, unittest.TestCase):
    """stamp: enriching collector payloads with configured context."""

    def test_stamp_adds_neutral_configured_accounts(self):
        payload = {"ok": True, "accounts": 1}
        result = stamp(payload, "claude")
        self.assertEqual(result["configured_accounts"], 0)
        self.assertEqual(result["accounts"], 1)

    def test_stamp_preserves_detected_when_mismatch(self):
        """When detected != configured, accounts remains collector-owned."""
        self.write_accounts_config({"claude": {"configured_accounts": 2}})
        payload = {"ok": True, "accounts": 1}
        result = stamp(payload, "claude")
        self.assertEqual(result["configured_accounts"], 2)
        self.assertEqual(result["accounts"], 1)
        self.assertEqual(result["detected_accounts"], 1)

    def test_stamp_no_detected_field_when_matches(self):
        self.write_accounts_config({"claude": {"configured_accounts": 2}})
        payload = {"ok": True, "accounts": 2}
        result = stamp(payload, "claude")
        self.assertNotIn("detected_accounts", result)

    def test_stamp_adds_account_inventory(self):
        self.write_accounts_config({
            "gemini": {
                "account_inventory": [{"slug": "primary", "priority": 10}],
            },
        })
        payload = {"ok": True}
        result = stamp(payload, "gemini")
        self.assertIn("account_inventory", result)
        self.assertEqual(result["account_inventory"], [{"slug": "primary", "priority": 10}])

    def test_stamp_adds_plan_events_for_gemini(self):
        self.write_accounts_config({
            "gemini": {
                "plan_events": [{"kind": "local", "label": "Configured locally"}],
            },
        })
        payload = {"ok": True}
        result = stamp(payload, "gemini")
        self.assertIn("plan_events", result)
        self.assertGreater(len(result["plan_events"]), 0)

    def test_stamp_does_not_overwrite_existing_plan(self):
        payload = {"ok": True, "plan": "Custom Plan"}
        result = stamp(payload, "claude")
        # setdefault should keep the existing plan
        self.assertEqual(result["plan"], "Custom Plan")

    def test_stamp_sets_plan_when_absent(self):
        payload = {"ok": True}
        result = stamp(payload, "claude")
        self.assertEqual(result["plan"], "Unknown")

    def test_stamp_adds_plan_aliases_for_gemini(self):
        self.write_accounts_config({"gemini": {"plan_aliases": ["Local alias"]}})
        payload = {"ok": True}
        result = stamp(payload, "gemini")
        self.assertIn("plan_aliases", result)
        self.assertIn("Local alias", result["plan_aliases"])

    def test_stamp_non_dict_payload_returns_as_is(self):
        """Non-dict payloads should pass through unchanged."""
        result = stamp("not a dict", "claude")
        self.assertEqual(result, "not a dict")

    def test_stamp_with_no_accounts_field(self):
        """Payload without 'accounts' should still get configured_accounts."""
        payload = {"ok": True}
        result = stamp(payload, "claude")
        self.assertEqual(result["configured_accounts"], 0)
        self.assertEqual(result["accounts"], 0)

    def test_stamp_without_tool_argument_uses_payload_tool(self):
        payload = {"tool": "gemini", "accounts": 0}
        result = stamp(payload)
        self.assertEqual(result["configured_accounts"], 0)
        self.assertEqual(result["accounts"], 0)

    def test_stamp_unknown_tool(self):
        payload = {"ok": True, "accounts": 1}
        result = stamp(payload, "unknown_tool")
        self.assertEqual(result["configured_accounts"], 0)
        self.assertEqual(result["accounts"], 1)
        self.assertEqual(result["plan"], "Unknown")

    def test_stamp_accounts_none_detected(self):
        """When detected is None, no detected_accounts mismatch field."""
        payload = {"ok": True}
        result = stamp(payload, "codex")
        self.assertNotIn("detected_accounts", result)


class TestContextIntegrity(unittest.TestCase):
    """Verify the static _CONTEXT data structure is well-formed."""

    def test_all_tools_have_required_keys(self):
        for tool, ctx in _CONTEXT.items():
            with self.subTest(tool=tool):
                self.assertIn("plan", ctx)
                self.assertIn("configured_accounts", ctx)
                self.assertIn("account_inventory", ctx)
                self.assertIsInstance(ctx["account_inventory"], list)

    def test_all_accounts_have_slug_and_priority(self):
        for tool, ctx in _CONTEXT.items():
            for acct in ctx["account_inventory"]:
                with self.subTest(tool=tool, slug=acct.get("slug")):
                    self.assertIn("slug", acct)
                    self.assertIn("priority", acct)
                    self.assertIsInstance(acct["priority"], int)
                    self.assertGreater(acct["priority"], 0)

    def test_all_plan_events_have_kind_and_label(self):
        for tool, ctx in _CONTEXT.items():
            for event in ctx.get("plan_events", []):
                with self.subTest(tool=tool, kind=event.get("kind")):
                    self.assertIn("kind", event)
                    self.assertIn("label", event)

    def test_slugs_are_unique_per_tool(self):
        for tool, ctx in _CONTEXT.items():
            slugs = [a["slug"] for a in ctx["account_inventory"]]
            with self.subTest(tool=tool):
                self.assertEqual(len(slugs), len(set(slugs)),
                                 f"Duplicate slugs in {tool}: {slugs}")


if __name__ == "__main__":
    unittest.main()
