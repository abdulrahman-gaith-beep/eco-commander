> **Historical — superseded by [`usage-monitor.md`](./usage-monitor.md)**
>
> This document was the original integration plan written on 2026-05-09, before
> the usage monitor was implemented. It is retained as an audit artifact so the
> design decisions are traceable. Do not edit the body; see the current docs
> linked below for live information.
>
> Current references:
> - **User-facing docs:** [`usage-monitor.md`](./usage-monitor.md)
> - **Architectural decision:** [ADR 0004](../adr/0004-usage-monitor-python-carveout.md)
> - **Implementation:** `src/poller/` (Python) + `src/bin/eco-commander.15s.sh` (renderer)

---

# Usage Monitor — Integration Plan & Audit

**Status:** Historical — fully implemented as of 2026-05-09
**Created:** 2026-05-09
**Scope:** Integrate a live plan-quota mirror for Claude Code, Gemini CLI, and Codex CLI into `eco-commander`.

> **Note:** This document is a historical planning artifact. The usage monitor
> is now live and shipping. For current user-facing documentation, see
> [`usage-monitor.md`](./usage-monitor.md). For the architectural decision, see
> [ADR 0004](../adr/0004-usage-monitor-python-carveout.md). Historical file
> names below such as `usage-monitor.15s.sh` and `eco-commander.30s.sh` were
> superseded by the merged `eco-commander.15s.sh` widget.

---

## 1. Goal

Mirror the **plan-quota panels** that each CLI already shows in its own TUI, so that all three are visible at a glance from the macOS menu bar without opening any of them.

Reference panels (the three native UIs we are mirroring):

| # | Source | Fields |
|---|--------|--------|
| 1 | Claude Code `/usage` | Current 5h session %, weekly %, reset times |
| 2 | Gemini CLI model picker | Flash %, Flash Lite %, Pro %, per-tier reset clock |
| 3 | Codex CLI account menu (workspace account) | 5h %, Weekly %, weekly reset date |

Non-goal (explicit): web sessions on `claude.ai`, `chatgpt.com`, `gemini.google.com`. The user runs the CLIs almost exclusively; mirroring the web UIs is fragile (scraping) and out of scope.

---

## 2. Critical recon findings (2026-05-09)

These findings invalidate or constrain the obvious approaches:

### 2.1 Headless `/status` is blocked
`claude -p "/status" --output-format json` returns:
```json
{"result":"/status isn't available in this environment.", ...}
```
Slash commands are not exposed in non-interactive mode for **any** of the three CLIs. We cannot simply run `claude /status`, `gemini /quota`, `codex /status` from a cron and parse stdout. Every "headless slash command" plan is dead.

### 2.2 Codex stores usage in SQLite — `~/.codex/logs_2.sqlite`
Already a structured database (`logs_2.sqlite-shm`, `logs_2.sqlite-wal` indicate an active SQLite WAL connection — Codex likely keeps it open during sessions). This is the cleanest of the three sources if the schema contains rate-limit fields. **Action:** open it read-only and dump the schema before committing to a parser.

### 2.3 Gemini caches OAuth at `~/.gemini/oauth_creds.json`
The model-picker quota panel is rendered from an authenticated HTTP call. With the OAuth token in hand we can replay the same call from a poller. This is the same trust boundary as running `gemini` itself, so no new exposure.

### 2.4 Claude has `~/.claude/projects/**/*.jsonl` but no plan endpoint
Per-message `usage` fields are present, but **the published 5h-session and weekly caps are not knowable**. Anthropic does not document plan-specific token caps. Two paths:
- **(a) Reverse-engineer caps by observing reset events** — every time the in-app meter rolls over, snapshot the running token total → that token total ≈ the 100% mark. Self-calibrating, takes ~1 week to converge.
- **(b) API replay** — find the endpoint Claude Code's `/usage` slash command hits (run `claude` with `--debug api`, capture the request URL + auth header, replay from poller). Risk: undocumented endpoint, may change without notice.

Path (b) is preferred when it works; (a) is the durable fallback.

### 2.5 Existing OSS to study, not rewrite
- `Maciek-roboblog/Claude-Code-Usage-Monitor` — already solves the 5h block math from JSONL.
- `ryoppippi/ccusage` — npm package with daily/weekly rollups.
Both ship calibration tables for public Claude tiers. Read their plan-cap constants before guessing.

---

## 3. Audit of `eco-commander` integration points

