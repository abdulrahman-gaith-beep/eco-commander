# Tutorial: Your First Successful Run

> **Diataxis type:** Tutorial — a guided, hands-on journey. You will clone the repository,
> wire up the environment, see the widget alive in your menu bar, run your first recipe,
> and recover from one common failure — all in a single session.

## What you will build

By the end of this tutorial you will have:

- A working `eco` CLI that responds to `eco status` and `eco list`.
- A live SwiftBar menu-bar widget (🟢/🟡/🔴) that refreshes every 15 seconds.
- Optional background LaunchAgents for the usage poller, SwiftBar autostart,
  and scheduler.
- A completed first recipe run (`eco do ask`) with output you can read immediately.
- Hands-on experience recovering from the most common new-install failure
  (`eco: command not found`), so you know what to do the next time something goes wrong.

**Time required:** approximately 15–20 minutes on a Mac with Homebrew already installed.

**Prerequisites:** macOS 13+, Homebrew, internet access. You do not need to know Python or
advanced bash. You *do* need to be running as your normal macOS user account — never `sudo`.

---

## Before you start: one safety note

The installer **refuses to run as root**. Every command below runs as your normal user. If
you accidentally open a root shell, close it and start fresh.

---

## Step 1 — Install system dependencies

eco-commander needs a handful of tools from Homebrew. Install them now:

```bash
brew install jq bash bats-core shellcheck
brew install --cask swiftbar      # the menu-bar host app
```

You should see:

```text
==> Fetching jq
...
==> Installing swiftbar
```

**Checkpoint:** confirm each tool is present:

```bash
jq --version       # should print jq-1.7 or later
bash --version     # should print GNU bash, version 5.x
shellcheck --version
open /Applications/SwiftBar.app
```

You should now see SwiftBar launch in your menu bar — it may show a generic icon or nothing
until the plugin is wired. That is expected; we fix it in Step 4.

---

## Step 2 — Clone and enter the repository

```bash
git clone https://github.com/abdulrahman-gaith-beep/eco-commander.git \
  eco-commander
cd eco-commander
```

**Expected output:**

```text
Cloning into 'eco-commander'...
remote: Enumerating objects: ...
Resolving deltas: 100% (...)
```

---

## Step 3 — Bootstrap: one command sets everything up

`make bootstrap` is the opinionated all-in-one setup path. It installs Homebrew packages,
creates the Python virtual environment, installs Git hooks, creates per-file symlinks under `~/.eco/`,
and runs a smoke test.

```bash
make bootstrap
```

Watch for these four milestone groups in the output:

```text
▶ Installing Homebrew dependencies
  ✓ Brewfile installed

▶ Setting up Python virtual environment
  ✓ Virtual environment ready at .venv/

▶ Installing Git hooks
  ✓ Pre-commit and commit-msg hooks installed

▶ Installing eco-commander (...)
  ✓ Installed — eco CLI available at ~/.eco/bin/eco
```

The final banner should read:

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  eco-commander development environment ready!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Next steps:
    make test       # run all tests
    make lint       # shellcheck + ruff
    make hygiene    # full pre-commit + workflow lint
    eco status      # check ecosystem status
```

**Checkpoint:** verify the symlink exists:

```bash
ls -l ~/.eco/bin/eco
```

You should see something like:

```text
lrwxr-xr-x  1 you  staff  ...  ~/.eco/bin/eco -> $HOME/projects/eco-commander/src/bin/eco
```

---

## Step 4 — Add `~/.eco/bin` to your PATH

`make bootstrap` installs the CLI to `~/.eco/bin/eco` but does not modify your shell profile
(that would be presumptuous). Do it yourself:

```bash
echo 'export PATH="$HOME/.eco/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**Checkpoint:**

```bash
which eco
```

Expected:

```text
~/.eco/bin/eco
```

> **Note for bash users:** substitute `~/.bashrc` for `~/.zshrc` above.

---

## Step 5 — Install the background LaunchAgents

The usage poller must run in the background to feed data to the widget. Install it:

```bash
bash scripts/install-launchagents.sh
```

**Expected output** (abbreviated):

```text
installed com.eco-commander.usage-poller -> ~/Library/LaunchAgents/com.eco-commander.usage-poller.plist
SwiftBar.app not found in /Applications; skipping SwiftBar autostart
  (or)
installed com.eco-commander.swiftbar -> ~/Library/LaunchAgents/com.eco-commander.swiftbar.plist

-- launchctl status --
-	0	com.eco-commander.usage-poller
-	0	com.eco-commander.swiftbar
```

The `-` in the PID column is normal at first boot — launchd has loaded the agent but it has
not yet run its first tick. Within 60 seconds the poller will write
`~/.eco/current/usage.json` and the widget will populate.

