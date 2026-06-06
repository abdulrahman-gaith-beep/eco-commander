# Repository Governance

> Source of truth for the branch-protection rules, label taxonomy, and release
> gates enforced in this repository. The machine-readable version of most
> settings lives in `.github/settings.yml` (GitHub Settings app) and
> `.github/CODEOWNERS`.

## Branch protection (`main`)

Settings declared in `.github/settings.yml → branches[main].protection`:

| Rule | Value |
|------|-------|
| Required approving reviews | 0 |
| Dismiss stale reviews on new push | yes |
| Require code-owner review | no (CODEOWNERS documents ownership; it is not a required branch-protection gate) |
| Require branch to be up to date | yes (`strict: true`) |
| Enforce rules for administrators | yes (`enforce_admins: true`) |
| Restrict direct pushes | no named restrictions (`restrictions: null`) |

### Required status checks

All seven checks must pass before merge:

| Check name | Workflow file |
|-----------|--------------|
| `CI / Python 3.10` | `.github/workflows/ci.yml` |
| `CI / Python 3.13` | `.github/workflows/ci.yml` |
| `Repository Hygiene / Hygiene` | `.github/workflows/hygiene.yml` |
| `Security / Secret and dependency scan` | `.github/workflows/security.yml` |
| `CodeQL / CodeQL` | `.github/workflows/codeql.yml` |
| `Commitlint / Commitlint` | `.github/workflows/commitlint.yml` |
| `Dependency Review / Dependency review` | `.github/workflows/dependency-review.yml` |

## CODEOWNERS

`.github/CODEOWNERS` maps ownership paths to `@abdulrahman-gaith-beep`. Current
branch protection does not require code-owner review, but the map documents who
owns each release-sensitive area:

| Path pattern | Reason |
|-------------|--------|
| `*` (default) | All files — catch-all owner |
| `.github/`, `.github/workflows/*.yml` | Workflow and repo policy changes |
| `CHANGELOG.md`, `SECURITY.md`, `GOVERNANCE.md` | Release and security surfaces |
| `scripts/release.sh` | Release tooling |
| `.pre-commit-config.yaml`, `pyproject.toml`, `requirements*.txt`, `Brewfile` | Supply-chain security |
| `scripts/install*.sh`, `scripts/uninstall*.sh` | Local-install surfaces |
| `src/poller/*oauth.py`, `src/poller/claude.py`, `src/poller/codex.py`, `src/poller/gemini.py` | Credential-adjacent code |
| `src/bin/`, `src/scheduler/`, `src/tools/` | Core CLI and scheduler (release-affecting) |

## Labels

Labels are declared in `.github/settings.yml → labels`. Active set:

| Label | Colour | Purpose |
|-------|--------|---------|
| `bug` | red | Something is broken |
| `enhancement` | cyan | New capability or behaviour |
| `security` | dark red | Security-sensitive change or vulnerability fix |
| `dependencies` | blue | Dependency or toolchain update |
| `discussion` | grey | Needs design or operator discussion |
| `area:docs` | blue | Documentation changes |
| `area:github` | purple | GitHub metadata, workflows, repo policy |
| `area:python` | blue | Python poller or scheduler changes |
| `area:scripts` | yellow | Shell scripts, recipes, install tooling |
| `area:tests` | green | Test fixtures or suites |
| `area:audits` | orange | Audit tooling, reports, and metadata |
| `area:config` | light blue | Root config files, linter settings, Makefile |
| `stale` | light grey | Inactive 60+ days; managed by the Stale workflow |

Route security issues through `SECURITY.md`, not public issues.

## Release gate

`scripts/release.sh X.Y.Z` enforces the following checks in order before
tagging:

```bash
scripts/release.sh 0.4.0
```

1. Must be run from `main` with a clean working tree.
2. Tag `vX.Y.Z` must not already exist.
3. `CHANGELOG.md` must contain `## [X.Y.Z]`.
4. `src/scheduler/__init__.py` must expose `__version__ = "X.Y.Z"`.
5. `make lint` must pass.
6. `make test` must pass (full suite: Bats + Python + E2E).
7. `git tag -a vX.Y.Z` is created and pushed to `origin`.
8. The `release` workflow (`.github/workflows/release.yml`) publishes the
   GitHub Release from the pushed tag.

Merge-queue squash is preferred (`allow_squash_merge: true`; merge commits are
disabled). Rebase-merge is also permitted. Branches are deleted automatically
after merge (`delete_branch_on_merge: true`).

## Related

- [developer-hygiene.md](./developer-hygiene.md) — local quality gates that
  mirror the CI checks above
- [testing.md](./testing.md) — test suite referenced by the release gate
- [CONTRIBUTING-DOCS.md](./CONTRIBUTING-DOCS.md) — doc-update requirements for
  PRs
- `.github/settings.yml` — machine-readable branch/label/repo config
- `.github/CODEOWNERS` — protected-path owner map
- `scripts/release.sh` — release automation script
- `../../GOVERNANCE.md` — project decision-making and ownership policy
