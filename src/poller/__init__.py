"""eco-commander usage poller — multi-tool quota/usage collector.

Reads token usage from Claude Code JSONL, Codex CLI sessions, and Gemini
Cloud APIs. Merges per-tool data into ~/.eco/current/usage.json for the
SwiftBar widget and scheduler routing.

Run-once-then-exit semantics: invoked by launchd every 60 seconds.
NOT a long-running daemon.
"""

from __future__ import annotations

__all__ = ["__version__"]
__version__ = "3.0.0"