> **Scheduler (optional):** To also install the scheduler — which dispatches queued AI jobs
> every 2 minutes — add `ECO_SCHEDULER_AUTO_LOAD=1` before the command:
> ```bash
> ECO_SCHEDULER_AUTO_LOAD=1 bash scripts/install-launchagents.sh
> ```

---

## Step 6 — Verify the widget is alive

Tell SwiftBar where to find the plugin. In the menu bar, click the SwiftBar icon, then go to
**SwiftBar → Preferences → Plugin folder** and confirm it shows:

```text
~/Library/Application Support/SwiftBar/Plugins
```

The installer already wrote the symlink there:

```bash
ls -l ~/Library/Application\ Support/SwiftBar/Plugins/eco-commander.15s.sh
```

Expected:

```text
lrwxr-xr-x  ...  eco-commander.15s.sh ->
  $HOME/projects/eco-commander/src/bin/eco-commander.15s.sh
```

After SwiftBar reads the file (within 15 seconds) you should see a status circle appear in
the menu bar. The color depends on your quota state:

| Icon | Meaning |
|------|---------|
| 🟢 | All quotas and RAM healthy |
| 🟡 | A quota is above 80% or RAM below 4 GB |
| 🔴 | A quota above 95%, RAM below 1 GB, or poller data stale |

**Checkpoint:** click the icon. The dropdown should show **Token Quotas**, **System**, and
**Recipes** sections. If you see `Poller has not produced data yet`, wait 60 seconds and
check again — the poller runs on a 60-second interval.

---

## Step 7 — Run `eco status` in the terminal

The same data the widget shows is available at the command line:

```bash
eco status
```

**Expected output** (example — your numbers will differ):

```text
=== Eco Commander (CLI) ===
Status: 🟢  |  Profile: no-mcp
Quota worst: 12%  |  RAM: 48.3GB avail  |  Snapshot: 5m (fresh)
Runtime: OpenClaw=offline | Cortex=offline | n8n=offline

── 📊 Token Quotas ──
  Updated 14:02:11 (34s ago)

  Claude
    Session  ░░█████░░░░░  12%  resets in 2h 18m
    Weekly   ░░░░░░░░░░░░   2%  resets in 6d 11h

  Gemini
    flash      ░░░░░░░░░░░░   0%  ...
    flash_lite ░░░░░░░░░░░░   0%  ...
    pro        ░░░░░░░░░░░░   0%  ...

  Codex CLI
    Session  ░░░░░░░░░░░░   0%  ...
    Weekly   ░░░░░░░░░░░░   0%  ...

── 📡 System ──
  Profile: no-mcp
  RAM: 48.3 GB avail (free: 12.1 GB)
  Ollama: 0/4 loaded
  ...
```

You should now see live quota bars for Claude, Gemini, and Codex when the
poller has data. If the Gemini section shows `setup needed`, address that
before running Gemini-backed recipes.

---

## Step 8 — Verify Gemini CLI access

`eco do ask` is not zero-config for cloud prompts. For normal prompts it needs
an authenticated Gemini CLI, or a working `gem-smart` wrapper. `gem-smart` is
optional for `ask`; if it is absent, the recipe falls back to plain `gemini`.

Install and authenticate the Google Gemini CLI before continuing, following
the upstream Gemini CLI instructions. Then verify it directly:

```bash
gemini --version
gemini -p "Reply with: eco ready"
```

If you rely on `gem-smart`, verify the wrapper instead:

```bash
"${ECO_GEM_SMART_BIN:-$HOME/bin/gem-smart}" 3.5f \
  -p "Reply with: eco ready" \
  -y \
  --allowed-mcp-server-names none
```

**Checkpoint:** one of those commands should print a short answer and exit 0.

---

## Step 9 — Run your first recipe: `eco do ask`

`ask` is eco-commander's fastest cloud-backed recipe: one question, one answer.
It routes non-private prompts to Gemini by default, falling back to a local
Ollama model only if the question contains a privacy keyword.

Run:

```bash
eco do ask "What is a LaunchAgent on macOS?"
```

**Expected output** (abbreviated):

```text
A LaunchAgent is a macOS launchd job that runs in the context of a
logged-in user session. It is defined by a property list (.plist) file
stored in ~/Library/LaunchAgents/ and loaded automatically by launchd
when the user logs in. LaunchAgents are the standard way to run
user-space background daemons on macOS without root privileges...
```

The answer streams from Gemini. If `gem-smart` is available, the recipe invokes
`gem-smart 3.5f`; otherwise it invokes plain `gemini -p`.

**Checkpoint:** you should see a multi-sentence answer in plain prose, printed to stdout,
with no error messages.

