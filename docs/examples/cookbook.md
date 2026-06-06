# Eco-Commander How-To Cookbook

> **Diátaxis type:** How-to — task-oriented, goal-driven.
> Every recipe here is verified against `src/bin/eco`, `src/recipes/`, and
> `src/scheduler/cli.py`. Commands that reference `scripts/`, `src/`, or
> `examples/` assume your shell is in the eco-commander checkout root.

**Prerequisites for every scenario:** `eco doctor` passes its required checks.
Scenarios that inspect live usage data also need a fresh poller sample (green
or yellow icon in the menu bar). If that is not true, start with the
[Operational Runbook](../operations/runbook.md).

---

## Scenario 1 — Run a one-shot research query with Gemini

**Goal:** Produce a structured research brief on any topic and open it in your
default editor.

**Prerequisites:**
- Gemini CLI is authenticated (`gemini` runs without prompting for login), or
  `gem-smart` is available through PATH or `ECO_GEM_SMART_BIN`.

**Steps:**

```bash
# Option A: pass the topic inline
eco do research "vision 2030 procurement reforms 2026"

# Option B: interactive prompt (run with no args, then type when asked)
eco do research
# Research topic: vision 2030 procurement reforms 2026
```

The recipe:
1. Slugifies your topic to create a deterministic output path.
2. Calls `gem-smart 3.5f` with a structured six-part brief prompt when that
   wrapper is available; otherwise it uses plain `gemini -p`.
   *(Caveat: `gemini-3.5-flash` requires API Key authentication (`gem-use-apikey`) and will return a 404 error if used with OAuth (`gem-use-oauth`).)*
3. Writes the result to `~/Documents/research/<slug>/YYYY-MM-DD-<slug>.md`.
4. Prints a head preview to stdout and opens the file.

**Expected output:**

```text
=== Recipe: research ===
Topic: vision 2030 procurement reforms 2026
Output: ~/Documents/research/vision-2030-procurement-reforms-2026/2026-06-04-vision-2030-procurement-reforms-2026.md

=== Done ===
      87 ~/Documents/research/vision-2030-procurement-reforms-2026/2026-06-04-...md

# Vision 2030 Procurement Reforms 2026
...
```

**Notes:**
- Output is plain markdown with inline citations as `[url]`.
- When using `gem-smart`, the recipe passes `3.5f`, `-y`, and
  `--allowed-mcp-server-names none`. *(Caveat: `gemini-3.5-flash` requires API Key authentication (`gem-use-apikey`) and will return a 404 error if used with OAuth (`gem-use-oauth`).)*
- To run a private query without cloud calls, use `eco do ask` with a keyword
  like "internal" or "خاص"; that routes to the local Ollama model instead.

**Troubleshooting:**
- `gem-smart not found, and no 'gemini' CLI on PATH` → install/authenticate the
  Gemini CLI or set `ECO_GEM_SMART_BIN`.
- Empty output file → run `gemini --version` to confirm the CLI is working and the
  Gemini account is authenticated.

**Further reading:** [Recipes subsystem](../subsystems/recipes.md)

---

## Scenario 2 — Queue a scheduler job from a YAML file

**Goal:** Import one or more AI jobs into the persistent queue so the scheduler
dispatches them automatically within the next 120 seconds.

**Prerequisites:**
- Python 3 is on PATH with `src/scheduler/` importable (verified by `eco doctor`).
- `~/.eco/queue/` is writable.
- The scheduler LaunchAgent is loaded: `launchctl list | grep com.eco-commander.scheduler`.

**Steps:**

1. Write a job YAML file (example: `~/tmp/my-jobs.yaml`):

```yaml
version: 1
jobs:
  - id: "audit-snapshot-module-2026-06-04"
    project: "eco-commander"
    workdir: "."
    template: "raw_prompt"
    template_vars:
      prompt: "Audit src/recipes/snapshot.sh for edge cases and missing error handling."
    model_preference:
      - provider: claude
        model: claude-3-5-sonnet-20241022
        meter: claude.session
      - provider: gemini
        model: gemini-3.1-flash-lite-preview
        meter: gemini.tiers.flash_lite
      - provider: ollama
        model: qwen3:4b
        meter: ollama.local
    priority: P2
    timeout_s: 300
    retry:
      max: 2
      backoff_s: [60, 300]
```

