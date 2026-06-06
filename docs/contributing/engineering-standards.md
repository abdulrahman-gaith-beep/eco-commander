# Engineering Standards

> **Purpose:** A practical framework for engineering a public, adoption-ready
> repository. The examples below are drawn from this repo's actual gates,
> layout, tests, docs, release process, and GitHub Actions workflows.

Use this page in two ways:

1. As a map for contributing to eco-commander without guessing what CI expects.
2. As a reusable checklist for building another repository that can attract
   users, contributors, and maintainers without relying on tribal knowledge.

## Standard 1: Make Quality Gates Explicit

A public repo needs one obvious answer to "what must pass before this change is
safe?" Here, that answer is the [`Makefile`](../../Makefile).

| Gate | Command | What it enforces |
|------|---------|------------------|
| Shell tests | `make test-bats` | Runs Bats suites through `tests/run-all.sh bats`; covers the CLI router, SwiftBar widget paths, recipes, installers, account rotation, shared shell helpers, and pure shell functions. |
| Python tests | `make test-python` | Runs `PYTHONPATH=src python -m unittest discover -s tests/python -p "test_*.py"` against `src/poller/` and `src/scheduler/`. |
| Static analysis | `make lint` | Runs [`scripts/lint.sh`](../../scripts/lint.sh) for `shellcheck`, YAML parsing, and plist-template parsing, then runs `ruff check src/ tests/python/`. |
| Docs validation | `make validate-docs` | Runs [`docs/scripts/validate-links.sh`](../scripts/validate-links.sh) for internal links, orphan checks, and `docs/INDEX.md` coverage, then [`validate-mermaid.sh`](../scripts/validate-mermaid.sh) for Mermaid placeholder safety. |
| Security audit | `make security-audit` | Runs `gitleaks detect --no-git --source . --redact --config .gitleaks.toml` and `pip-audit -r requirements.txt --strict`. |

The repo also exposes composite targets:

| Command | Use it when |
|---------|-------------|
| `make test-fast` | You need the local fast loop: Bats + Python, no E2E. |
| `make test` | You need the full suite: Bats + Python + E2E. |
| `make hygiene` | You are touching workflows, dependencies, docs, release controls, or security-sensitive paths. It runs lint, pre-commit, actionlint, security audit, docs validation, and `git diff --check`. |
| `make release V=X.Y.Z` | You are cutting a release through [`scripts/release.sh`](../../scripts/release.sh). |

Reusable pattern: expose every gate as a boring command. Contributors should not
need to know which tool is underneath until a gate fails.

## Standard 2: Separate Source, Runtime State, and Contributor Fixtures

The repository is engineered around a clear boundary: committed source lives in
`src/`; user runtime state lives under `~/.eco/`; tests create synthetic homes.

| Area | What lives there | Why it matters |
|------|------------------|----------------|
| `src/bin/` | `eco`, `eco-commander.15s.sh`, `eco-alerts.sh`, and related command surfaces | Runtime entry points stay reviewable in Git instead of drifting in a local install directory. |
| `src/recipes/` | Standalone recipe scripts with a shared shell contract | New user-facing actions can be added without bloating the CLI router. |
| `src/poller/` | Python usage-monitor modules | Polling and token-meter parsing are isolated from shell UI code. |
| `src/scheduler/` | Python scheduler, routing, queue, and provider adapters | Dispatch logic has a typed module boundary and its own unit-test surface. |
| `src/common/` | Shared Python config helpers | Shared behavior is not duplicated across poller and scheduler modules. |
| `scripts/` | Install, uninstall, lint, release, LaunchAgent, and support scripts | Repo operations are versioned beside the code they affect. |
| `~/.eco/` | Symlinked commands, recipes, snapshots, queue, logs, and state | The installed product can run on a user's machine without treating the Git checkout as mutable state. |
| `tests/fixtures/` | Canned JSON/YAML inputs | Tests use deterministic data rather than live local state. |

The install model is implemented by [`scripts/install.sh`](../../scripts/install.sh):

