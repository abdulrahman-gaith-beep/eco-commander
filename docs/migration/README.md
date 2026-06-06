# Migration Notes

This directory is the canonical hub for version-to-version upgrade notes. Each guide documents what changed, why it changed, and the exact steps required to migrate an existing installation.

See also: [CHANGELOG](../../CHANGELOG.md) | [Documentation Index](../INDEX.md)

---

## Purpose

Migration guides exist for **breaking changes only** — changes that require an operator to take action when upgrading. Non-breaking additions and fixes are recorded in the CHANGELOG and do not require a guide here.

A change is breaking when it affects any of the following stable surfaces:

| Surface | Examples |
|---|---|
| **CLI contract** | New required arguments, removed subcommands, changed flag names |
| **Snapshot format** | Directory layout under `~/.eco/snapshots/`, JSON schema of `state.json` or `usage.json` |
| **Recipe contract** | New required annotations, changed exit codes, renamed environment variables passed to recipes |
| **Configuration** | Renamed env vars, moved config files, changed defaults that alter runtime behaviour |
| **Dependencies** | New required system packages, minimum Python version bumped, Bash version requirement changed |

---

## Current Status

**No breaking migrations yet (pre-1.0).**

eco-commander is pre-1.0. The public API, snapshot format, and recipe contract are still stabilising. The first migration guide will be written when any of the surfaces above changes in a way that requires operator action on upgrade.

---

## How Migration Guides Are Structured

Each guide lives in this directory as `vX.Y-to-vX.Z.md` (e.g., `v0.3-to-v0.4.md`) so files sort chronologically. Every guide follows this template:

```markdown
# Migrating from vX.Y to vX.Z

**Released:** YYYY-MM-DD
**Affects:** (e.g., snapshot format, CLI contract)
**Related ADR:** ADR NNNN (see [`../adr/`](../adr/README.md))

## What changed

Brief description of the breaking change and which subsystem it affects.

## Why

Rationale for the change — link to the ADR or RFC that approved it.

## Migration steps

1. Step one with exact command.
2. Step two with exact command.
3. Verify: expected output after a successful migration.

## Rollback

How to revert to the previous version if the migration fails.
Include any data-safety notes (e.g., snapshot directories to preserve).
```

---

## How to Add a Guide

1. Determine the version range (e.g., `v0.3` → `v0.4`).
2. Create `docs/migration/vX.Y-to-vX.Z.md` using the template above.
3. Link the relevant ADR in the "Related ADR" field.
4. Add an entry in [CHANGELOG](../../CHANGELOG.md) under the new version heading.
5. If the change also affects the snapshot format or data model, update [reference/data-model.md](../reference/data-model.md).

Migration guides must be written **before the PR is merged**, not after.
