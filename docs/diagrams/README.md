# Architecture & Design Diagrams

This directory contains visual architecture and flow diagrams for `eco-commander`. The diagrams are written in Markdown using **Mermaid** blocks, which render natively in GitHub and supported editors.

→ Back to [Documentation Index](../INDEX.md)

---

## Diagrams Directory

| Diagram | Focus | Description |
|---------|-------|-------------|
| [architecture.md](./architecture.md) | System topology | High-level component arrangement and external dependencies. |
| [data-flow.md](./data-flow.md) | Data routing | How metrics and state files move between collectors, snapshots, and SwiftBar. |
| [scheduler-flow.md](./scheduler-flow.md) | Execution loop | Step-by-step logic for the quota-aware multi-provider scheduler. |
| [meter-state-machine.md](./meter-state-machine.md) | Quota state | Lifecycle and transition thresholds for individual providers' quota meters. |
| [poller-pipeline.md](./poller-pipeline.md) | Collection loop | Periodic (60s) execution sequence for the background usage collector. |
| [alert-pipeline.md](./alert-pipeline.md) | Audit pipeline | How snapshot layer issues are captured, categorized, and escalated. |
| [account-swap-flow.md](./account-swap-flow.md) | Rotation | Safe credential storage and execution flow for rotating API accounts. |
| [widget-rendering.md](./widget-rendering.md) | Rendering | Sources of data, thresholds, and execution speed limits for SwiftBar. |
| [filesystem-layout.md](./filesystem-layout.md) | Paths | Ownership boundary and structures inside `~/.eco/` at runtime. |
| [install-lifecycle.md](./install-lifecycle.md) | Lifecycle | Step-by-step installation, launchd activation, and validation logic. |
| [ci-pipeline.md](./ci-pipeline.md) | Quality gates | GitHub Actions automation workflows, required checks, and releases. |
| [snapshot-lifecycle.md](./snapshot-lifecycle.md) | Immutability | Atomic snapshots generation, layer execution, and active-symlink swap. |
| [module-deps.md](./module-deps.md) | Code dependencies | Directed dependency graph of the Python and shell codebase. |
| [test-architecture.md](./test-architecture.md) | QA framework | Structural arrangement of Bats, unittest, and end-to-end (E2E) suites. |

---

## Modifying Diagrams

When adding or updating diagrams:
1. Wrap all Mermaid nodes and labels properly.
2. Avoid unescaped angle brackets (`<` and `>`) inside nodes, as they break Markdown/HTML rendering. Use quotes or HTML entities (e.g. `&lt;` or `&gt;`).
3. Validate the syntax locally before committing:
   ```bash
   bash docs/scripts/validate-mermaid.sh
   ```