### 3.1 What already exists (good — reuse, don't reinvent)
- **Repo→runtime symlink pattern** — `make install` (via `scripts/install.sh`) symlinks `src/{bin,recipes}` to `~/.eco/{bin,recipes}`. Edits to source go live immediately. New widget files belong in `src/bin/`.
- **SwiftBar plugin convention** — `eco-commander.15s.sh` is registered at `~/Library/Application Support/SwiftBar/Plugins/`. Filename suffix `.15s.sh` controls refresh cadence. The plugin reads `~/.eco/current/state.json` and renders.
- **Snapshot/state JSON pattern** — the existing widget never blocks on live calls; it reads a pre-computed `state.json`. Apply the same separation: a poller writes `~/.eco/current/usage.json`; the widget only reads it.
- **Recipe library** — `src/recipes/*.sh` for repeatable workflows. A `usage` recipe (`eco recipe usage`) belongs here for terminal use.
- **Bats test suite** — every recipe and the panel are tested. New code must come with bats coverage to land.
- **ADR culture** — `docs/adr/000{1,2,3}-*.md` records architecture decisions. Add ADR 0004 for "Usage monitor: poller + JSON file + SwiftBar render."

### 3.2 What is missing / blockers
- **No long-running background daemon today** — current widgets are stateless polls. A usage poller wants to run on a 60s timer. Options:
  - launchd `LaunchAgent` plist (preferred — no new processes when not firing, survives reboot)
  - A `usage-monitor.60s.sh` SwiftBar plugin that does both fetch + render (simpler, but one slow API call freezes the menu bar)
  - **Decision: launchd plist + separate render plugin.** Prevents UI stalls.
- **No secret/credential handling pattern** — eco-commander has not previously needed to read `~/.gemini/oauth_creds.json` or any token. Document in `SECURITY.md` and limit credential reads to the poller process only.
- **No Python in the stack today** — eco-commander is bash-only by ADR 0002. Either:
  - Stay bash + `jq` + `sqlite3` (Codex path is easy; Claude/Gemini parsing in bash is painful)
  - Allow a single Python module for the poller, kept narrow and out of `src/bin/` (e.g. `src/poller/usage.py`), with bash plugins continuing to render
  - **Recommendation: amend ADR 0002 with a narrow exception for the poller.** Document the carve-out.

### 3.3 Health check of eco-commander itself
- Repo last touched 2026-05-08 (`.git` mtime). Active.
- README and Makefile are current; `make install` / `make test` / `make lint` all wired.
- **Recommendation: run `make test && make lint` before adding any file** to confirm the green baseline still holds. Treat any pre-existing failures as a blocker, not noise we work around.

---

## 4. Revised architecture (post-audit)

```text
┌─ Poller (Python, launchd, 60s) ───────────────────────────────┐
│  src/poller/usage.py                                          │
│                                                               │
│  ┌─ claude.py ──────────────────────────────────────────────┐ │
│  │ Try (b): replay /usage API call (token from              │ │
│  │   ~/.claude/.credentials.json).                          │ │
│  │ Fallback (a): tail JSONL → tokens-since-last-reset →     │ │
│  │   % vs calibrated cap (cap learned from reset events).   │ │
│  └──────────────────────────────────────────────────────────┘ │
│  ┌─ gemini.py ──────────────────────────────────────────────┐ │
│  │ Replay model-picker quota call (OAuth from               │ │
│  │   ~/.gemini/oauth_creds.json). Returns Flash/Lite/Pro.   │ │
│  └──────────────────────────────────────────────────────────┘ │
│  ┌─ codex.py ───────────────────────────────────────────────┐ │
│  │ Read ~/.codex/logs_2.sqlite read-only (uri=...?mode=ro). │ │
│  │ Schema dump first. If quota fields absent, fall back to  │ │
│  │ counting messages in ~/.codex/sessions/ via JSONL.       │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                               │
│  Output (atomic write):                                       │
│    ~/.eco/current/usage.json                                  │
│    {                                                          │
│      "ts": 1715284800,                                        │
│      "claude":  {"session_pct":3, "session_resets_in":"2h18m",│
│                  "weekly_pct":53, "weekly_resets":"Mon 1AM",  │
│                  "source":"api|jsonl|estimate"},              │
│      "gemini":  {"flash":0, "flash_lite":13, "pro":0, ...},  │
│      "codex":   {"session_pct":99, "weekly_pct":68,           │
│                  "weekly_resets":"May 15"},                   │
│      "errors":  ["..."]   // surfaced in widget tooltip       │
│    }                                                          │
└──────────────────────┬────────────────────────────────────────┘
                       ▼
        ┌─ src/bin/eco-commander.15s.sh ─────────┐
        │ Pure bash + jq. Reads usage.json only. │
        │ Renders quota bars + reset times.      │
        │ Color thresholds: green<80, amber<95,  │
        │ red≥95, stale badge if >180s.          │
        └────────────────────────────────────────┘
```