2. Import the file:

```bash
eco scheduler add --file ~/tmp/my-jobs.yaml
```

3. Confirm the job is in the queue:

```bash
eco scheduler status
```

4. Optionally trigger one tick immediately rather than waiting:

```bash
eco scheduler run-once
```

**Expected output (add):**

```text
✅ added 1 new job(s); 0 skipped (id already in queue)
```

**Expected output (status):**

```text
━━━ eco-scheduler status @ 2026-06-04T09:15:00 ━━━
queue: ~/.eco/queue/jobs.yaml

Jobs (1 total):
  pending            1

Meters:
  ✅ claude.session               use_it_or_lose_it
  ✅ gemini.tiers.flash           use_it_or_lose_it
  ...

Next pending jobs (top 5):
  [P2] audit-snapshot-module-2026-06-04  -> claude/gemini/ollama  (earliest now)
```

**Notes:**
- Job `id` must match `[A-Za-z0-9._-]+` and be unique. Re-adding the same id
  is silently skipped.
- The `model_preference` ladder is walked top-to-bottom; the first provider
  whose meter shows capacity fires the job.
- To import many YAML files from a directory at once, use `eco scheduler seed --dir <path>`.

**Troubleshooting:**
- `error: <file>: YAML must contain a list of jobs or a {jobs: [...]} root` → ensure the root key is `jobs:`.
- Jobs stay `gated_by_quota` → all meters are blocked. Run `eco scheduler status --json`
  to see each meter's `seconds_until_available`.

**Further reading:** [Scheduler subsystem](../subsystems/scheduler.md)

---

## Scenario 3 — Debug a stale usage meter

**Goal:** Diagnose and recover from a "STALE" badge in the widget or a
`⚠ usage.json stale` warning from `eco status`.

**Prerequisites:**
- Access to `~/.eco/logs/usage-poller.err.log` (do not paste raw log into agents).

**Steps:**

1. Check the widget's current reading:

```bash
eco status
```

Look for lines like:
```text
Quota worst: 42%  |  RAM: 12.3GB avail  |  Snapshot: 2h (fresh)
⚠ STALE — poller data is 5m old
```

A "STALE" marker means `usage.json` has not been refreshed in more than 180 seconds.

2. Verify the LaunchAgent is loaded and has not exited non-zero:

```bash
launchctl list | grep com.eco-commander.usage-poller
```

Output columns are `PID`, `LastExitStatus`, `Label`. `LastExitStatus` of `0`
is healthy. A `-` PID means not currently running (normal between 60 s
intervals). A non-zero exit code indicates a crash.

3. Run the poller manually to see live error output:

```bash
python3 src/poller/main.py
```

4. Check `usage.json` freshness:

```bash
stat -f "%Sm %N" ~/.eco/current/usage.json
```

5. If the LaunchAgent is not loaded, reinstall it:

```bash
bash scripts/install-launchagents.sh
```

6. If the poller errors with `OAuth expired`, re-authenticate Gemini:

```bash
# Run Gemini CLI once interactively to refresh the OAuth token
gemini
# Then force a manual poll
python3 src/poller/main.py
```

**Expected output after recovery:**

```bash
eco status
# Quota worst: 42%  |  RAM: 12.3GB avail  |  Snapshot: 2h (fresh)
# (no STALE marker)
```

**Notes:**
- The `eco-commander.15s.sh --cli` script (called by `eco status`) computes
  staleness as `now - usage.json mtime > 180s`. A single successful poll clears it.
- Do not share raw poller logs with external agents — provide a short redacted
  summary instead (as noted in the runbook boundary).

**Troubleshooting:**
- Poller crash-loops (rapidly incrementing PID in `launchctl list`) →
  follow [Runbook § 10](../operations/runbook.md).
