"""Shared test configuration and fixtures for eco-commander Python tests.

This module centralizes:
- sys.path setup (eliminates copy-paste in every test file)
- Shared temporary directory patterns
- Common test data factories

Usage:
    Tests can import shared utilities from here:
        from conftest import ECO_SRC_ROOT, create_eco_skeleton
"""

import sys
import time
from pathlib import Path

# ── Centralized path setup ─────────────────────────────────────────
# This makes `from poller.main import ...` and `from scheduler.cli import ...`
# work in all test files without repeating sys.path.insert everywhere.
ECO_SRC_ROOT = Path(__file__).resolve().parent.parent.parent / "src"
if str(ECO_SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(ECO_SRC_ROOT))

ECO_REPO_ROOT = ECO_SRC_ROOT.parent
ECO_TESTS_ROOT = Path(__file__).resolve().parent


# ── Shared test data factories ─────────────────────────────────────

def create_eco_skeleton(base_dir: str | Path) -> dict[str, Path]:
    """Create a minimal ~/.eco skeleton for integration tests.

    Returns a dict of key paths for easy reference.
    """
    base = Path(base_dir)
    paths = {
        "eco_home": base / ".eco",
        "current": base / ".eco" / "current",
        "bin": base / ".eco" / "bin",
        "recipes": base / ".eco" / "recipes",
        "logs": base / ".eco" / "logs",
        "profiles": base / ".ai-ecosystem" / "profiles",
    }
    for p in paths.values():
        p.mkdir(parents=True, exist_ok=True)

    # Current profile
    profile_root = base / ".ai-ecosystem"
    (profile_root / ".current-profile").write_text("core")

    return paths


def make_healthy_usage(ts: int | None = None) -> dict:
    """Create a healthy usage.json data dict with realistic values."""
    if ts is None:
        ts = int(time.time())
    return {
        "ts": ts,
        "version": 1,
        "claude": {
            "ok": True, "source": "jsonl", "plan": "Max 20x", "accounts": 1,
            "session": {"pct": 10, "resets_in": "4h 30m"},
            "weekly": {
                "pct": 25, "resets_in": "5d 2h",
                "pct_all": 25, "pct_sonnet": 5,
            },
        },
        "gemini": {
            "ok": True, "plan": "AI Ultra", "accounts": 2,
            "tiers": {
                "flash": {"pct": 5, "resets_in": "23h"},
                "flash_lite": {"pct": 2, "resets_in": "23h"},
                "pro": {"pct": 8, "resets_in": "23h"},
            },
        },
        "codex": {
            "ok": True, "source": "jsonl", "plan": "Business", "accounts": 1,
            "session": {"pct": 15, "resets_in": "3h 10m"},
            "weekly": {"pct": 20, "resets_in": "6d 1h"},
        },
    }


def make_error_usage(ts: int | None = None) -> dict:
    """Create a usage.json with all providers in error state."""
    if ts is None:
        ts = int(time.time())
    return {
        "ts": ts,
        "version": 1,
        "claude": {"ok": False, "error": "RuntimeError"},
        "gemini": {"ok": False, "error": "TimeoutError"},
        "codex": {"ok": False, "error": "FileNotFoundError"},
    }


def make_state(alert_count: int = 0) -> dict:
    """Create a state.json dict with a given number of alerts."""
    issues = [
        {"severity": "HIGH", "id": f"ISSUE-{i}", "desc": f"Test issue {i}"}
        for i in range(1, alert_count + 1)
    ]
    return {
        "generated_at": "2026-05-20T12:00:00Z",
        "snapshot_id": "test-snapshot",
        "layers": {"L1_core": {"issues": issues}},
    }
