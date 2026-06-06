# TODO

Contributor-facing tasks derived from [ROADMAP.md](./ROADMAP.md) and the
current codebase. Before starting, open an issue to confirm scope and
acceptance criteria, then follow [CONTRIBUTING.md](./CONTRIBUTING.md).

## CLI

- [ ] Add a missing-file check to `eco dashboard` so it prints a clear error
      when `~/.eco/current/dashboard.html` is absent. (good first issue)
- [ ] Add a small test that `eco help` and `eco list` continue to expose the
      commands documented in `docs/api/cli-reference.md`.
- [ ] Define the user-facing behavior for the planned local `eco dashboard`
      server, including port selection, browser opening, and shutdown.
- [ ] Keep the current static-dashboard behavior documented until the local
      HTML/JS dashboard ships. (good first issue)

## Scheduler

- [ ] Add Claude adapter coverage to `tests/python/test_adapters.py` for
      prompt rendering, dry-run mode, empty prompts, unsafe job ids, invalid
      timeouts, and error-kind heuristics.
- [ ] Add structured JSON logging for scheduler ticks and adapter fire results
      without logging prompt bodies or credentials.
- [ ] Add a fixture test for `eco scheduler status --json` that covers
      `pending`, `gated_by_quota`, `running`, `completed`, and `cancelled`.
- [ ] Draft the webhook adapter contract before implementing Slack, Discord,
      or ntfy.sh delivery.
- [ ] Implement ntfy.sh as the first webhook backend with dry-run tests before
      adding Slack or Discord.

## Usage Monitor

- [ ] Add structured JSON logging for `poller.main` and `poller.notify` while
      preserving the existing private-log redaction behavior.
- [ ] Add direct tests for `src/poller/time_utils.py`: ISO parsing, countdown
      formatting, bad inputs, and nested dot-path lookup. (good first issue)
- [ ] Add boundary tests for `src/poller/value.py` when token fields are
      missing, zero, or partially populated. (good first issue)
- [ ] Expand Gemini collector tests for network failures, schema drift, and
      parse errors using existing stubs or mocks.
- [ ] Prototype rate-limit prediction from existing pace data and document the
      false-positive cases before wiring notifications.

## Docs

- [ ] Add a non-destructive `--check` mode to
      `docs/api/generate-cli-reference.sh` so CI can detect CLI reference
      drift without rewriting files.
- [ ] Document how to verify `sbom.json` and the GitHub build-provenance
      attestation after a release.
- [ ] Add a short dashboard note that distinguishes the current static
      snapshot file from the planned local HTML/JS dashboard. (good first issue)
- [ ] Automate the public-release leakage pass for absolute home paths, real
      emails outside attribution files, private project names, and stale
      local-only examples.
- [ ] Move the current `[Unreleased]` changelog content into the v0.3.0
      release section when the release issue is approved.

## Tests

- [ ] Add `tests/python/test_config.py` for `common.config` environment
      handling and cache-clearing behavior. (good first issue)
- [ ] Add `tests/python/test_dep_graph.py` using a temporary source tree to
      cover JSON output, Mermaid output, and cycle detection. (good first issue)
- [ ] Verify whether `tests/bats/08_installers.bats` covers
      `src/bin/install-commander.sh`; add focused cases or document the gap.
- [ ] Add error-path Bats coverage for `src/recipes/snapshot.sh` and
      `src/recipes/hygiene.sh`.
- [ ] Raise the Python coverage gate only after the uncovered and under-tested
      modules in `tests/COVERAGE_MAP.md` have focused tests.

## Packaging

- [ ] Finish the v0.3.0 release checklist: changelog section, `VERSION`,
      `src/scheduler/__init__.py`, `make lint`, `make test`, and
      `make release V=0.3.0`.
- [ ] Create the Homebrew tap plan, including formula source, install layout,
      test command, and release ownership.
- [ ] Add a packaging smoke test that an installed checkout can run
      `eco list`, `eco doctor`, and `eco scheduler status --json` with a
      temporary `ECO_HOME`.
- [ ] Keep `.devcontainer/scripts/readiness.sh --quick` green for first-time
      contributors in GitHub Codespaces and local Dev Containers.
- [ ] Document the exact release artifacts expected on GitHub: notes, SBOM,
      and provenance attestation.