- `jq required` warning in `eco status` → `brew install jq`.

**Further reading:** [Operational Runbook](../operations/runbook.md) ·
[Widget Health](../subsystems/widget-health.md)

---

## Scenario 4 — Rotate CLI accounts safely

**Goal:** Switch the active Gemini account (or Codex account) to a previously
registered snapshot without re-running OAuth.

**Prerequisites:**
- At least two account snapshots registered for the target tool
  (`eco account-swap list` shows multiple entries).
- No `claude` or `codex` CLI process running when swapping those tools
  (Gemini is swap-safe at any time).

**Steps:**

1. List registered accounts and see which is currently active:

```bash
eco account-swap list
```

Expected:
```text
gemini:
  * gemini-primary (active)
    gemini-secondary
    gemini-tertiary
codex:
  * codex-primary (active)
    codex-secondary
```

2. Register the current live auth as a new named snapshot (first time only):

```bash
# Capture current Gemini credentials as "gemini-primary"
eco account-swap gemini --register gemini-primary

# Capture current Codex credentials as "codex-primary"
eco account-swap codex --register codex-primary

# Claude requires explicit Keychain consent
eco account-swap claude --register claude-primary --allow-keychain-prompt
```

3. Swap to a different account:

```bash
# Switch Gemini to gemini-secondary
eco account-swap gemini gemini-secondary

# Switch Codex to the "codex-secondary" account (quit Codex CLI first)
eco account-swap codex codex-secondary
```

4. Confirm the switch:

```bash
eco account-swap list
# gemini:
#     gemini-primary
#   * gemini-secondary (active)
```

**Expected output (swap):**

```text
gemini now using account: gemini-secondary (was: gemini-primary)
```

A macOS notification also fires if `osascript` is available.

**Notes:**
- Credential snapshots are stored under `~/.eco/auth-snapshots/<tool>/<slug>/`
  with mode `0700` (directory) and `0600` (files).
- The recipe auto-saves the previously active account before restoring the
  target, so a swap is always reversible.
- Claude Keychain restore via the real `security` CLI is intentionally
  disabled for safety (it would expose the secret in process arguments).
  If you need to switch Claude accounts, re-authenticate manually with
  `claude login` after the swap.
- Slugs must match `[A-Za-z0-9_-]+`.

**Troubleshooting:**
- `refusing to swap: a 'codex' process is running` → quit the Codex CLI and retry.
- `no snapshot for gemini/gemini-tertiary at ...` → the slug is not yet registered. Run `--register` first.
- `snapshot directory contains unexpected files; refusing to overwrite` → pass `--force` to re-register.

**Further reading:** [Recipes subsystem](../subsystems/recipes.md) ·
[Operational Runbook § 7](../operations/runbook.md)

---

## Scenario 5 — Capture and share a usage snapshot

**Goal:** Take a full eco-commander ecosystem snapshot from the selected Gemini prompt
library and produce a shareable `state.json` + `dashboard.html` that reflects
current ecosystem health.

**Prerequisites:**
- Gemini CLI authenticated, or `gem-smart` available through PATH or
  `ECO_GEM_SMART_BIN`.
- A snapshot prompt library is available. A fresh checkout includes the public
  `examples/snapshot-prompts/` library; private canonical libraries can be
  supplied through `$ECO_AUDIT_ROOT/prompts` or
  `~/.eco/ecosystem-audit/prompts`.
- `~/.eco/` exists from install or prior runtime setup; the snapshot recipe
  creates or repoints the `~/.eco/current` symlink after a successful run.
- No concurrent snapshot running (`~/.eco/.snapshot.lock` must not exist from a
  live run).

**Steps:**

1. Run the snapshot recipe:

```bash
eco do snapshot
```

