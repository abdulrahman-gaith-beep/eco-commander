# Frequently Asked Questions

## General

### What is eco-commander?

A unified CLI and SwiftBar control surface for managing a multi-tool AI
ecosystem on macOS. It orchestrates Claude Code, Gemini CLI, Codex CLI,
Ollama, and MCP servers from a single dashboard, and monitors Cursor status.

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

1. **Bash version:** The core `eco` CLI and `make install` work on macOS default bash (3.2). Recipes that use newer syntax (associative arrays, `[[ ]]` with regex) require Bash 5+ via Homebrew (`brew install bash`). If a recipe fails with a syntax error, check your bash version first.
2. **Permissions:** The installer **refuses** to run as root or via `sudo`. Run all installation steps as your normal macOS user.
3. **Dependencies:** Run `brew bundle --file=Brewfile` to install required tools like `jq`, `git`, and `curl`.
4. **Directory health:** Ensure that the installer can create real `~/.eco/bin` and `~/.eco/recipes` directories. They should contain individual symlinks to `src/bin/*` and `src/recipes/*.sh`, not be symlinked directories themselves.

See [`getting-started/troubleshooting.md`](./getting-started/troubleshooting.md).

### Do I need SwiftBar?

SwiftBar is optional. The CLI (`eco status`) works without it. SwiftBar
adds the macOS menu-bar widget for at-a-glance ecosystem monitoring.

---

## Recipes & Gemini

### Do recipes require the Gemini CLI?

It depends on the recipe. Core features like `eco status`, `eco list`, and the background `scheduler` work without Gemini tooling. However, the `ask`, `research`, `swarm`, and `snapshot` recipes require either an authenticated [Gemini CLI](https://github.com/google-gemini/gemini-cli) or a working `gem-smart` wrapper.

### What is `gem-smart` and do I need it?

`gem-smart` is an optional opinionated wrapper around the Gemini CLI used in some workflows for smarter model selection and parameter defaults. Recipes use the model shortcut from `ECO_GEM_MODEL` (default `3f`) if `gem-smart` is available but will automatically fall back to plain `gemini` if it is not. You do not need it if you have the standard Gemini CLI configured on your `PATH`.

### How do I run a fully private/local query?

If you have [Ollama](https://ollama.com/) installed and running, you can trigger a local-only path by including privacy-related keywords in your prompt. Running `eco do ask "my private secret question"` will detect keywords like `private`, `secret`, `internal`, or `confidential` and route the request to a local Ollama model instead of a cloud provider.

---

## Usage

### Why does `eco doctor` say a LaunchAgent is not loaded — is that an error?

No. `eco doctor` reports the status of all ecosystem components to help you understand your current setup. Since the `scheduler` and `swiftbar` LaunchAgents are optional or environment-dependent, "not loaded" is merely informational. `eco doctor` only exits with an error (status 1) if the core `eco` CLI is missing or if Python dependencies for the poller/scheduler modules fail to import.

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

## Security & Privacy

### Does eco-commander send my data anywhere?

No. eco-commander has no network daemon and does not "phone home." It is a local-only orchestrator that invokes provider CLIs (like `gemini`, `claude`, or `ollama`) that you have already installed. Data only leaves your machine if you explicitly invoke a recipe or command that calls a cloud-based provider.

### How is my data protected?

- **Local Storage:** All configuration, logs, and snapshots are stored in `~/.eco/` with `0700` permissions.
- **No Sudo:** The installer refuses to run as root, ensuring the tool operates strictly within your user's permission boundary.
- **Privacy Routing:** Integrated recipes include logic to intercept sensitive keywords and divert them to local-only models (via Ollama) to prevent accidental leakage to cloud providers.

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
