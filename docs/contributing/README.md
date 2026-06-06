# Contributing — cluster landing page

> This directory documents the standards and processes for contributing to
> eco-commander's codebase and documentation.

| Doc | Purpose |
|-----|---------|
| [CONTRIBUTING-DOCS.md](./CONTRIBUTING-DOCS.md) | When and how to update docs: change-type matrix, quality checklist, validators (`validate-links.sh`, `doc-stats.sh`), ADR conventions, staleness prevention |
| [developer-hygiene.md](./developer-hygiene.md) | Bootstrap setup, conventional commits, pre-commit hooks (16 hooks), local quality gates |
| [repository-governance.md](./repository-governance.md) | Branch protection rules, CODEOWNERS, label taxonomy, and release gate |
| [testing.md](./testing.md) | Test architecture: a comprehensive Bats + Python + E2E suite; how to run each suite; fixtures and helpers |

## Before your first PR

1. Run `make bootstrap` (or `bash scripts/bootstrap.sh`) to install all tools
   and Git hooks in one step.
2. Read [developer-hygiene.md](./developer-hygiene.md) for commit conventions
   and pre-commit gate details.
3. Read [CONTRIBUTING-DOCS.md](./CONTRIBUTING-DOCS.md) for the doc-update
   matrix if your change touches `docs/`.
4. Run `make lint && make test` locally before pushing.
5. See [../../CONTRIBUTING.md](../../CONTRIBUTING.md) for the full contributor
   workflow (fork, branch, PR, review process).

## Cross-references

- **Full contributor workflow** → [../../CONTRIBUTING.md](../../CONTRIBUTING.md)
- **Project governance and decision-making** → [../../GOVERNANCE.md](../../GOVERNANCE.md)
- **Architecture decisions (ADRs)** → [`../adr/`](../adr/) (format defined in
  [CONTRIBUTING-DOCS.md](./CONTRIBUTING-DOCS.md))
- **CI workflows** → [`.github/workflows/`](../../.github/workflows/)
- **Branch protection and label config** → [`.github/settings.yml`](../../.github/settings.yml)

## Related

- [testing.md](./testing.md) — test suite details
- [developer-hygiene.md](./developer-hygiene.md) — local gates
- [repository-governance.md](./repository-governance.md) — merge requirements
- [CONTRIBUTING-DOCS.md](./CONTRIBUTING-DOCS.md) — documentation standards
