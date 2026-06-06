# Versioning & Compatibility

> **Purpose:** The compatibility contract for eco-commander — supported platforms,
> dependency versions, semantic-versioning rules, schema stability, and deprecation
> windows. Read this before upgrading or when planning a release.

eco-commander follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)
and records every change in [`../../CHANGELOG.md`](../../CHANGELOG.md) using the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. The canonical version
string lives in [`../../VERSION`](../../VERSION) and is exposed programmatically via
`scheduler.__version__`.

**Current version:** `0.2.0` (pre-1.0 — see [Pre-1.0 policy](#pre-10-policy)).

## Supported platforms

| Component | Supported | Notes |
|-----------|-----------|-------|
| **OS** | macOS 13+ (Ventura and later) | Hard requirement — relies on `launchd`, SwiftBar, `osascript`, `qlmanage`, Keychain |
| **Dev Containers** | Linux contributor subset | Supported for editing, linting, and portable tests; macOS runtime surfaces are shimmed or disabled. See [`../../.devcontainer/README.md`](../../.devcontainer/README.md). |
| **Shell** | Bash 3.2+ (system bash) and Bash 5.x (Homebrew) | Scripts target the macOS system bash; `set -euo pipefail` safe |
| **Python** | 3.10 – 3.13 (`>=3.10,<3.14`) | Poller + scheduler. **3.14 is not supported.** Enforced by `scripts/setup-venv.sh` and `pyproject.toml` `requires-python` |
| **SwiftBar** | 1.4.x+ | Menu-bar widget host; install via Homebrew cask |
| **Architecture** | Apple Silicon (arm64) + Intel (x86_64) | Homebrew prefix auto-detected |

## Runtime dependencies

| Dependency | Constraint | Source of truth |
|------------|-----------|-----------------|
| `PyYAML` | `>=6.0.3` (runtime) | `pyproject.toml`, `requirements.txt` |
| CLI tools | `jq`, `shellcheck`, `shfmt`, `bats-core`, `actionlint`, `gitleaks` | [`../../Brewfile`](../../Brewfile) |
| Dev | `ruff==0.11.12`, `mypy==2.1.0`, `coverage`, `pip-audit`, `pre-commit` | [`../../requirements-dev.txt`](../../requirements-dev.txt) |

External AI CLIs (`claude`, `gemini`, `codex`, `ollama`) are **optional integrations** discovered
at runtime — their absence degrades gracefully (the relevant meter is omitted, not fatal).

## SemVer rules for this project

Given a version `MAJOR.MINOR.PATCH`:

| Bump | When | Examples |
|------|------|----------|
| **MAJOR** | Backwards-incompatible change to a public contract | Renamed/removed `eco` subcommand; breaking change to `state.json`/`usage.json`/`jobs.yaml` schema; dropped macOS/Python version |
| **MINOR** | Backwards-compatible capability | New recipe, new `eco` subcommand, new scheduler adapter, new optional config field |
| **PATCH** | Backwards-compatible fix | Bug fix, doc fix, internal refactor, calibration update |

### Public contract surface

These are the interfaces SemVer protects:

- The `eco` CLI subcommands and flags ([`../api/cli-reference.md`](../api/cli-reference.md))
- The on-disk data schemas ([`data-model.md`](./data-model.md)): `state.json`, `usage.json`, `notify.json`, `jobs.yaml`
- The recipe contract ([`../subsystems/recipes.md`](../subsystems/recipes.md))
- LaunchAgent labels (`com.eco-commander.*`)
- Documented environment variables ([`environment-variables.md`](./environment-variables.md))

Internal module layout (`src/poller/*`, `src/scheduler/*`) is **not** a public contract and may
change in any release.

## Schema compatibility

On-disk JSON/YAML files carry a `schema_version` / `version` field. The poller and scheduler
read older minor schema versions where practical and rewrite to the current shape on next run.
A `schema_version` **major** bump is a breaking change and requires a migration note.

## Pre-1.0 policy

While the version is `0.y.z`:

- The API is still stabilizing. Per SemVer §4, a `MINOR` bump (`0.2 → 0.3`) **may** include
  breaking changes; a `PATCH` bump (`0.2.0 → 0.2.1`) will not.
- Breaking changes are still announced in [`../../CHANGELOG.md`](../../CHANGELOG.md) and, when they
  affect on-disk state or commands, documented under [`../migration/`](../migration/README.md).
- There are no breaking migrations to date — see [`../migration/README.md`](../migration/README.md).

## Deprecation window

A feature marked deprecated remains functional for at least one `MINOR` release with a runtime
notice (and a CHANGELOG `Deprecated` entry) before removal in a subsequent `MAJOR`/`MINOR`.

## See also

- [`../../CHANGELOG.md`](../../CHANGELOG.md) — release history
- [`../migration/README.md`](../migration/README.md) — upgrade notes hub
- [`../contributing/repository-governance.md`](../contributing/repository-governance.md) — release gates
- [`data-model.md`](./data-model.md) — the protected schemas
