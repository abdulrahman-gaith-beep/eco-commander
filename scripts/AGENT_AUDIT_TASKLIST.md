# Scripts AI Agent Audit & Enhancement Tasklist

> Machine-readable task list for 5 specialized sub-agents to systematically
> audit, improve, and enhance the `scripts/` directory.
>
> **Priority levels:** P0 = blocking/correctness, P1 = high-value, P2 = nice-to-have

---

## 🏗️ Agent 1: ARCHITECT — Structure & Navigation

### Completed ✅
- [x] A01: Create `scripts/README.md` with full documentation
- [x] A02: Create `scripts/MANIFEST.yaml` — machine-readable index
- [x] A03: Move mission YAMLs out of `scripts/` (example now at `examples/missions/seed-jobs.example.yaml`)
- [x] A04: Create `scripts/lib/` directory with shared libraries
- [x] A05: Create `scripts/run-scheduler.sh` wrapper
- [x] A06: Verify Makefile paths after restructure
- [x] A07: Verify cross-references in INDEX.md, docs/INDEX.md
- [x] A09: Verify CI workflows don't reference moved files

### Remaining
- [ ] A10: **Create dependency graph** — mermaid diagram of script call relationships (P2)
  - Path: embed in `scripts/README.md` — DONE, already exists
- [ ] A11: **Add YAML front-matter headers** to each script for AI parsing (P2)
  - Format: `# @category`, `# @depends`, `# @calls`, `# @called-by`, `# @env-vars`
  - Target: all 20 scripts + 2 libraries
- [ ] A12: **Verify Makefile targets** still work after restructure — `make install`, `make lint` (P0)
- [ ] A13: **Audit `install.sh` for edge cases**: re-install over existing install, partial install recovery (P1)
- [ ] A14: **Add `scripts/` section** to root `INDEX.md` referencing MANIFEST.yaml (P1)

---

## 🔧 Agent 2: REFACTOR — DRY & Decomposition

### Completed ✅
- [x] R01: Create `scripts/lib/common.sh` with `validate_install_path`
- [x] R02: Extract `plist_label_matches` to `lib/common.sh`
- [x] R03–R06: Update all 4 install/uninstall scripts to source `lib/common.sh`
- [x] R07: Create `scripts/lib/snapshot-helpers.sh`
- [x] R08–R09: Extract helpers from `usage-snapshot.sh` + source them

### Remaining
- [ ] R10: **Extract `remove_link_if_ours`** to `lib/common.sh` (P2)
  - Currently in both `install.sh` and `uninstall.sh` — verify if identical
  - Path: `scripts/install.sh` (around line 65), `scripts/uninstall.sh` (around line 25)
- [ ] R11: **Extract `validate_plist`** to `lib/common.sh` (P2)
  - Currently only in `install-launchagents.sh` but useful for uninstall too
- [ ] R12: **Decompose `usage-snapshot.sh` Phase 2** — extract HTML template (P1)
  - The inline heredoc HTML (~300 lines) should become `templates/snapshot-card.html.tpl`
  - `usage-snapshot.sh` would use `sed`/`envsubst` to render it
  - Risk: HIGH — the HTML uses many bash variable interpolations
- [ ] R13: **Decompose `usage-snapshot.sh` Phase 3** — split data extraction from rendering (P2)
  - Extract jq data-pull block (lines ~75–165) into `lib/snapshot-data.sh`
  - Makes it testable independently
- [ ] R14: **Consolidate `humanize()` variants** — widget and snapshot use similar but not identical versions (P1)
  - Widget: 12-char bar, units through P (petabytes), different thresholds
  - Snapshot: 20-char bar, units through T (terabytes)
  - Decide: unify or explicitly document divergence
- [ ] R15: **Add `source_summary()` to `lib/snapshot-helpers.sh`** (P2)
  - Currently stays inline because it closes over `c_src`, `x_src`, `g_src`
  - Refactor to accept parameters instead

---

## 🔒 Agent 3: SECURITY — Hardening & Audit

### Completed ✅
- [x] S01: Fix hardcoded username in `log-rotate.conf` → template
- [x] S02: Update `install-log-rotation.sh` to render template
- [x] S03: Add scheduler log entries to `log-rotate.conf`

### Remaining
- [ ] S04: **Audit all scripts for unquoted variables** (P1)
  - Focus: `$ECO_HOME`, `$SWIFTBAR_PLUGIN_DIR`, `$HOME` in conditional contexts
  - Shellcheck may miss context-dependent cases
- [ ] S05: **Verify `toggle-precise.sh` AppleScript injection hardening** (P1)
  - The script constructs AppleScript strings from user input (tool names)
  - Check: are tool names validated before interpolation?
  - Path: `scripts/toggle-precise.sh` lines ~85–110
- [ ] S06: **Check `usage-snapshot.sh` HTML generation for XSS** (P1)
  - The HTML card interpolates plan names, model lists, and source labels
  - Are all user-controlled strings passed through `html_escape`?
  - Path: `scripts/usage-snapshot.sh` lines ~320–590
- [ ] S07: **Verify mission YAMLs don't contain secrets/tokens** (P0)
  - Scan `examples/missions/*.yaml` for API keys, tokens, credentials
- [ ] S08: **Audit plist templates for path traversal risks** (P2)
  - Check `__POLLER_PATH__`, `__SRC_DIR__`, `__ECO_HOME__` substitution
  - Ensure template vars can't escape XML context
- [ ] S09: **Ensure `umask 077`** is consistently applied in write-path scripts (P1)
  - install.sh sets `chmod 0700` on `$ECO_HOME` — verify other scripts don't loosen