The recipe runs one parallel Gemini layer per prompt in the selected prompt
library. Canonical prompt libraries use the seven eco-commander audit layers
(`GA-hardware-llm`, `GB-ai-clients`, `GC-mcp`, `GD-hooks-plugins`,
`GE-agents-memory`, `GF-toolkit-projects-external`, `GG-wiring-behavior`);
the shipped public example library uses generic example layer names. The
recipe prefers `gem-smart 3.5f` and falls back to plain `gemini -p` when the
configured/default wrapper path does not resolve, then assembles `state.json`,
`map.md`, and `dashboard.html` and atomically creates or repoints the
`~/.eco/current` symlink.
*(Caveat: `gemini-3.5-flash` requires API Key authentication (`gem-use-apikey`) and will return a 404 error if used with OAuth (`gem-use-oauth`).)*

**Expected output with the canonical seven-prompt library:**

```text
=== Eco snapshot: 2026-06-04T09-30Z ===
Workspace: ~/.eco/snapshots/2026-06-04T09-30Z

  ✓ GA-hardware-llm
  ✓ GB-ai-clients
  ✓ GC-mcp
  ✓ GD-hooks-plugins
  ✓ GE-agents-memory
  ✓ GF-toolkit-projects-external
  ✓ GG-wiring-behavior

=== Assembling current snapshot ===
Current snapshot now points to:
~/.eco/snapshots/2026-06-04T09-30Z

Open dashboard:
  ~/.eco/current/dashboard.html
```

2. Open the dashboard:

```bash
eco dashboard
```

3. Inspect the machine-readable state for scripting or sharing with an agent:

```bash
cat ~/.eco/current/state.json | python3 -m json.tool | head -40
```

4. Save a PNG + clipboard snapshot for sharing:

```bash
bash scripts/usage-snapshot.sh
```

PNG files are written to `~/.eco/usage-snapshots/` by default. Set
`ECO_SNAPSHOT_DIR` to redirect to a different location.

**Notes:**
- Each layer has a 180-second timeout (`GEMINI_LAYER_TIMEOUT_SEC`). Timed-out
  or non-zero layers surface as a snapshot failure, leave logs in the
  timestamped workspace, and prevent `current` from being repointed.
- The lock file at `~/.eco/.snapshot.lock` prevents concurrent runs. If a
  previous run was killed, the lock may be stale — the recipe detects a dead PID
  and cleans it up automatically.
- The assembled snapshot is immutable: the timestamped directory under
  `~/.eco/snapshots/` is never modified after creation (only the `current`
  symlink is updated).

**Troubleshooting:**
- `Snapshot already running (pid N)` → wait for the active run to finish, or
  verify the PID is actually dead before removing the lock.
- `Prompt library not found` → provide `$ECO_AUDIT_ROOT/prompts`, populate
  `~/.eco/ecosystem-audit/prompts`, or run from a checkout that includes
  `examples/snapshot-prompts/`.
- Layer outputs are empty → run `gemini --version` to confirm CLI health; check
  `~/.eco/snapshots/<ts>/layers/<layer>.log` for error details.

**Further reading:** [Operational Runbook](../operations/runbook.md)

---

## Scenario 6 — Add a new recipe to the catalog

**Goal:** Write a new recipe that appears in `eco list`, is runnable via
`eco do <name>`, and passes the recipe contract requirements from
`docs/subsystems/recipes.md`.

**Prerequisites:**
- `src/recipes/` directory is present (checked by `eco doctor`).
- `~/.eco/recipes/` is a real directory containing per-file symlinks back to
  installed `src/recipes/*.sh` files.

**Steps:**

1. Create your recipe file in `src/recipes/`:

```bash
cat > src/recipes/my-recipe.sh << 'EOF'
#!/usr/bin/env bash
# DESC: Brief one-line description shown in eco list
# INPUTS: <required-arg> [optional-arg]
# OUTPUT: ~/Documents/my-recipe/<date>-output.md
# USES: Gemini Flash Lite
# HUMAN: review the output file before sharing
set -eu

ARG="${1:-}"
if [ -z "$ARG" ]; then
  echo "Usage: eco do my-recipe <arg>" >&2
  exit 1
fi

# Your logic here
echo "Running my-recipe with: $ARG"
EOF
chmod +x src/recipes/my-recipe.sh
```