- It creates `~/.eco/bin` and `~/.eco/recipes` with owner-only permissions.
- It symlinks `src/bin/*` into `~/.eco/bin/`.
- It symlinks `src/recipes/*.sh` into `~/.eco/recipes/`.
- It registers the SwiftBar plugin when the SwiftBar plugin directory exists.
- It skips LaunchAgents unless `ECO_INSTALL_LAUNCHAGENTS=1` is set.
- It refuses root installs and refuses to overwrite non-owned paths.

Reusable pattern: install from source with reversible symlinks, keep mutable
runtime files outside the repo, and make tests point at synthetic runtime roots.

## Standard 3: Build a Test Pyramid Around Real Risk

The test pyramid is documented in [`testing.md`](./testing.md) and wired through
`make test`.

| Layer | Path | Runner | Primary job |
|-------|------|--------|-------------|
| Shell unit and contract tests | `tests/bats/` | Bats via `tests/run-all.sh` | Exercise Bash commands, recipes, install behavior, parsing paths, and CLI output contracts. |
| Python unit tests | `tests/python/` | `unittest discover` | Exercise poller and scheduler behavior with mocked external APIs and deterministic files. |
| End-to-end tests | `tests/e2e/` | `tests/e2e/run_e2e.sh` | Render the widget and integrated flows inside synthetic `ECO_HOME` sandboxes. |

The important engineering choice is not just "many tests"; it is hermeticity:

- Bats `setup()` calls `eco_setup` from
  [`tests/helpers/common.bash`](../../tests/helpers/common.bash).
- `eco_setup` creates a fresh temporary `$HOME` and populates `$HOME/.eco/`.
- Test `PATH` is prepended with `tests/helpers/stubs/`.
- External tools such as `claude`, `curl`, `gemini`, `ollama`, `osascript`,
  and `open` are represented by stubs.
- Python tests mock external API calls and file IO instead of touching real
  OAuth endpoints or local runtime files.
- E2E tests create `/tmp` sandboxes and run the widget with explicit `HOME`,
  `ECO_HOME`, and `ECO_COMMANDER_REPO` values.

Reusable pattern: tests may verify integrations, but they should not depend on
the maintainer's real machine, live credentials, or the network.

## Standard 4: Treat Documentation as a Tested Surface

The docs tree follows the Diataxis model called out in [`docs/INDEX.md`](../INDEX.md):
tutorials, how-to material, reference, and explanation are separate.

| Diataxis mode | Repo example | Reader question |
|---------------|--------------|-----------------|
| Tutorial | [`tutorials/first-run.md`](../tutorials/first-run.md) | "Can you walk me through the first successful run?" |
| How-to | [`getting-started/installation.md`](../getting-started/installation.md), [`examples/cookbook.md`](../examples/cookbook.md) | "How do I complete this task?" |
| Reference | [`reference/data-model.md`](../reference/data-model.md), [`api/cli-reference.md`](../api/cli-reference.md) | "What exactly is the contract?" |
| Explanation | [`architecture.md`](../architecture.md), [`concepts/mental-model.md`](../concepts/mental-model.md), ADRs in [`adr/`](../adr/) | "Why is the system shaped this way?" |

Documentation quality is enforced as code:

| Mechanism | Enforcement |
|-----------|-------------|
| Index coverage | `docs/scripts/validate-links.sh` reports docs missing from `docs/INDEX.md`. |
| Link validation | The same script resolves internal Markdown links. |
| Mermaid validation | `docs/scripts/validate-mermaid.sh` catches raw angle-bracket placeholders that break rendered diagrams. |
| Pre-commit | `.pre-commit-config.yaml` runs Markdown linting and docs link validation on changed docs files. |
| CI hygiene | `.github/workflows/hygiene.yml` runs `pre-commit run --all-files`, `actionlint`, and `git diff --check`. |

Reusable pattern: docs are not a side channel. Put them in a navigable
information architecture, then validate links and coverage in CI.

## Standard 5: Version and Release Through Auditable Gates

