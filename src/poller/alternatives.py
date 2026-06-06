"""Alternatives — fallback tools when cloud quota is saturated.

Static catalog of non-metered tools the user can route to when Claude /
Gemini / Codex meters are in 'ahead' (overspending) or 'hard_wall' state.

Two classes:
  * `status: "stub"`   — has its own quota but we can't poll it yet
                         (externally tracked tools configured by the user)
  * `status: "always_available"` — no quota; route freely
                         (VS Code editor; local Ollama when installed)

T4 §5 — stubs are `ok: true` (not false) so the widget doesn't paint a
permanent red badge causing alarm fatigue.
M3 — caller-side state hooks use setdefault patterns.
"""
from __future__ import annotations

import logging
import shutil
import subprocess
from typing import Any

logger = logging.getLogger("eco.poller.alternatives")


def _ollama_models(timeout_s: int = 3) -> list[dict[str, str]]:
    """Best-effort: list installed Ollama models with sizes.

    Returns ``[]`` on any failure — no exceptions propagate. The poller
    runs every 60s; transient ollama-list failures are uninteresting.
    """
    if shutil.which("ollama") is None:
        return []
    try:
        result = subprocess.run(
            ["ollama", "list"],
            capture_output=True, text=True,
            timeout=timeout_s, check=False,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        logger.debug(f"ollama list failed: {exc}")
        return []
    if result.returncode != 0:
        return []

    models: list[dict[str, str]] = []
    lines = result.stdout.splitlines()[1:]  # skip header
    for line in lines:
        parts = line.split()
        if len(parts) < 4 or parts[0] == "NAME":
            continue
        # `ollama list` output: NAME  ID  SIZE_NUM  SIZE_UNIT  MODIFIED...
        models.append({
            "name": parts[0],
            "size": f"{parts[2]} {parts[3]}",
        })
    return models


def collect() -> dict[str, Any]:
    """Return the alternatives block for `usage.json`.

    Shape locked in T3+T4: every entry has `ok` + `status` + `note`.
    """
    ollama_path = shutil.which("ollama")
    ollama_ok = ollama_path is not None
    ollama_models = _ollama_models() if ollama_ok else []
    ollama_status = "always_available" if ollama_ok else "missing_binary"
    ollama_note = (
        "local models — unlimited, electricity-bound"
        if ollama_ok
        else "ollama command not found on PATH; install Ollama to use local models"
    )

    return {
        "antigravity": {
            "ok": True,
            "status": "stub",
            "note": "external tool — no live tracking yet",
            "category": "metered_alternative",
        },
        "cursor": {
            "ok": True,
            "status": "stub",
            "note": "external tool — no live tracking yet",
            "category": "metered_alternative",
        },
        "vs_code": {
            "ok": True,
            "status": "always_available",
            "note": "editor only — pair with Copilot / Continue / Ollama",
            "category": "editor",
        },
        "ollama": {
            "ok": ollama_ok,
            "status": ollama_status,
            "note": ollama_note,
            "category": "local_llm",
            "models": ollama_models,
        },
    }
