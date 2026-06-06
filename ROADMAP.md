# Roadmap

> Last updated: 2026-06-06

This roadmap reflects the maintainer's current priorities. Items may change
based on user feedback, contributor experience, and the tool ecosystem.
Contributors should open an issue first to agree scope and acceptance criteria.

---

## Now

Target: v0.3.0 public-release polish.

- [ ] The current `[Unreleased]` changelog section is released as v0.3.0.
- [ ] Repository hardening is enforced and documented for contributors:
      `pyproject.toml`, Ruff, coverage gates, dependency review, SBOM, and
      release provenance all have visible checks or verification steps.
- [ ] The poller and scheduler emit structured JSON logs with stable fields
      for subsystem, event, provider or job id, duration, outcome, and error
      class.
- [ ] The CLI reference under `docs/api/` is verifiably in sync with
      `src/bin/eco` and `src/scheduler/cli.py`.
- [ ] The dev container is a supported contributor path with documented
      readiness checks for GitHub Codespaces and local Dev Containers.

## Next

Target: v0.4.0 adoption and integration work.

- [ ] The Claude scheduler adapter has parity tests and documented behavior
      alongside the Gemini, Codex, and Ollama adapters.
- [ ] Webhook notifications can deliver scheduler or poller events to an
      opt-in Slack, Discord, or ntfy.sh target.
- [ ] `eco dashboard` serves a local HTML/JS dashboard from runtime state
      instead of only opening the static snapshot file.
- [ ] A Homebrew install path exists for one-line installation:
      `brew install eco-commander`.
- [ ] Release provenance is documented and verifiable against SLSA Level 2
      expectations.

## Later

- [ ] Multi-machine support keeps state synchronized across macOS devices
      without breaking snapshot immutability.
- [ ] Declarative recipe plugins let contributors add YAML-defined recipes
      without editing the CLI router.
- [ ] Rate-limit prediction warns before likely 429s by using historical
      usage patterns.
- [ ] macOS Shortcuts integration exposes approved recipes as Shortcuts
      actions.
- [ ] Linux support provides systemd units in place of launchd for non-widget
      use.
- [ ] TUI mode provides a keyboard-first terminal interface via `textual` or
      `blessed`.
- [ ] Agent-to-agent protocol support lets eco-commander mediate handoffs
      between AI agents.
- [ ] Cost tracking aggregates actual provider API spend when source data is
      available.

---

## Completed

### v0.2.0

- [x] CLI router (`eco`)
- [x] SwiftBar status panel
- [x] Recipe library (ask, note, research, swarm, snapshot, arabic-proof,
      dashboard)
- [x] Immutable snapshot system
- [x] End-to-end Bats test suite
- [x] Usage monitor poller (Claude, Gemini, Codex)
- [x] Job scheduler with adapter pattern
- [x] Bats, Python unit, and E2E test suites
- [x] Alert system with `eco-alerts.sh`
- [x] Gold-standard repository scaffold
