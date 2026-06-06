# ADR 0001 — Record Architecture Decisions

| Field  | Value |
|--------|-------|
| Status | Accepted |
| Date   | 2026-04-27 |

## Context

We need a low-friction way to capture material design decisions so that future
contributors (and future-us) understand _why_ things are the way they are.
Without a shared record, rationale erodes: the same trade-offs get relitigated,
and superseded approaches creep back in.

## Decision

Use Architecture Decision Records (ADRs) following the
[MADR](https://adr.github.io/madr/) flavour of Michael Nygard's format, stored
as Markdown under `docs/adr/`. Each file is numbered sequentially
(`NNNN-kebab-title.md`) and is treated as append-only.

## Consequences

- Every PR that changes the public CLI surface, recipe contract, snapshot
  format, or an external integration **must** add or update an ADR.
- Superseding decisions are recorded in a new file that explicitly references
  the superseded one; the older ADR's Status line is updated to
  `Superseded by ADR NNNN`.
- ADR numbers are never recycled.
- See [`README.md`](./README.md) for the full index and the "how to add an ADR"
  guide.
