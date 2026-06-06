"""Centralized configuration for eco-commander.

Replaces the 8x duplicated ``Path(os.environ.get("ECO_HOME", Path.home() / ".eco"))``
pattern scattered across poller/ and scheduler/ modules.

All modules should import from here instead of constructing paths directly::

    from common.config import eco_config
    path = eco_config().current_dir / "usage.json"

The config object is frozen (immutable) and cached per process. It resolves
paths once at first access, respecting ``$ECO_HOME`` if set.
"""

from __future__ import annotations

import functools
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class EcoConfig:
    """Resolved filesystem paths for the eco-commander runtime.

    All directories are created lazily by the modules that write to them,
    not by this config object. Config is read-only and side-effect-free.
    """

    eco_home: Path
    current_dir: Path
    state_dir: Path
    queue_dir: Path
    log_dir: Path
    config_path: Path

    @classmethod
    def from_env(cls) -> EcoConfig:
        """Build from environment. Falls back to ``~/.eco`` if ``$ECO_HOME`` is unset."""
        eco_home = Path(os.environ.get("ECO_HOME", str(Path.home() / ".eco")))
        return cls(
            eco_home=eco_home,
            current_dir=eco_home / "current",
            state_dir=eco_home / "state",
            queue_dir=eco_home / "queue",
            log_dir=eco_home / "logs",
            config_path=eco_home / "config.json",
        )


@functools.lru_cache(maxsize=1)
def eco_config() -> EcoConfig:
    """Return the process-wide config singleton.

    Cached after first call. If ``$ECO_HOME`` changes mid-process (unusual),
    call ``eco_config.cache_clear()`` to re-resolve.
    """
    return EcoConfig.from_env()
