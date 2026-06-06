# Contributing to Documentation

> Guidelines for keeping eco-commander docs accurate, complete, and free of
> drift. Covers the change-type matrix, quality checklist, validators, ADR
> conventions, and staleness prevention.

## When to update docs

| Change type | Required doc updates |
|-------------|---------------------|
| New recipe added | Add entry to `docs/subsystems/recipes.md`, update `docs/INDEX.md` and root `INDEX.md` |
| New CLI subcommand | Update `docs/getting-started/usage.md` and `docs/architecture.md` §2.1 |
| New environment variable | Add to `docs/reference/environment-variables.md` |
| New config file | Add to `docs/reference/configuration.md` |
| New LaunchAgent | Update `docs/architecture.md` §4, `docs/getting-started/installation.md` |
| New scheduler adapter | Update `docs/subsystems/` adapter table |
| New ADR | Add file to `docs/adr/`, update `docs/INDEX.md` and root `INDEX.md` |
| Schema change (JSON/YAML) | Update `docs/reference/data-model.md` |
| New troubleshooting scenario | Add to `docs/getting-started/troubleshooting.md` and/or `docs/operations/runbook.md` |
| Security-relevant change | Update `docs/operations/security-model.md` |
| Architectural change | Create or amend an ADR, update `docs/architecture.md` |

## Doc quality checklist

Before merging any PR that touches `docs/`:

- [ ] All internal links resolve (run `bash docs/scripts/validate-links.sh`)
- [ ] New documents are listed in `docs/INDEX.md` and root `INDEX.md`
- [ ] Code examples are tested and copy-pasteable
- [ ] File paths and command names match the actual source code
- [ ] No placeholder text (`TODO`, `TBD`, `FIXME`) left in published docs
- [ ] `docs/MANIFEST.json` is updated if file count changed (run
      `python3 docs/scripts/generate-manifest.py --check` to verify)

## Validators

The documentation validation scripts live in `docs/scripts/`:

```bash
# Check that all internal Markdown links resolve; exit non-zero on broken links
bash docs/scripts/validate-links.sh

# Mermaid placeholder lint; also run by make validate-docs
bash docs/scripts/validate-mermaid.sh

# Corpus statistics: file count, line count, size, ADRs, diagrams, glossary terms
bash docs/scripts/doc-stats.sh
bash docs/scripts/doc-stats.sh --json    # machine-readable output

# Machine-readable manifest drift check
python3 docs/scripts/generate-manifest.py --check
```

`validate-links.sh` also runs as the `validate-docs` pre-commit hook on every
changed `docs/` file. `make validate-docs` runs `validate-links.sh` and
`validate-mermaid.sh`; run it manually before opening a doc-only PR.

## First-time dev setup

The bootstrap script installs all tools including the pre-commit hooks:

```bash
bash scripts/bootstrap.sh
# or
make bootstrap
```

See [developer-hygiene.md](./developer-hygiene.md) for the full toolchain
details.

## Diagrams

Mermaid diagrams live in `docs/diagrams/` as `.md` files with fenced code
blocks. GitHub renders them automatically. Keep diagrams updated when the
component topology or data flow changes.

## ADR conventions

Follow [Michael Nygard's format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions):

```markdown
# ADR NNNN — <Title>

**Status:** Proposed | Accepted | Deprecated | Superseded by NNNN
**Date:** YYYY-MM-DD
**Supersedes:** (if applicable)
**Amends:** (if applicable)

## Context
## Decision
## Consequences
## Alternatives considered
```

Number ADRs sequentially. ADRs are append-only — superseding decisions are
added as new files that reference the older one.

## Glossary

When introducing a new project-specific term, add it to `docs/reference/glossary.md`.

## Staleness prevention

The most common docs failure mode is **drift** — code changes without matching
doc updates. To combat it:

1. `docs/scripts/validate-links.sh` catches broken internal links on every
   commit (via the `validate-docs` pre-commit hook).
2. PR reviewers should check the "When to update docs" table above.
3. `docs/scripts/doc-stats.sh` reports corpus statistics so you can spot
   missing files.
4. The root `INDEX.md` header includes a date — update it when you add files.

## Related

- [developer-hygiene.md](./developer-hygiene.md) — pre-commit hooks including
  `validate-docs`
- [repository-governance.md](./repository-governance.md) — PR review
  requirements
- `docs/scripts/validate-links.sh` — link validator
- `docs/scripts/doc-stats.sh` — corpus statistics generator
- `scripts/bootstrap.sh` — one-command dev environment setup
- `../../CONTRIBUTING.md` — full contributor workflow
