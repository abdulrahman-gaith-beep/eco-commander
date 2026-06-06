# Module Dependency Graph

Internal import dependency graph across eco-commander's Python packages
(`common`, `poller`, `scheduler`). Auto-generated from `src/tools/dep_graph.py`. Regenerate with:

```bash
PYTHONPATH=src python3 -m tools.dep_graph --format=mermaid
```

```mermaid
graph LR
    poller_discovery["poller.discovery"] --> common_config["common.config"]
    poller_main["poller.main"] --> common_config["common.config"]
    poller_main["poller.main"] --> poller["poller"]
    poller_notify["poller.notify"] --> common_config["common.config"]
    scheduler_adapters["scheduler.adapters"] --> scheduler_adapters_base["scheduler.adapters.base"]
    scheduler_adapters["scheduler.adapters"] --> scheduler_adapters_claude["scheduler.adapters.claude"]
    scheduler_adapters["scheduler.adapters"] --> scheduler_adapters_codex["scheduler.adapters.codex"]
    scheduler_adapters["scheduler.adapters"] --> scheduler_adapters_gemini["scheduler.adapters.gemini"]
    scheduler_adapters["scheduler.adapters"] --> scheduler_adapters_ollama["scheduler.adapters.ollama"]
    scheduler_adapters_claude["scheduler.adapters.claude"] --> scheduler_adapters_base["scheduler.adapters.base"]
    scheduler_adapters_claude["scheduler.adapters.claude"] --> scheduler_queue["scheduler.queue"]
    scheduler_adapters_codex["scheduler.adapters.codex"] --> scheduler_adapters_base["scheduler.adapters.base"]
    scheduler_adapters_codex["scheduler.adapters.codex"] --> scheduler_queue["scheduler.queue"]
    scheduler_adapters_gemini["scheduler.adapters.gemini"] --> scheduler_adapters_base["scheduler.adapters.base"]
    scheduler_adapters_gemini["scheduler.adapters.gemini"] --> scheduler_queue["scheduler.queue"]
    scheduler_adapters_ollama["scheduler.adapters.ollama"] --> scheduler_adapters_base["scheduler.adapters.base"]
    scheduler_adapters_ollama["scheduler.adapters.ollama"] --> scheduler_queue["scheduler.queue"]
    scheduler_cli["scheduler.cli"] --> scheduler_dispatcher["scheduler.dispatcher"]
    scheduler_cli["scheduler.cli"] --> scheduler_queue["scheduler.queue"]
    scheduler_cli["scheduler.cli"] --> scheduler_routing["scheduler.routing"]
    scheduler_dispatcher["scheduler.dispatcher"] --> common_config["common.config"]
    scheduler_dispatcher["scheduler.dispatcher"] --> scheduler_adapters["scheduler.adapters"]
    scheduler_dispatcher["scheduler.dispatcher"] --> scheduler_adapters_base["scheduler.adapters.base"]
    scheduler_dispatcher["scheduler.dispatcher"] --> scheduler_queue["scheduler.queue"]
    scheduler_dispatcher["scheduler.dispatcher"] --> scheduler_routing["scheduler.routing"]
    scheduler_queue["scheduler.queue"] --> common_config["common.config"]
```

**Key observations:**
- `common.config` is the shared dependency root — imported by both poller and scheduler subsystems
- No circular dependencies detected
- Poller modules with internal imports (`pace.py` → `caps.py`) use relative imports within the package and are not captured at the cross-package level by `dep_graph.py`
- All four scheduler adapters share the same dependency pattern: `adapters.base` + `queue`

**Related docs:** [Architecture](../architecture.md) · [Poller Pipeline](poller-pipeline.md) · [Scheduler Flow](scheduler-flow.md)