- [ ] S10: **Verify `_safe_collect` pattern** from poller is honored in snapshot error paths (P2)
  - If `jq` fails on `usage.json`, does snapshot leave a corrupt card?
- [ ] S11: **Check `run-poller.sh` PYTHONPATH injection** (P2)
  - Does prepending to PYTHONPATH pollute child processes?
- [ ] S12: **Audit `release.sh` for tag collision / force-push risk** (P2)
  - Does it check if the tag already exists before creating?

---

## ✅ Agent 4: QUALITY — Testing & Validation

### Completed ✅
- [x] Q05: Create BATS test for `lib/common.sh` functions (13 tests)
- [x] Q06: Create BATS test for `lib/snapshot-helpers.sh` functions (35 tests)
- [x] Q08: Enhanced `lint.sh` with YAML + plist validation

### Remaining
- [ ] Q01: **Add `--dry-run` flag to `install.sh`** (P1)
  - Show what would be symlinked/created without actually doing it
  - Useful for CI validation and user previews
- [ ] Q02: **Add `--dry-run` flag to `uninstall.sh`** (P1)
  - Show what would be removed without actually doing it
- [ ] Q03: **Add `--dry-run` flag to `install-launchagents.sh`** (P2)
  - Show plist rendering + launchctl commands without executing
- [ ] Q07: **Verify `healthcheck.sh --json`** output is valid JSON (P2)
  - Run: `bash scripts/healthcheck.sh --json | python3 -m json.tool`
- [ ] Q09: **Test `validate-commit-message.sh` edge cases** (P2)
  - Empty subject, multi-line body, Unicode in type, scope with parens
- [ ] Q10: **Test install → uninstall → re-install idempotency** (P1)
  - Full lifecycle round-trip in BATS sandbox
- [ ] Q11: **Verify `release.sh` version validation** catches `v` prefix mistake (P2)
- [ ] Q12: **Add property-based tests** for `humanize()` (P2)
  - Invariant: output length ≤ 6 chars for any input
  - Invariant: humanize(0) = "0"
  - Invariant: humanize(x) ≈ humanize(x+1) for large x

---

## 📖 Agent 5: DOCUMENTATION — Indexing & Cross-References

### Completed ✅
- [x] D01: Write `scripts/README.md` content (full docs, env vars, call graph)
- [x] D02: Finalize `scripts/MANIFEST.yaml` (20 scripts, 2 libs, 1 config, 3 plist templates)
- [x] D08: Create `scripts/lib/README.md`

### Remaining
- [ ] D03: **Add inline documentation headers** to all scripts (P1)
  - Standardized format: purpose, usage, dependencies, env vars, exit codes
  - Target: `healthcheck.sh`, `toggle-precise.sh`, `release.sh` (least documented)
- [ ] D04: **Document environment variables** in a central table (P1)
  - scripts/README.md already has a table — verify completeness against actual usage
  - Run: `grep -rh 'ECO_[A-Z_]*' scripts/*.sh | sort -u`
- [ ] D05: **Document script call graph** (P1)
  - Verify the mermaid diagram in README.md matches actual `source`/`bash` calls
- [ ] D06: **Update `docs/` references** for new structure (P1)
  - Check: `docs/installation.md`, `docs/troubleshooting.md` for stale script paths
  - Note: some docs may have been moved/deleted by parallel conversations
- [ ] D07: **Document the plist template variable system** (P1)
  - `__POLLER_PATH__`, `__SRC_DIR__`, `__ECO_HOME__` substitution mechanism
  - How: add section to `scripts/launchagents/README.md` (create if missing)
- [ ] D09: **Add AI-navigation comments** to each script (P2)
  - Format: `# @category`, `# @depends`, `# @calls`, `# @called-by`, `# @env-vars`
  - Must match `MANIFEST.yaml` metadata
- [x] D10: **Sync `scripts/MANIFEST.yaml`** with any changes from other agents (P0)
  - MANIFEST.yaml updated to 20 scripts (added bootstrap.sh, setup-venv.sh, doctor.sh,
    run-alerts.sh, uninstall-log-rotation.sh, verify-manifest.sh). `scripts/verify-manifest.sh` passes with 0 issues.
- [ ] D11: **Create visual ecosystem diagram** (P2)
  - Mermaid showing: scripts → launchagents → poller/scheduler → usage.json → widget
- [ ] D12: **Update CHANGELOG.md** with restructuring entry (P1)

---

## Verification Checklist

After all agents complete, run:

```bash
# 1. Full shellcheck + YAML + plist validation
bash scripts/lint.sh

# 2. All BATS tests (including new library tests)
bats tests/bats/

# 3. Python unit tests
PYTHONPATH=src python3 -m unittest discover -s tests/python

# 4. E2E test suite
bash tests/e2e/run-e2e.sh

# 5. Healthcheck
ECO_HEALTHCHECK_MACOS_SURFACES=0 bash scripts/healthcheck.sh

# 6. MANIFEST validation
python3 -c "import yaml; d=yaml.safe_load(open('scripts/MANIFEST.yaml')); print(f'{len(d[\"scripts\"])} scripts indexed')"

# 7. Cross-reference integrity
grep -r 'scripts/' docs/ Makefile .github/ | grep -v '.git/' | grep -v MANIFEST
```

---

## Priority Summary

| Priority | Count | Examples |
|----------|-------|---------|
| **P0** | 2 | S07 (secrets scan), A12 (Makefile verify) — D10 (MANIFEST sync) ✅ done |
| **P1** | 16 | Q01/Q02 (dry-run), R12 (HTML decompose), S04-S06 (security audit) |
| **P2** | 13 | R10-R11 (more extractions), D09 (AI annotations), Q12 (property tests) |