2. Refresh the installed per-file symlink:

```bash
make install
```

3. Verify it appears in the catalog:

```bash
eco list
# ...
#   my-recipe            Brief one-line description shown in eco list
#                          inputs: <required-arg> [optional-arg]
```

4. Test it:

```bash
eco do my-recipe hello-world
```

**Recipe contract checklist:**

| Requirement | How to satisfy |
|-------------|---------------|
| Shebang + `set -eu` | First two lines of the file |
| `# DESC:` header | Required — drives `eco list` and widget menus |
| `# INPUTS:` header | Recommended — documents the argument spec |
| `# OUTPUT:` header | Recommended — tells operators where to look |
| `# USES:` header | Recommended — model or tool used |
| `# HUMAN:` header | Recommended — what the operator reviews |
| Validate args, emit `usage:` on misuse | Show usage to stderr and exit non-zero |
| Exit 0 on success | Required |
| No secrets on disk or in logs | Use env vars for any credentials |
| Timeout within 5 minutes | Use `timeout 300 <cmd>` or `GEMINI_LAYER_TIMEOUT_SEC` |

**Notes:**
- `eco list` discovers recipes by scanning `*.sh` files in `$HOME/.eco/recipes/`
  for a `# DESC:` comment. Only scripts with that header appear.
- Files named `_lib.sh` are skipped by convention.
- After adding a recipe, rerun `make install` so `~/.eco/recipes/` gets the new
  per-file symlink.

**Further reading:** [Recipes subsystem](../subsystems/recipes.md)

---

## Scenario 7 — Inspect what the widget is showing via `--cli`

**Goal:** Read the widget's full rendered output in a terminal session (no
SwiftBar required) to verify quota levels, system status, and active alerts.

**Prerequisites:**
- `eco` is on PATH (`eco doctor` passes).
- `jq` is installed (`brew install jq` if missing).

**Steps:**

1. Print the full widget panel to stdout:

```bash
eco status
```

This calls `~/.eco/bin/eco-commander.15s.sh --cli` internally.

**Expected output structure:**

```text
=== Eco Commander (CLI) ===
Status: 🟢  |  Profile: no-mcp
Quota worst: 23%  |  RAM: 18.4GB avail  |  Snapshot: 47m (fresh)
Runtime: OpenClaw=offline | Cortex=offline | n8n=offline

── 📊 Token Quotas ──

  Updated 09:14:52 (37s ago)

  Claude · Unknown
    Session  ████████░░░░  23%  resets 4h 12m
    ---- in 142K · out 38K · cache+ 12K · cache↻ 208K · billable: 38K
    Weekly   ██░░░░░░░░░░   8%  resets 5d 2h

  Gemini · Unknown
    flash      ░░░░░░░░░░░░   0%  —
    flash_lite ░░░░░░░░░░░░   0%  —
    pro        ░░░░░░░░░░░░   0%  —

  Codex CLI · Unknown · active: codex-primary
    Session  ░░░░░░░░░░░░   0%  resets 23h 44m
    Weekly   ░░░░░░░░░░░░   2%  resets 5d 2h

── 📡 System ──
  Profile: no-mcp
  RAM: 18.4 GB avail (free: 4.2 GB)
  Snapshot: 47m (fresh)
  Snap ID: 2026-06-04T09-30Z
  ...

── ⚠ 2 Alerts ──
  [MED] GA-hardware-llm:14: error detected in layer output — evidence
  ...
```

2. Get a machine-readable JSON dump for scripting:

```bash
eco scheduler status --json
```

3. Check a specific field from `usage.json` directly:

```bash
# Claude session usage percentage
jq '.claude.session.pct' ~/.eco/current/usage.json

# All Gemini tier percentages
jq '.gemini.tiers' ~/.eco/current/usage.json

# Full worst-case quota for routing decisions
jq '[.claude.session.pct, .claude.weekly.pct, .codex.session.pct, .gemini.tiers.flash.pct] | max' \
  ~/.eco/current/usage.json
```

4. Verify the widget renders without errors (useful after config changes):

