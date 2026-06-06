"""Tests for poller.caps neutral default constants.

Validates:
- All required token cap constants use neutral public defaults
- Window constants are sane (5h session, 7d weekly)
- Threshold constants are in valid percentage ranges
- Back-compat aliases match their canonical values
- CACHE_READ_WEIGHT is non-negative and at most 1
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "src"))

from poller.caps import (
    CACHE_READ_WEIGHT,
    CLAUDE_DEFAULT_5H_TOKENS,
    CLAUDE_DEFAULT_7D_ALL_TOKENS,
    CLAUDE_DEFAULT_7D_SONNET_TOKENS,
    CLAUDE_MAX20X_5H_TOKENS,
    CLAUDE_MAX20X_7D_ALL_TOKENS,
    CLAUDE_MAX20X_7D_SONNET_TOKENS,
    CLAUDE_MAX20X_SESSION_TOKENS,
    CLAUDE_MAX20X_WEEKLY_TOKENS,
    CODEX_DEFAULT_SESSION_TOKENS,
    CODEX_DEFAULT_WEEKLY_TOKENS,
    CODEX_PRO_SESSION_TOKENS,
    CODEX_PRO_WEEKLY_TOKENS,
    CRIT_PCT,
    SESSION_WINDOW_SECONDS,
    UNKNOWN_TOKEN_CAP,
    WARN_PCT,
    WEEKLY_WINDOW_SECONDS,
    is_unknown_token_cap,
)


class TestClaudeCaps(unittest.TestCase):
    """Claude usage cap default checks."""

    def test_neutral_defaults(self):
        self.assertEqual(CLAUDE_DEFAULT_5H_TOKENS, UNKNOWN_TOKEN_CAP)
        self.assertEqual(CLAUDE_DEFAULT_7D_ALL_TOKENS, UNKNOWN_TOKEN_CAP)
        self.assertEqual(CLAUDE_DEFAULT_7D_SONNET_TOKENS, UNKNOWN_TOKEN_CAP)

    def test_backcompat_aliases(self):
        self.assertEqual(CLAUDE_MAX20X_5H_TOKENS, CLAUDE_DEFAULT_5H_TOKENS)
        self.assertEqual(CLAUDE_MAX20X_7D_ALL_TOKENS, CLAUDE_DEFAULT_7D_ALL_TOKENS)
        self.assertEqual(
            CLAUDE_MAX20X_7D_SONNET_TOKENS,
            CLAUDE_DEFAULT_7D_SONNET_TOKENS,
        )
        self.assertEqual(CLAUDE_MAX20X_SESSION_TOKENS, CLAUDE_MAX20X_5H_TOKENS)
        self.assertEqual(CLAUDE_MAX20X_WEEKLY_TOKENS, CLAUDE_MAX20X_7D_ALL_TOKENS)


class TestCodexCaps(unittest.TestCase):
    """Codex usage cap default checks."""

    def test_neutral_defaults(self):
        self.assertEqual(CODEX_DEFAULT_SESSION_TOKENS, UNKNOWN_TOKEN_CAP)
        self.assertEqual(CODEX_DEFAULT_WEEKLY_TOKENS, UNKNOWN_TOKEN_CAP)

    def test_backcompat_aliases(self):
        self.assertEqual(CODEX_PRO_SESSION_TOKENS, CODEX_DEFAULT_SESSION_TOKENS)
        self.assertEqual(CODEX_PRO_WEEKLY_TOKENS, CODEX_DEFAULT_WEEKLY_TOKENS)


class TestUnknownTokenCap(unittest.TestCase):
    """UNKNOWN_TOKEN_CAP should be neutral but safe for division."""

    def test_nonzero_integer(self):
        self.assertIsInstance(UNKNOWN_TOKEN_CAP, int)
        self.assertEqual(UNKNOWN_TOKEN_CAP, 1)

    def test_helper_detects_only_sentinel(self):
        self.assertTrue(is_unknown_token_cap(UNKNOWN_TOKEN_CAP))
        self.assertFalse(is_unknown_token_cap(1_000_000))


class TestCacheReadWeight(unittest.TestCase):
    """CACHE_READ_WEIGHT constraints."""

    def test_non_negative(self):
        self.assertGreaterEqual(CACHE_READ_WEIGHT, 0.0)

    def test_at_most_one(self):
        self.assertLessEqual(CACHE_READ_WEIGHT, 1.0)

    def test_currently_zero(self):
        """Per Anthropic: cached reads don't count toward rate limits."""
        self.assertEqual(CACHE_READ_WEIGHT, 0.00)


class TestWindowConstants(unittest.TestCase):
    """Window durations should match expected calendar intervals."""

    def test_session_window_is_5_hours(self):
        self.assertEqual(SESSION_WINDOW_SECONDS, 5 * 3600)

    def test_weekly_window_is_7_days(self):
        self.assertEqual(WEEKLY_WINDOW_SECONDS, 7 * 24 * 3600)


class TestThresholds(unittest.TestCase):
    """WARN_PCT and CRIT_PCT are valid percentages."""

    def test_warn_pct_range(self):
        self.assertGreater(WARN_PCT, 0)
        self.assertLess(WARN_PCT, 100)

    def test_crit_pct_range(self):
        self.assertGreater(CRIT_PCT, 0)
        self.assertLessEqual(CRIT_PCT, 100)

    def test_crit_greater_than_warn(self):
        self.assertGreater(CRIT_PCT, WARN_PCT)

    def test_expected_values(self):
        """Pin known values to catch accidental drift."""
        self.assertEqual(WARN_PCT, 80)
        self.assertEqual(CRIT_PCT, 95)


if __name__ == "__main__":
    unittest.main()