Release behavior is split between human-edited files, a local release script,
and the GitHub release workflow.

| Surface | Source of truth |
|---------|-----------------|
| Version file | [`VERSION`](../../VERSION) |
| Python package version | `scheduler.__version__` in [`src/scheduler/__init__.py`](../../src/scheduler/__init__.py) |
| Release history | [`CHANGELOG.md`](../../CHANGELOG.md), using Keep a Changelog |
| Versioning policy | [`versioning-compatibility.md`](../reference/versioning-compatibility.md), using SemVer with a documented pre-1.0 policy |
| Release command | `make release V=X.Y.Z` |

[`scripts/release.sh`](../../scripts/release.sh) enforces this before tagging:

1. The version argument matches `X.Y.Z`.
2. The release runs from `main`.
3. `origin` exists.
4. The working tree is clean.
5. `vX.Y.Z` does not already exist.
6. `CHANGELOG.md` contains `## [X.Y.Z]`.
7. `VERSION` contains exactly `X.Y.Z`.
8. `src/scheduler/__init__.py` contains `__version__ = "X.Y.Z"`.
9. `make lint` passes.
10. `make test` passes.
11. The annotated tag is created and pushed.

The [`release.yml`](../../.github/workflows/release.yml) workflow then publishes
from an existing `v*.*.*` tag or manual dispatch input. It checks out the tag,
runs `make lint` and `make test`, extracts release notes from `CHANGELOG.md`,
creates the GitHub Release, uploads a CycloneDX SBOM from `requirements.txt`,
and attests build provenance for the SBOM.

Commits are also structured. Local hooks and
[`commitlint.yml`](../../.github/workflows/commitlint.yml) enforce Conventional
Commits with these allowed types: `feat`, `fix`, `docs`, `test`, `ci`, `build`,
`chore`, `refactor`, `perf`, `security`, `style`, `revert`, and `audit`.

Reusable pattern: make a release impossible unless version files, changelog,
tests, lint, tag shape, and release notes agree.

## Standard 6: Make Security a Default Gate

Security is not a separate checklist at the end of a release. It is part of the
normal contributor path.

| Control | Where it runs | What it prevents |
|---------|---------------|------------------|
| Secret scanning | `make security-audit` and [`security.yml`](../../.github/workflows/security.yml) | Accidental credential commits, with redacted output. |
| Gitleaks config | [`.gitleaks.toml`](../../.gitleaks.toml) | Uses repo config and limits the test-fixture allowlist to `tests/fixtures/`. |
| Dependency audit | `pip-audit -r requirements.txt --strict` | Known vulnerable runtime Python dependencies. |
| Dependency Review | [`dependency-review.yml`](../../.github/workflows/dependency-review.yml) | PR dependency changes with high-severity vulnerabilities or GPL-3.0/AGPL-3.0 licenses. |
| CodeQL | [`codeql.yml`](../../.github/workflows/codeql.yml) | Python static-analysis findings reported to GitHub code scanning. |
| Pre-commit private-key detection | `.pre-commit-config.yaml` | Private-key patterns before commit. |
| Runtime path hygiene | Shell standards in [`CONTRIBUTING.md`](../../CONTRIBUTING.md) | No embedded credentials or absolute user paths; use `$HOME` and environment variables. |
| Redaction discipline | Security workflow and tests | Secret scans use `--redact`; tests use fake token-like fixtures where needed. |

Reusable pattern: combine static scanning, dependency policy, code scanning,
redacted output, path hygiene, and tests that prove sensitive data is not echoed.

## Standard 7: Use CI/CD as a Contributor Contract

The current workflow files under `.github/workflows/` are:

