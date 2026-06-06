# Frequently Asked Questions

## General

### What is eco-commander?

A unified CLI and SwiftBar control surface for managing a multi-tool AI
ecosystem on macOS. It orchestrates Claude Code, Gemini CLI, Codex CLI,
Ollama, Cursor, and MCP servers from a single dashboard.

### Does eco-commander run AI models?

No. It orchestrates, inspects, and schedules work across tools that run
models. It does not host or serve models itself.

### Is it macOS-only?

Yes. eco-commander depends on SwiftBar (macOS menu bar), launchd (macOS
daemon manager), and macOS-specific paths. Linux support is on the
[long-term roadmap](../ROADMAP.md).

---

## Installation

### `make install` failed — what do I check?

1. Ensure a supported Bash is available: `bash --version`. The core
   installer targets the macOS system Bash; Homebrew Bash is recommended if a
   recipe fails on newer shell syntax.
2. Run `brew bundle --file=Brewfile` to install dependencies.
3. Check that the installer can create or use real `~/.eco/bin` and
   `~/.eco/recipes` directories. They should contain individual symlinks to
   `src/bin/*` and `src/recipes/*.sh`, not be symlinked directories.

See [`docs/getting-started/troubleshooting.md`](./getting-started/troubleshooting.md).

### Do I need SwiftBar?

SwiftBar is optional. The CLI (`eco status`) works without it. SwiftBar
adds the macOS menu-bar widget for at-a-glance ecosystem monitoring.

---

## Usage

### How do I add a new recipe?

1. Create `src/recipes/my-recipe.sh` with `set -euo pipefail`.
2. Add `# DESC:`, `# INPUTS:`, `# OUTPUT:`, `# USES:` annotations.
3. Run `eco list` to verify it appears in the catalog.
4. Add a Bats test under `tests/bats/recipes/`.

See [`docs/subsystems/recipes.md`](./subsystems/recipes.md).

### How do I add a new scheduler adapter?

Implement the `Adapter` protocol from `src/scheduler/adapters/base.py`,
then register it in `src/scheduler/adapters/__init__.py`. See existing
adapters (codex, gemini, ollama) for reference.

---

## Development

### Why is Python used alongside Bash?

The usage monitor (poller) and job scheduler require structured data
parsing, OAuth token refresh, and complex state management. Bash is used
for the CLI router, SwiftBar plugin, and recipes. See
[ADR 0004](./adr/0004-usage-monitor-python-carveout.md).

### How do I run tests?

```bash
make test         # all suites (Bats + Python + E2E)
make test-fast    # Bats + Python only (~15s)
make test-bats    # Bats only
make test-python  # Python only
```
