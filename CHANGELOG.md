# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `src/recipes/n8n-start.sh` — fallback recipe to start n8n via Docker
  Compose or `npx` when the daemon is missing.
- `src/recipes/dashboard-refresh.sh` — automated hydration script that
  injects live ecosystem metrics into the dashboard template.
- `src/bin/eco-alerts.sh` — alert-doctor that audits every snapshot finding
  and prints fix commands outside SwiftBar.
- `docs/subsystems/widget-health.md` — health playbook for alert truth, fix tiers, Ollama
  count semantics, repo health, and a bounded 24/7 manager design.
- `eco-alerts.sh repo-health` — checks docs, changelog, runtime links, expected
  tools, current state, widget renderability, and lint when available.
- `eco-alerts.sh debug-ollama` and a widget action to explain loaded vs
  installed Ollama model counts with raw local evidence.
- Alert workflow documented in `docs/getting-started/usage.md` (verified-finding model with
  per-alert "Open evidence" / "Fix:" / "Alert doctor" actions).
- Gold-standard repo scaffold: `README`, `LICENSE`, `CHANGELOG`, `CONTRIBUTING`,
  `CODE_OF_CONDUCT`, `SECURITY`, `SUPPORT`, `AUTHORS`, `Makefile`.
- `docs/` tree with architecture, installation, usage, recipes, snapshots,
  testing, troubleshooting guides.
- ADR log under `docs/adr/`.
- GitHub workflows for CI (shellcheck + bats), issue and PR templates,
  CODEOWNERS, dependabot config.
- `scripts/install.sh` and `scripts/uninstall.sh` for symlink-based deployment
  into `~/.eco/`.

### Changed
- Snapshot probe semantics: n8n-offline now classified as `info`, not `high`,
  reflecting on-demand-service architecture (audit finding D2).
- SwiftBar title now shows Ollama as `loaded/installed` instead of a bare
  loaded count, and the widget adds Homebrew paths without hiding test stubs.
- Snapshot-generated issues now live on their source layer, with
  `Linf_wiring.issues` retained as a deprecated compatibility aggregate.
- Dashboard probe (`GG-wiring-behavior:27`) tightened to compute explicit
  numeric diffs against live JSON instead of regex-flagging static counts.
- Source-of-truth moved from runtime state to the repository `src/` tree.
  `~/.eco/` is now a runtime directory of symlinks + state.

### Fixed
- Snapshot layer failures: `snapshot.sh` now uses a bounded per-layer timeout
  (`GEMINI_LAYER_TIMEOUT_SEC`, default 180s), captures stderr, reports rc=124
  timeouts, and keeps the `gem-smart` to plain `gemini` fallback path.
- Optional memory-router alert handling now treats cross-project dependency
  fixes as delegated work unless direct complex fixes are explicitly enabled.

## [0.2.0] - 2026-04-18

### Fixed
- BUG-R1: `eco status` invoked the non-existent `eco-commander.1s.sh`. Fixed
  to call `eco-commander.30s.sh`.

### Added
- End-to-end Bats test suite under `tests/`.

## [0.1.0] - 2026-04-17

### Added
- Initial CLI router (`eco`).
- SwiftBar status panel (`eco-commander.30s.sh`).
- Recipes: ask, note, research, swarm, snapshot, arabic-proof, dashboard.
- Snapshot system under `~/.eco/snapshots/`.
