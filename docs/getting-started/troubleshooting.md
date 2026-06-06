# Troubleshooting

> Symptom-to-fix guide covering the most common eco-commander failure modes. For step-by-step operational procedures, see [../operations/runbook.md](../operations/runbook.md).

## Quick-reference table

| Symptom | Likely cause | First fix |
|---------|-------------|-----------|
| `eco: command not found` | `~/.eco/bin` not on PATH | [Add to PATH](#eco-command-not-found) |
| Widget shows stale icon, never refreshes | SwiftBar pointed at wrong plugin folder | [Reinstall plugin](#widget-shows-stale-icon-and-never-refreshes) |
| `eco-commander.1s.sh: No such file or directory` | Pre-0.2.0 router in SwiftBar | [Update and reinstall](#eco-commander1ssh-no-such-file-or-directory) |
| `eco status` prints nothing or hangs | `eco-commander.15s.sh` fails to source deps | [Run with debug](#eco-status-prints-nothing-or-hangs) |
| `usage.json` missing or stale | Poller LaunchAgent not loaded | [Check agent](#usagejson-missing-or-stale) |
| Llama count is `0/N` | Ollama idle or daemon lacks Homebrew PATH | [Check ollama](#llama-count-is-0n) |
| `eco doctor` reports Python import failed | Missing Python deps or wrong PYTHONPATH | [Fix imports](#eco-doctor-reports-python-import-failed) |
| Bats tests fail: `command not found: bats` | bats-core not installed | [Install bats-core](#bats-tests-fail-command-not-found-bats) |
| A recipe leaks a secret into `_outputs/` | Recipe writes env vars to log | [Security response](#a-recipe-leaks-a-secret-into-_outputs) |

---

## `eco: command not found`

**Cause:** `~/.eco/bin` is not on `PATH`. This is required because `make install` symlinks the CLI into `~/.eco/bin/eco`, not into `/usr/local/bin`.

**Fix:** Add the following to `~/.zshrc` (or `~/.bashrc`), then restart your terminal or run `source ~/.zshrc`:

```bash
export PATH="$HOME/.eco/bin:$PATH"
```

**Verify:**

```bash
which eco          # should print ~/.eco/bin/eco
eco status
```

---

## Widget shows stale icon and never refreshes

**Cause:** SwiftBar reads from one specific plugin folder. If that folder does not match the path the installer wrote to, the widget file is never executed. Older installs could also leave an empty directory at the plugin path instead of a symlink.

**Fix:**

```bash
make uninstall && make install
```

This removes any stale directory or foreign symlink and writes a clean symlink to `~/Library/Application Support/SwiftBar/Plugins/eco-commander.15s.sh`.

If your SwiftBar plugin folder is in a non-default location, pass it explicitly:

```bash
SWIFTBAR_PLUGIN_DIR=~/my-swiftbar-plugins make install
```

Then verify the plugin folder in **SwiftBar → Preferences → Plugin folder** matches the path above.

---

## `eco-commander.1s.sh: No such file or directory`

**Cause:** You have an old version of eco-commander. Before v0.2.0 the router script was named `eco-commander.1s.sh` (and was also briefly named `eco-commander.30s.sh`); it is now `eco-commander.15s.sh`.

**Fix:**

```bash
# From your eco-commander checkout:
git pull origin main
make uninstall && make install
```

SwiftBar will auto-detect the new filename on next refresh.

---

## `eco status` prints nothing or hangs

**Cause:** `eco-commander.15s.sh` cannot source one of its dependencies — typically a missing Python module, a stale `~/.eco/current/state.json`, or a PATH mismatch in the SwiftBar environment.

**Fix:**

```bash
# Run the widget script directly with debug output
bash -x ~/.eco/bin/eco-commander.15s.sh --cli 2>&1 | head -60

# Run the health check
eco doctor
~/.eco/bin/eco-alerts.sh repo-health
```

Common sub-causes:

- **Missing `state.json`:** Run `eco do snapshot` to regenerate it.
- **Python error:** See [eco doctor reports Python import failed](#eco-doctor-reports-python-import-failed).
- **Homebrew not on PATH in SwiftBar environment:** Add `/opt/homebrew/bin` (Apple Silicon) or `/usr/local/bin` (Intel) to your login shell PATH, then restart SwiftBar.

---

## `usage.json` missing or stale

**Cause:** The usage poller LaunchAgent (`com.eco-commander.usage-poller`) is not loaded or has crashed.

**Fix:**

```bash
# Check if the agent is loaded
launchctl list com.eco-commander.usage-poller

# If not loaded, reinstall LaunchAgents
bash scripts/install-launchagents.sh

# Inspect the agent log
tail -50 ~/.eco/logs/usage-poller.err.log
```

If the log shows authentication errors, you may need to re-authorize the poller for the relevant tool. See [eco account-swap](./usage.md#account-swap-subcommands) to rotate credentials.

**Verify:**

```bash
eco doctor    # "usage.json fresh" if poller is working
```

---

## Snapshots disagree with reality

**Cause:** The snapshot is a point-in-time capture. It does not auto-update.

**Fix:** Refresh the snapshot, then reopen the widget:

```bash
eco do snapshot
eco status
```

---

## Llama count is `0/N`

**Cause:** Ollama has `N` installed models but zero are currently loaded. This is normal after `ollama stop <model>` or when the daemon has been idle long enough to unload all models.

If the widget shows `0/0` while `ollama list` shows models in Terminal, SwiftBar may not have Homebrew on its PATH.

**Fix:**

```bash
# Diagnose
~/.eco/bin/eco-alerts.sh debug-ollama

# If Homebrew is not on SwiftBar's PATH, add it to your login shell:
# Apple Silicon:
echo 'export PATH="/opt/homebrew/bin:$PATH"' >> ~/.zprofile
# Intel:
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zprofile

# Then restart SwiftBar
killall SwiftBar && open /Applications/SwiftBar.app
```

---

## `eco doctor` reports Python import failed

**Cause:** The poller or scheduler Python module cannot be imported. Common causes: missing `PYTHONPATH`, missing `pip` deps, or incorrect Python version.

**Fix:**

```bash
# Test imports manually (eco doctor uses this exact check)
PYTHONPATH="$PWD/src" \
  python3 -c "from poller import main; from scheduler import dispatcher"

# If that fails, check Python version
python3 --version   # must be 3.10-3.13

# Install/sync Python deps
bash scripts/setup-venv.sh
```

`eco doctor` normally resolves the repo through the installed symlink. If the
symlink is missing, dangling, or copied instead of linked, set it explicitly:

```bash
export ECO_COMMANDER_REPO=~/code/eco-commander
```

---

## Bats tests fail: `command not found: bats`

**Cause:** bats-core is not installed.

**Fix:**

```bash
brew install bats-core
make test
```

---

## A recipe leaks a secret into `_outputs/`

**Cause:** A recipe writes environment variables or tokens to its log output.

**Immediate response:**

1. Stop using that recipe.
2. Rotate the exposed credential immediately.
3. Delete or redact the affected file in `_outputs/`.
4. Open a security issue — see [../../SECURITY.md](../../SECURITY.md).

Recipes must redact secrets (e.g., via `sed 's/sk-[A-Za-z0-9]*/REDACTED/g'`) before writing any log output. For deep remediation guidance, see [../operations/runbook.md](../operations/runbook.md).

---

## Related

- [installation.md](./installation.md) — step-by-step installation
- [usage.md](./usage.md) — all subcommands and examples
- [../operations/runbook.md](../operations/runbook.md) — step-by-step operational procedures
- [../architecture.md](../architecture.md) — system component overview