```bash
~/.eco/bin/eco-commander.15s.sh --cli 2>&1 | head -5
# Expected first line: === Eco Commander (CLI) ===
```

**Notes:**
- The `--cli` flag switches rendering from SwiftBar pipe-separated format to
  plain indented text. The same data is used for both.
- A `⚠ STALE` marker on the "Updated" line means the poller has not written
  fresh data in more than 180 seconds. Follow Scenario 3 to resolve.
- The icon logic (`🟢`/`🟡`/`🔴`) aggregates: quota thresholds (80%/95%),
  RAM available (<4 GB = yellow, <1 GB = red), snapshot age (>24 h = yellow,
  >72 h = red), and poller staleness.

**Troubleshooting:**
- `jq required. Install: brew install jq` in the output → install jq.
- `Poller has not produced data yet` → run `python3 src/poller/main.py`
  once to seed `usage.json`.
- `usage.json is corrupt` → delete `~/.eco/current/usage.json` and re-run the poller.

**Further reading:** [Widget Health](../subsystems/widget-health.md) ·
[Operational Runbook](../operations/runbook.md)

---

## Scenario 8 — Seed the scheduler queue from a missions directory

**Goal:** Import a whole directory of YAML mission files into the scheduler
queue in one command — useful when setting up a new sprint of background jobs.

**Prerequisites:**
- A directory of `*.yaml` or `*.yml` mission files with the standard schema.
- Python 3 with the `scheduler` module importable (verified by `eco doctor`).

**Steps:**

1. Organize your mission files in a directory:

```text
examples/missions/
  audit-snapshot.yaml
  research-v2030.yaml
  codegen-widget-test.yaml
```

Each file must have a `jobs:` root key (or be a bare list):

```yaml
# examples/missions/research-v2030.yaml
version: 1
jobs:
  - id: "research-v2030-procurement-2026-06-04"
    project: "eco-commander"
    workdir: "."
    template: "research"
    template_vars:
      prompt: "Research Vision 2030 procurement reforms for 2026."
    model_preference:
      - provider: gemini
        model: gemini-3.1-flash-lite-preview
        meter: gemini.tiers.flash_lite
    priority: P3
    timeout_s: 600
```

2. Seed the entire directory:

```bash
eco scheduler seed --dir examples/missions/
```

**Expected output:**

```text
  ✅ audit-snapshot.yaml: 1 added, 0 skipped
  ✅ research-v2030.yaml: 1 added, 0 skipped
  ✅ codegen-widget-test.yaml: 1 added, 0 skipped

Seed complete: 3 job(s) added, 0 skipped (already in queue), 0 invalid
```

3. Verify the queue:

```bash
eco scheduler status
```

4. Inspect the tail of the most recently completed job:

```bash
eco scheduler tail
```

**Notes:**
- `seed` and `add` both skip jobs whose `id` already exists in the queue —
  re-running is safe.
- Files that fail to parse are reported with a warning but do not abort the
  seed run.
- The `scheduler-seed` recipe (`eco do scheduler-seed <dir>`) is a thin
  wrapper around this same `eco scheduler seed --dir` call.

**Troubleshooting:**
- `no .yaml/.yml files found in <dir>` → check the directory path and file extensions.
- `<file>: bad job entry 0 ('id')` → every job entry must have an `id` field.
- Jobs remain `gated_by_quota` after seeding → all meters for that job are blocked.
  Run `eco scheduler status --json | python3 -m json.tool` to see per-meter
  `seconds_until_available`.

**Further reading:** [Scheduler subsystem](../subsystems/scheduler.md) ·
[Recipes subsystem](../subsystems/recipes.md)

---

## Scenario 9 — Cancel a queued job and drain the rest

**Goal:** Remove a job you queued by mistake, then run the remaining queue to
completion in the foreground instead of waiting for the 120-second
LaunchAgent ticks.

**Prerequisites:**
- At least one job in the queue (`eco scheduler status` shows a non-empty queue).
- Python 3 with the `scheduler` module importable (verified by `eco doctor`).

