# Developer Hygiene

> Local quality gates, pre-commit hooks, and daily checks that keep the repo
> healthy and aligned with what CI enforces.

This repo keeps local and CI checks in sync through the same entry points:
`make lint`, `make test`, and `make hygiene`.

## Bootstrap (first-time setup)

One command installs all dependencies, wires the Git hooks, and runs a smoke
test:

```bash
bash scripts/bootstrap.sh
# or
make bootstrap
```

What it does:

1. Installs Homebrew dependencies (`Brewfile` — bats-core, shellcheck, actionlint, …).
2. Creates `.venv` and installs `requirements.txt` + `requirements-dev.txt`.
3. Installs pre-commit and commit-msg hooks via `scripts/install-hooks.sh`.
4. Creates per-file symlinks under `~/.eco/bin/` and `~/.eco/recipes/` (`make install`).
5. Runs the Bats smoke suite.

### Manual setup (step by step)

```bash
brew bundle --file=Brewfile

python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt -r requirements-dev.txt

pre-commit install
pre-commit install --hook-type commit-msg
```

Use Python 3.10 through 3.13. Python 3.14 is not a supported target.

## Daily checks

```bash
make lint        # shellcheck + ruff on src/ and scripts/
make test        # full suite: Bats + Python + E2E
make hygiene     # lint + precommit + actionlint + security-audit + validate-docs
```

`make hygiene` is the broad local gate before opening a PR. CI also runs the
Python version matrix, mypy, install smoke, and coverage checks.

## Pre-commit hooks

The hook set is defined in `.pre-commit-config.yaml` (16 hooks across five
external repos plus local hooks). Install once, then every `git commit` runs
them automatically.

```bash
pre-commit install                # file-content hooks
pre-commit install --hook-type commit-msg  # commit-message hook
pre-commit run --all-files        # run manually on the full tree
```

### Hook inventory

| Hook ID | Tool / Repo | What it checks |
|---------|-------------|----------------|
| `trailing-whitespace` | pre-commit-hooks | Trailing whitespace (preserves Markdown line-break `  `) |
| `end-of-file-fixer` | pre-commit-hooks | Ensures files end with a newline |
| `check-added-large-files` | pre-commit-hooks | Blocks files > 1 024 KB |
| `check-case-conflict` | pre-commit-hooks | Case-insensitive filename collisions |
| `check-json` | pre-commit-hooks | Valid JSON syntax |
| `check-merge-conflict` | pre-commit-hooks | Unresolved merge-conflict markers |
| `check-yaml` | pre-commit-hooks | Valid YAML syntax |
| `detect-private-key` | pre-commit-hooks | Private-key patterns |
| `mixed-line-ending` | pre-commit-hooks | Normalises to LF |
| `shellcheck` | shellcheck-py | Shell scripts in `src/` and `scripts/` (`--severity=error`) |
| `yamllint` | yamllint | YAML style (`.yamllint.yml` config) |
| `ruff` | ruff-pre-commit | Python linting with auto-fix |
| `ruff-format` | ruff-pre-commit | Python formatting |
| `markdownlint` | markdownlint-cli | Markdown style (`.markdownlint.json` config) |
| `conventional-commit-msg` | local | Commit message follows Conventional Commits (`scripts/validate-commit-message.sh`) |
| `validate-docs` | local | Internal link validation on changed `docs/` files (`docs/scripts/validate-links.sh`) |

The `.claude/` and `tests/.claude/` trees are excluded from all
hooks (`exclude:` in `.pre-commit-config.yaml`).

## Quality gates in CI

The CI pipeline adds type-checking on top of the pre-commit gates:

| Gate | Tool | Where |
|------|------|-------|
| Shell linting | shellcheck `--severity=error` | pre-commit + `make lint` |
| Python linting | ruff | pre-commit + `make lint-python` |
| Python type-checking | mypy | `ci.yml` (`--ignore-missing-imports`) |
| Markdown style | markdownlint | pre-commit |
| Secret scanning | gitleaks | `security.yml` |
| Python dependency audit | pip-audit | `security.yml` |
| Workflow lint | actionlint | `hygiene.yml` + `make actionlint` |
| Commit messages | Conventional Commits | `commitlint.yml` + pre-commit hook |
| Doc link validation | `docs/scripts/validate-links.sh` | pre-commit + `make validate-docs` |

`mypy` runs in CI. `gitleaks` is not wired into `.pre-commit-config.yaml`, but
it does run locally through `make security-audit` and in CI.

## Conventional Commits

All commit messages must follow the
[Conventional Commits v1.0](https://www.conventionalcommits.org/) specification.
The `conventional-commit-msg` hook and the `commitlint` CI workflow both enforce
this.

```text
<type>(<optional scope>): <description>

[optional body]

[optional footer(s)]
```

Allowed types: `feat`, `fix`, `refactor`, `docs`, `chore`, `security`, `test`,
`build`, `ci`.

## Dependency updates

Dependabot watches GitHub Actions (`/.github/`) and Python requirements
(`/requirements*.txt`). Keep runtime dependencies in `requirements.txt` and
developer-only tools in `requirements-dev.txt` so audits and update PRs stay
precise.

## Related

- [testing.md](./testing.md) — how to run the test suite locally
- [repository-governance.md](./repository-governance.md) — which CI checks are
  required for merge
- `.pre-commit-config.yaml` — canonical hook definitions
- `docs/scripts/validate-links.sh` — documentation link validator
- `scripts/bootstrap.sh` — one-command dev environment setup
