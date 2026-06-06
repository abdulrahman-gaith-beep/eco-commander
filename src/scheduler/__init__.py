"""eco-commander job scheduler — quota-aware multi-provider dispatcher.

Reads job queue from ~/.eco/queue/jobs.yaml and meter state from
~/.eco/state/notify.json (written by src/poller). Walks each job's
model_preference ladder, fires via the first adapter whose meter has
capacity, records the result, and re-queues failures with backoff.

Run-once-then-exit semantics: invoked by launchd every N minutes.
NOT a long-running daemon.
"""

from __future__ import annotations

__all__ = ["__version__"]
__version__ = "0.2.0"