**Steps:**

1. Find the id of the job to remove:

```bash
eco scheduler status
```

2. Cancel a `pending` or `gated_by_quota` job by id:

```bash
eco scheduler cancel audit-snapshot-module-2026-06-04
```

**Expected output:**

```text
✅ cancelled job 'audit-snapshot-module-2026-06-04' (was: pending)
```

3. A job that has already advanced past `pending`/`gated_by_quota` (for example,
   one that is `running`, `completed`, or `failed`) is protected. Force it only
   if you are sure:

```bash
eco scheduler cancel <job-id> --force
```

Without `--force`, the command refuses and exits non-zero:

```text
error: job '<job-id>' has status 'running' — use --force to cancel anyway
```

4. Drain the remaining ready jobs immediately rather than waiting for the
   scheduler LaunchAgent. `drain` runs one job per tick until the queue is idle,
   all remaining jobs are gated by quota, or it hits `--max-ticks` (default 10):

```bash
eco scheduler drain
```

To pace ticks and cap their count:

```bash
eco scheduler drain --max-ticks 20 --interval-s 5
```

**Expected output (abbreviated):**

```text
--- tick 1/10 ---
{
  "fired": 1,
  ...
}
queue idle; exit
```

**Notes:**
- `cancel` sets the job's status to `cancelled` in `~/.eco/queue/jobs.yaml`; it
  does not delete the row, so the audit trail is preserved.
- `drain` stops early and exits non-zero if any attempt fails — inspect the
  printed JSON summary before retrying.
- `drain` fires at most one job per tick (`max_jobs_per_tick=1`), so a long
  queue may need a higher `--max-ticks`.

**Troubleshooting:**
- `error: job '<id>' not found in queue` → re-check the id with `eco scheduler status`.
- `all remaining jobs gated; exit` → every remaining job is `gated_by_quota`;
  run `eco scheduler status --json` to see each meter's `seconds_until_available`.

**Further reading:** [Scheduler subsystem](../subsystems/scheduler.md) ·
[Operational Runbook § 3](../operations/runbook.md)

---

## Scenario 10 — Monitor system health with the hygiene watcher

**Goal:** Run the background hygiene watcher that monitors RAM, swap pressure,
MCP connection count, and stuck Gemini CLI processes, and read its current
state.

**Prerequisites:**
- `eco` is on PATH (`eco doctor` passes).
- macOS (the watcher uses `vm_stat`, `sysctl`, `pgrep`, and `launchctl`).

**Steps:**

1. Take a single one-shot snapshot without installing any daemon:

```bash
eco hygiene snapshot
```

This prints one state line and writes it to `~/.eco/state.json` under the
`hygiene` key.

2. Install and start the watcher as a managed LaunchAgent (recommended for
   continuous monitoring):

```bash
eco hygiene watch
```

3. Check whether the daemon is running and when it last emitted an event:

```bash
eco hygiene status
```

4. Follow the live event stream (or only high-severity events):

```bash
eco hygiene tail          # all events
eco hygiene tail-high     # high-severity events only
```

5. Stop the watcher when you no longer need it:

```bash
eco hygiene stop
```

**Notes:**
- The watcher replaces session-scoped monitor loops with a proper
  LaunchAgent-managed daemon (label `com.eco-commander.hygiene`).
- Thresholds are configurable via environment variables (for example
  `ECO_HYGIENE_RED_MEM_GB`, `ECO_HYGIENE_YEL_SWAP_MB`); see the script header in
  `src/recipes/hygiene.sh`.
- Event logs live under `~/.eco/hygiene/` and are private operator data — do not
  paste raw logs into agents.

**Troubleshooting:**
- `daemon not running` from `eco hygiene status` → start it with
  `eco hygiene watch`.
- No notifications appear → notifications require `osascript`; the daemon still
  logs events to `~/.eco/hygiene/events.log` regardless.

**Further reading:** [Usage subcommands](../getting-started/usage.md#hygiene-subcommands) ·
[Operational Runbook](../operations/runbook.md)
