# Contributing to eco-commander

Thanks for your interest. The best first PR is small, easy to review, and
covered by the same checks maintainers run in CI.

## Your first contribution

1. Fork the repository on GitHub, then clone your fork:

   ```bash
   git clone https://github.com/<your-username>/eco-commander.git
   cd eco-commander
   git remote add upstream https://github.com/abdulrahman-gaith-beep/eco-commander.git
   git checkout -b docs/first-fix
   ```

2. Bootstrap the local development environment:

   ```bash
   make bootstrap
   ```

   `make bootstrap` runs `scripts/bootstrap.sh`: it installs Brewfile
   dependencies when Homebrew is available, creates `.venv/`, installs Git
   hooks, installs the local per-file CLI/recipe symlinks, and runs smoke
   checks.

3. Run the fast local checks:

   ```bash
   make test-fast
   make lint
   ```

4. Pick a small first issue. Start with `good first issue` when that label is
   available. If it is not in use, `area:docs` and `area:tests` issues are good
   places to start.

5. Commit and open a pull request:

   ```bash
   git status
   git add <files>
   git commit -m "docs(contributing): clarify first contribution flow"
   git push -u origin docs/first-fix
   ```

   Open the PR against `main`. In the PR body, link the issue or briefly explain
   the change and list the checks you ran.

## Local commands

Run `make help` to see the current Makefile targets.

### Setup

| Command | Use |
|---------|-----|
| `make bootstrap` | Full development setup via `scripts/bootstrap.sh` |
| `make venv` | Create `.venv/` and install Python dependencies |
| `make install` | Create local eco dirs with per-file symlinks and register SwiftBar |
| `make install-hooks` | Install pre-commit and commit-message hooks |
| `make clean-venv` | Remove `.venv/` |

### Tests and lint

| Command | Use |
|---------|-----|
| `make test-fast` | Fast local loop: Bats plus Python unit tests |
| `make test` | Full test suite: Bats, Python, and E2E |
| `make test-bats` | Bats suites only |
| `make test-python` | Python unit tests only |
| `make test-e2e` | End-to-end integration tests only |
| `make lint` | `shellcheck` plus `ruff check` |
| `make lint-python` | Run `ruff check --fix` on Python code |
| `make validate-docs` | Validate docs links and Mermaid diagrams |
| `make hygiene` | Lint, pre-commit, workflow lint, security audit, docs validation |

For most small PRs, `make test-fast` and `make lint` are enough before you push.
Run `make test` for CLI, installer, recipe, or integration behavior changes.
Run `make hygiene` before PRs that touch workflows, dependencies, release
controls, documentation structure, or security-sensitive paths.

## Branching model

- `main` is always releasable.
- Feature branches: `feat/<slug>`.
- Fix branches: `fix/<slug>`.
- Docs-only branches: `docs/<slug>`.

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat(recipe): add prompt template option
fix(eco): correct SwiftBar plugin path
docs(architecture): clarify snapshot lifecycle
test(scheduler): cover retry backoff
```

The local `commit-msg` hook and the PR `Commitlint` workflow enforce this
shape.

## Pull requests

> Related diagram: [CI Pipeline](docs/diagrams/ci-pipeline.md) (workflows, test
> matrix, and releases)

Before opening a PR:

- Tests pass locally (`make test-fast`, or `make test` for broader changes).
- Lint is clean (`make lint`).
- Docs are updated when behavior, commands, config, or workflows change.
- Commit messages follow Conventional Commits.
- The PR references an issue or explains the motivation.

Keep PRs focused. Large refactors should ship as a series. A maintainer review
is required before merge.

## Engineering standards

For deeper standards, see
[Engineering Standards](docs/contributing/engineering-standards.md). Related
focused references:

- [Developer Hygiene](docs/contributing/developer-hygiene.md)
- [Testing](docs/contributing/testing.md)
- [Documentation Standards](docs/contributing/CONTRIBUTING-DOCS.md)
- [Repository Governance](docs/contributing/repository-governance.md)

Core rules for code changes:

- Use Python 3.10 through 3.13.
- Bash scripts should use Bash 5+ and `set -euo pipefail`.
- Pass `shellcheck` without warnings, or justify any `# shellcheck disable=...`.
- Quote variable expansions. Prefer `[[ ... ]]` over `[ ... ]`.
- Do not embed credentials or absolute user paths; read from `$HOME` or env.

## Tests

Tests live under `tests/bats/`, `tests/python/`, and `tests/e2e/`. Add fixtures
under `tests/fixtures/` unless a suite has a narrower fixture directory.

```bash
make test-fast   # Bats + Python
make test        # Bats + Python + E2E
```

See [Testing](docs/contributing/testing.md) for suite details and focused test
commands.

## Architecture decisions

Material design choices are recorded as ADRs in `docs/adr/`. Add a new ADR for
any change that affects the public CLI, recipe contract, or snapshot format.

## Release process

See [`scripts/release.sh`](./scripts/release.sh) and the release workflow.
Bump `CHANGELOG.md`, update `src/scheduler/__init__.py`, tag `vX.Y.Z`, push
the tag, and let the release workflow publish GitHub release notes.