| Workflow | Trigger | PR role |
|----------|---------|---------|
| [`ci.yml`](../../.github/workflows/ci.yml) | Push to `main`, PR to `main`, manual | Runs macOS matrix on Python 3.10 and 3.13: install smoke, lint, actionlint, mypy, syntax checks, Bats, E2E, Python unit tests under coverage, and coverage artifact upload. |
| [`hygiene.yml`](../../.github/workflows/hygiene.yml) | Push to `main`, PR to `main`, weekly schedule, manual | Runs pre-commit on all files, workflow lint, and whitespace checks. |
| [`security.yml`](../../.github/workflows/security.yml) | Push to `main`, PR to `main`, weekly schedule, manual | Runs gitleaks and `pip-audit`. |
| [`codeql.yml`](../../.github/workflows/codeql.yml) | Push to `main`, PR to `main`, weekly schedule, manual | Runs CodeQL for Python. |
| [`commitlint.yml`](../../.github/workflows/commitlint.yml) | PR opened, synchronized, reopened, edited; manual | Enforces Conventional Commit shape. |
| [`dependency-review.yml`](../../.github/workflows/dependency-review.yml) | PR to `main` | Reviews dependency changes, blocks high severity and denied licenses, and comments in PRs. |
| [`labeler.yml`](../../.github/workflows/labeler.yml) | `pull_request_target` events | Applies PR labels without changing the code gate. |
| [`dependabot-automerge.yml`](../../.github/workflows/dependabot-automerge.yml) | `pull_request_target` | For Dependabot only, auto-approves and queues auto-merge for non-major updates. |
| [`release.yml`](../../.github/workflows/release.yml) | SemVer tag push or manual dispatch | Publishes GitHub releases, SBOM, and provenance attestation from existing tags. |
| [`stale.yml`](../../.github/workflows/stale.yml) | Weekly schedule or manual | Marks and closes inactive issues/PRs, excluding security-sensitive labels. |

The required merge checks are documented in
[`repository-governance.md`](./repository-governance.md): CI for Python 3.10 and
3.13, Repository Hygiene, Security, CodeQL, Commitlint, and Dependency Review.

Reusable pattern: CI should explain the contribution contract. A new maintainer
should be able to predict which checks run on PRs, which checks run on releases,
and which automations are informational.

## Adoption Checklist

Use this checklist when creating or hardening any public repository.

| Area | Standard |
|------|----------|
| Entry points | Provide `make bootstrap`, `make lint`, `make test`, `make hygiene`, and `make release`. |
| Runtime split | Keep committed source, local install paths, mutable state, and test fixtures separate. |
| Install safety | Refuse root installs, use owner-only permissions for local state, and avoid overwriting foreign files. |
| Tests | Use a pyramid: fast unit tests, integration tests where contracts cross, and E2E tests for user-visible flows. |
| Hermeticity | Stub external tools, sandbox `$HOME`, avoid real credentials, and keep tests network-independent. |
| Docs | Use Diataxis, maintain an index, validate internal links, and document public contracts before release. |
| Versioning | Keep one version policy, one changelog format, one release command, and machine-checkable version files. |
| Commits | Enforce Conventional Commits locally and in CI. |
| Security | Run secret scanning, dependency audit, CodeQL or equivalent static analysis, and dependency review on PRs. |
| CI matrix | Test the supported language/runtime versions that users actually run. |
| Release artifacts | Publish from tags, extract notes from the changelog, attach an SBOM, and attest provenance where supported. |
| Governance | Document required checks, code-owner paths, labels, security reporting, and merge rules. |
| Adoption | Make the first contribution path obvious: setup, test, docs rules, PR expectations, and review gates. |

The core idea is simple: every claim in the README, docs, release notes, and PR
process should correspond to a source file, a test, a gate, or a documented
maintainer rule. That is what lets a public repo scale beyond its original
author without becoming fragile.

## Related

- [CONTRIBUTING.md](../../CONTRIBUTING.md) — contributor workflow
- [developer-hygiene.md](./developer-hygiene.md) — local quality gates
- [testing.md](./testing.md) — test architecture and commands
- [repository-governance.md](./repository-governance.md) — branch protection and release gates
- [CONTRIBUTING-DOCS.md](./CONTRIBUTING-DOCS.md) — documentation standards
- [versioning-compatibility.md](../reference/versioning-compatibility.md) — SemVer and compatibility policy
