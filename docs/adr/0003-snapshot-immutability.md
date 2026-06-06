# ADR 0003 — Snapshots Are Immutable

| Field  | Value |
|--------|-------|
| Status | Accepted |
| Date   | 2026-04-27 |

## Context

The SwiftBar widget and recipes need a stable, consistent view of ecosystem
state. Mutating a shared file in place creates race conditions between the
writer (poller) and the readers (renderer, recipes): a reader may observe a
partially-written file.

## Decision

Each `eco snapshot` invocation writes a new directory under
`~/.eco/snapshots/<UTC-ISO>/` and only then atomically updates the
`~/.eco/current` symlink via `ln -sfn`. Snapshot directories are immutable once
finalized; the active directory that `~/.eco/current` points at is still the
runtime write target and can receive poller updates while it is current.

```text
~/.eco/
├── snapshots/
│   ├── 2026-04-27T10:00:00Z/   # finalized
│   ├── 2026-04-27T10:05:00Z/   # current/runtime writes may still land here
│   └── …
└── current -> snapshots/2026-04-27T10:05:00Z/   # symlink, updated atomically
```

## Consequences

- Readers observe atomically written files inside `~/.eco/current`; the current
  snapshot may continue to change until a newer snapshot is published.
- Snapshot pruning is a separate, opt-in operation (see
  [`docs/subsystems/snapshots.md`](../subsystems/snapshots.md)).
- Disk usage grows linearly with snapshot count; this is acceptable because
  each snapshot is small (< 1 MB).
- Debugging is easier: historical snapshots remain on disk until pruned.
