# Installation

> How to install eco-commander on macOS, wire the SwiftBar plugin, and register background LaunchAgents.

## Prerequisites

- macOS 13+ (Apple Silicon or Intel)
- Bash 5+ recommended — install via Homebrew (`brew install bash`); the core `eco` CLI works on macOS default bash (3.2) but recipes with newer syntax require Bash 5+
- Python 3.10-3.13 (`>=3.10,<3.14`) — for the usage poller and scheduler modules
- `jq`, `git`, `curl`
- Optional: [SwiftBar](https://github.com/swiftbar/SwiftBar) for the menu-bar widget
- Optional: [bats-core](https://bats-core.readthedocs.io/) for running the test suite

### Optional recipe dependencies

The core `eco status`, `eco list`, and scheduler features work without Gemini tooling. The `ask`, `research`, `swarm`, and `snapshot` recipes require an authenticated Gemini CLI or a working `gem-smart` wrapper. They prefer `gem-smart 3.5f` when available and fall back to plain `gemini` when it is not. The `snapshot` recipe also requires a prompt library: explicit `$ECO_AUDIT_ROOT/prompts`, a populated `$HOME/.eco/ecosystem-audit/prompts`, or the public example prompts shipped under `examples/snapshot-prompts/`.

```bash
brew install jq bash bats-core shellcheck
brew install --cask swiftbar   # optional menu-bar widget
```

> **Note:** The installer refuses to run as root or under `sudo`. Run all steps as your normal macOS user.

## Install

```bash
git clone https://github.com/abdulrahman-gaith-beep/eco-commander.git \
  eco-commander
cd eco-commander
make install
```

`make install` delegates to `scripts/install.sh`, which does the following in order:

1. Creates `~/.eco/`, `~/.eco/bin/`, and `~/.eco/recipes/` (mode `0700`).
2. Symlinks every file under `src/bin/*` into `~/.eco/bin/`.
3. Symlinks every `src/recipes/*.sh` file into `~/.eco/recipes/`.
4. Refuses to overwrite regular files, non-owned directories, or symlinks pointing outside the repo.
5. Removes any stale symlinks from pre-0.2.0 installs (`eco-commander.30s.sh`, `usage-monitor.15s.sh`).
6. Writes the SwiftBar plugin symlink to `~/Library/Application Support/SwiftBar/Plugins/eco-commander.15s.sh`.
7. Skips LaunchAgents unless `ECO_INSTALL_LAUNCHAGENTS=1` is exported.

A dry run (no files written) is available:

```bash
bash scripts/install.sh --dry-run
```

### Add `~/.eco/bin` to PATH

Add the following line to `~/.zshrc` (or `~/.bashrc`) and restart your terminal:

```bash
export PATH="$HOME/.eco/bin:$PATH"
```

For the current terminal, run the export directly as well:

```bash
export PATH="$HOME/.eco/bin:$PATH"
```

Before running `eco do ask`, `eco do research`, `eco do swarm`, or `eco do snapshot`, verify the
Gemini backend you plan to use:

```bash
gemini --version
gemini -p "Reply with: eco ready"
```

If you use `gem-smart`, ensure `${ECO_GEM_SMART_BIN:-$HOME/bin/gem-smart}` is
executable or that `gem-smart` is on `PATH`.

### LaunchAgents (background services)

Install the usage poller and, when SwiftBar.app is installed, the SwiftBar autostart agent:

```bash
bash scripts/install-launchagents.sh
```

This renders and validates plist files into `~/Library/LaunchAgents/`. The usage poller is loaded by default, the SwiftBar autostart agent is loaded only when `/Applications/SwiftBar.app` exists, and the scheduler plist is opt-in:

| Agent label | Cadence | Purpose |
|-------------|---------|---------|
| `com.eco-commander.usage-poller` | Every 60 s | Collect quota data from Claude, Gemini, and Codex |
| `com.eco-commander.scheduler` | Every 120 s | Dispatch queued jobs (opt-in; see below) |
| `com.eco-commander.swiftbar` | At login | Open SwiftBar automatically |

The scheduler LaunchAgent is opt-in:

```bash
# Persist the plist but do NOT load it
ECO_SCHEDULER_PERSIST=1 bash scripts/install-launchagents.sh

# Persist AND load the scheduler
ECO_SCHEDULER_AUTO_LOAD=1 bash scripts/install-launchagents.sh
```

If SwiftBar is not installed in `/Applications`, the SwiftBar agent step is skipped automatically with a note to `brew install --cask swiftbar`.

### Log rotation (optional)

```bash
sudo scripts/install-log-rotation.sh
```

Installs a `newsyslog` config that rotates logs >= 1 MB daily, retaining five compressed archives.

## Verify

```bash
eco status                  # render the status panel
eco doctor                  # self-test; optional LaunchAgents/data are informational
ls -l ~/.eco/bin/eco        # confirm symlink points into the repo
make test                   # full BATS + Python + E2E suite
scripts/healthcheck.sh      # repo/runtime health (no macOS Library surface reads)
```

To include macOS Library surface checks (manual operator use only):

```bash
ECO_HEALTHCHECK_MACOS_SURFACES=1 scripts/healthcheck.sh
```

## SwiftBar wiring

SwiftBar reads from one plugin folder configured under **SwiftBar → Preferences → Plugin folder**. The installer writes to:

```text
~/Library/Application Support/SwiftBar/Plugins/eco-commander.15s.sh
```

If your SwiftBar plugin folder is in a non-default location, set `SWIFTBAR_PLUGIN_DIR` before running `make install`:

```bash
SWIFTBAR_PLUGIN_DIR=~/swiftbar-plugins make install
```

The widget refreshes every 15 seconds. The filename suffix (`.15s.`) encodes the interval; SwiftBar reads it automatically.

## Uninstall

```bash
make uninstall
bash scripts/uninstall-launchagents.sh
```

`make uninstall` removes all symlinks owned by this repo. Snapshots, recipe outputs, and `~/.eco/snapshots/` are preserved.

## Related

- [usage.md](./usage.md) — all `eco` subcommands, recipes, and examples
- [troubleshooting.md](./troubleshooting.md) — what to do when installation fails
- [../diagrams/install-lifecycle.md](../diagrams/install-lifecycle.md) — bootstrap, symlink wiring, and LaunchAgent sequence diagram
- [../architecture.md](../architecture.md) — system component overview