**Why poller and renderer are split:**
- API calls take 200ms–2s. If the SwiftBar plugin did them inline, the menu bar would freeze on every refresh. Rendering must be a file read only.
- Poller can have a longer cadence (60s — quota changes slowly) than the widget (15s — feels live).
- The renderer keeps working even if the poller fails; it shows the last known state plus a stale-data badge.

---

## 5. Phased delivery

### Phase 0 — Recon (1 hour, no code)
1. `sqlite3 -readonly ~/.codex/logs_2.sqlite ".schema"` — confirm Codex has rate-limit fields.
2. `claude --debug api 2>&1 | grep -i usage` while opening `/usage` interactively — capture the endpoint URL.
3. Inspect `~/.gemini/oauth_creds.json` keys; identify token field. Strace or proxy `gemini` once to capture the model-quota endpoint.
4. Read source of `Claude-Code-Usage-Monitor` and `ccusage` for known plan caps.

**Gate:** if Codex SQLite has no quota fields AND Claude API endpoint cannot be captured, escalate before writing code — fall back to estimation-only mode and lower confidence.

### Phase 1 — MVP, behind a feature flag (1–2 days)
- ADR 0004 written and merged.
- `src/poller/usage.py` for the source(s) that worked in Phase 0.
- `src/bin/eco-commander.15s.sh` renderer.
- launchd plist under `scripts/launchagents/` registered by `scripts/install-launchagents.sh`.
- Bats tests covering: missing usage.json (graceful), stale usage.json (>5min — show warning badge), all-fields-present (renders), poller exits non-zero (logs but doesn't crash).
- Documented in `docs/usage-monitor.md` (user-facing) — separate from this planning doc.

### Phase 2 — Hardening (after a week of use)
- Calibrate Claude caps from observed resets; commit calibration table.
- Notification on >85% with <30m to reset (uses existing `eco-alerts.sh` pattern).
- Add weekly summary recipe: `eco recipe usage --week` — print last 7 days of peak %.

### Phase 3 — Native SwiftUI (only if MVP gets daily use for a month)
- `MenuBarExtra` app with sparklines and click-through detail window.
- Same `usage.json` data source (no poller changes).
- Lives in a new sibling repo; eco-commander stays bash-only.

---

## 6. Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Claude `/usage` endpoint changes/breaks | High over 12mo | Lose Claude % | Fallback to JSONL + calibrated estimate |
| Gemini OAuth refresh flow not handled by replay | Medium | Lose Gemini panel | Detect 401 → flag in usage.json → user re-auths via `gemini` |
| Codex SQLite schema lacks quota | Medium | Lose Codex precision | Fall back to message-count estimate vs published ChatGPT caps |
| Poller leaks credentials to logs | Low | High (token exposure) | Never log token contents; redact in error paths; review before merge |
| launchd plist runs even when laptop offline | Always | Wasted CPU + log spam | Check network before fetch; back off on N consecutive failures |
| Adds Python dependency to bash-only repo | Certain | Architectural drift | ADR 0004 documents the carve-out; keep Python contained to `src/poller/` |
| Mirrors data Anthropic/Google may not want mirrored | Low | ToS question | Read-only of own account state; no scraping of others — same posture as `ccusage` |

---

## 7. Open questions for the operator

1. **Python carve-out OK?** Or should Phase 1 stay bash-only and accept worse Claude/Gemini parsing?
2. **One usage JSON or three?** Single `usage.json` (proposed) vs. `usage-claude.json` / `usage-gemini.json` / `usage-codex.json` (more isolated; failed fetch on one tool can't corrupt others).
3. **Blink/notify thresholds** — 85%? 90%? And only when reset is imminent, or any time?
4. **Is this its own SwiftBar plugin (`usage-monitor.15s.sh`)** or a panel added to the existing `eco-commander.30s.sh`? Separate plugin is simpler; merged keeps the menu bar tidier.

---

## 8. Decision log

- **2026-05-09:** Confirmed all three CLIs (Claude/Gemini/Codex) expose plan-quota panels in their TUIs. Mirroring is feasible without scraping web dashboards.
- **2026-05-09:** Headless slash commands ruled out (`claude -p "/status"` returns "not available"). Pivot to API replay + log parsing per tool.
- **2026-05-09:** Codex SQLite (`~/.codex/logs_2.sqlite`) identified as the most-structured source — investigated first.
- **2026-05-09:** Decision deferred on Python carve-out vs bash-only — pending Phase 0 recon outcome.
- **2026-05-09:** All phases implemented and shipped. Document retained as historical reference.
