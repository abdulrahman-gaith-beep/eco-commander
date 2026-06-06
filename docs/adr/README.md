# Architecture Decision Records

This directory contains the Architecture Decision Records (ADRs) for
eco-commander. ADRs capture significant design choices — _what_ was decided,
_why_, and what trade-offs were accepted.

→ Back to [Documentation Index](../INDEX.md)

---

## Index

| # | Title | Status | Date | Summary |
|---|-------|--------|------|---------|
| [0001](./0001-record-architecture-decisions.md) | Record Architecture Decisions | Accepted | 2026-04-27 | Use numbered MADR-style ADRs in `docs/adr/` as the canonical record of material design decisions. |
| [0002](./0002-bash-implementation.md) | Implement Core in Bash, Not Python | Accepted _(amended by 0004)_ | 2026-04-27 | Router, SwiftBar plugin, and recipes are implemented in Bash 5 for zero install overhead and fast cold start. |
| [0003](./0003-snapshot-immutability.md) | Snapshots Are Immutable | Accepted | 2026-04-27 | Each snapshot run writes a new `~/.eco/snapshots/<UTC-ISO>/` directory; `~/.eco/current` is updated atomically via symlink swap. |
| [0004](./0004-usage-monitor-python-carveout.md) | Usage Monitor: Python Carve-out + LaunchAgent Poller | Accepted | 2026-05-09 | Adds `src/poller/` (stdlib-only Python) for token aggregation and OAuth; renderer stays in bash; poller runs via launchd every 60 s. |
| [0005](./0005-job-scheduler.md) | Job Scheduler: Quota-Aware Multi-Provider Dispatch | Accepted | 2026-05-11 | Adds `src/scheduler/` (Python + PyYAML) with a YAML job queue and model-preference ladder; launchd fires one tick every 120 s. |

---

## What Is an ADR?

An Architecture Decision Record documents one architecturally significant
choice. It answers three questions:

1. **Context** — what situation or constraint made a decision necessary?
2. **Decision** — what was chosen, and what does that mean in the codebase?
3. **Consequences** — what are the trade-offs, risks, and follow-on constraints?

ADRs are _not_ design documents or RFCs. They are short (one screen), written
after the decision is made, and treated as append-only history.

---

## When to Add an ADR

Add or update an ADR in any PR that changes:

- The public CLI surface (`eco` subcommands, flags, or exit codes)
- The recipe contract (inputs, outputs, or expected environment)
- The snapshot format (`~/.eco/current/` file structure)
- An external integration (LaunchAgent, SwiftBar, OAuth flow)
- The language or runtime used for a subsystem

---

## How to Add an ADR

1. Pick the next number: `ls docs/adr/ | sort | tail -1`.
2. Copy the template below into `docs/adr/NNNN-kebab-title.md`.
3. Fill in the four required sections. Keep it to one screen.
4. Add a row to the index table above.
5. If the new ADR supersedes an older one, update the older file's Status line
   to `Superseded by ADR NNNN` (linking to the new file).

### Template

```markdown
# ADR NNNN — Title

| Field  | Value |
|--------|-------|
| Status | Proposed / Accepted / Deprecated / Superseded by ADR MMMM |
| Date   | YYYY-MM-DD |

## Context

<!-- What situation makes a decision necessary? -->

## Decision

<!-- What was decided? Be concrete about code paths and file locations. -->

## Consequences

<!-- Positive and negative outcomes; follow-on constraints. -->

## Related

<!-- Optional: links to related ADRs, diagrams, or subsystem docs. -->
```

---

## Numbering Convention

- Numbers are four-digit, zero-padded: `0001`, `0002`, …
- Numbers are assigned sequentially and **never recycled**.
- File name pattern: `NNNN-kebab-case-title.md`.
