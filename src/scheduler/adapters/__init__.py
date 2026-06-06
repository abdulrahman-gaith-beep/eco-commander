"""Provider adapters — one module per provider CLI we shell out to."""

from __future__ import annotations

from scheduler.adapters.base import Adapter, AdapterResult

__all__ = ["Adapter", "AdapterResult", "get_adapter"]


def get_adapter(provider: str) -> Adapter:
    """Lazy import to keep cold-start fast."""
    if provider == "claude":
        from scheduler.adapters.claude import ClaudeAdapter
        return ClaudeAdapter()
    if provider == "codex":
        from scheduler.adapters.codex import CodexAdapter
        return CodexAdapter()
    if provider == "gemini":
        from scheduler.adapters.gemini import GeminiAdapter
        return GeminiAdapter()
    if provider == "ollama":
        from scheduler.adapters.ollama import OllamaAdapter
        return OllamaAdapter()
    raise ValueError(f"unknown provider: {provider!r}")