> **What just happened?** `eco do ask` ran `src/recipes/ask.sh`, which found no privacy
> keywords in your question and forwarded it to Gemini through `gem-smart` or
> plain `gemini`. The recipe exited 0; its only output was to stdout. No files
> were written. See
> [../subsystems/recipes.md](../subsystems/recipes.md) for the full recipe contract.

---

## Step 10 — Inspect `eco list` and understand the recipe catalog

```bash
eco list
```

**Expected output** (abbreviated; the full list is generated from recipe
headers in `src/recipes/`):

```text
=== Eco Recipes ===
(call with: eco do <name>)

  ask                  Ask a question fast. Routes to Gemini (quick) by default. No ceremony.
  ...
  research             Research a topic with Gemini (1M context)
  scheduler-seed       Import mission YAML files into the scheduler queue
  snapshot             Capture ecosystem state into an immutable snapshot
  swarm                Dispatch N parallel Gemini agents on a task

=== Utility commands ===
  status               one-screen ecosystem state
  dashboard            open dashboard.html
  ...
```

Every line is a live recipe from `~/.eco/recipes/` (symlinked from `src/recipes/`). The
descriptions are read from `# DESC:` headers inside each script — what you see is exactly
what the widget menu also shows.

---

## Step 11 — Run `eco doctor` (the self-test)

```bash
eco doctor
```

**Expected output when everything is healthy:**

```text
=== eco doctor ===
  ℹ️  com.eco-commander.usage-poller not loaded (optional LaunchAgent)
  ℹ️  com.eco-commander.scheduler not loaded (optional LaunchAgent)
  ℹ️  com.eco-commander.swiftbar not loaded (optional LaunchAgent)
  ✅ eco CLI on PATH
  ✅ Python imports OK
  ℹ️  usage.json missing (usage poller optional)
  ✅ queue directory writable

All checks passed ✅
```

If you installed and loaded the optional LaunchAgents in Step 5, those lines
may show `✅ ... loaded`, and `usage.json` may show as fresh after the poller
has written its first sample. Missing optional LaunchAgents are informational,
not errors.

---

## Intentional failure and recovery: `eco: command not found`

This is the most common issue new users hit. Let's reproduce it and fix it so you have
hands-on experience before it catches you off-guard.

### Reproduce the failure

Open a new terminal window (one that has *not* sourced the updated `~/.zshrc`):

```bash
env -i HOME="$HOME" bash --noprofile --norc -c 'echo $PATH; eco status'
```

**Expected output:**

```text
/usr/bin:/bin:/usr/sbin:/sbin
bash: eco: command not found
```

`~/.eco/bin` is absent from this minimal PATH, so the shell cannot find `eco`.

### Why this happens

`make install` (called by `make bootstrap`) places the CLI at `~/.eco/bin/eco` via a
symlink. It deliberately does *not* modify your shell profile — that is the user's
responsibility. If you open a new shell before sourcing the updated profile, or if you
log in on a machine where the profile was never updated, the CLI is invisible.

### Fix it

In your real terminal (not the env-i shell above):

```bash
# Confirm the line is already there from Step 4:
grep 'eco/bin' ~/.zshrc

# If missing, add it:
echo 'export PATH="$HOME/.eco/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Then verify:

```bash
which eco
eco status
```

You should now see `eco` resolve to `~/.eco/bin/eco` and the status output appear.

### What if the PATH fix does not work?

Run the doctor to surface other causes:

```bash
eco doctor
```

And check the symlink itself:

```bash
ls -l ~/.eco/bin/eco
```

If the symlink points to a non-existent path (dangling symlink), re-run the installer:

```bash
# From your eco-commander checkout:
make uninstall && make install
```

> For a full symptom table covering stale widgets, missing `usage.json`, and Python
> import failures, see [../getting-started/troubleshooting.md](../getting-started/troubleshooting.md).

---

## Where to go next

You have completed the core journey. Here is how to go deeper:

| Topic | Document |
|-------|---------|
| All `eco` subcommands, recipes, and flags | [../getting-started/usage.md](../getting-started/usage.md) |
| Recipe authoring guide and contract | [../subsystems/recipes.md](../subsystems/recipes.md) |
| System component overview | [../architecture.md](../architecture.md) |
| Operational procedures (poller down, scheduler stuck, full reinstall) | [../operations/runbook.md](../operations/runbook.md) |
| Troubleshooting symptom table | [../getting-started/troubleshooting.md](../getting-started/troubleshooting.md) |
| Glossary of project terms | [../reference/glossary.md](../reference/glossary.md) |

The next natural step after this tutorial is to run `eco do snapshot` — which captures your
full AI ecosystem state into an immutable directory and updates the widget with fresh data —
then explore the output in `~/.eco/current/`.
