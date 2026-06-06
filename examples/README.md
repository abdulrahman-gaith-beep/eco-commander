# Examples

Ready-to-run example inputs for Eco Commander. Everything here uses neutral
placeholders and repo-local `workdir: "."` values. Replace `demo-project`, the
prompts, and timing before relying on a job.

## Scheduler mission files

The scheduler runs queued "jobs" (one unit of work each) and routes every job
to the first AI provider whose quota meter is open. Mission YAML files describe
those jobs.

| File | What it contains |
|------|------------------|
| [`missions/seed-jobs.example.yaml`](missions/seed-jobs.example.yaml) | Three illustrative jobs: a raw-prompt warm-up, a deferred research job, and a dependent job gated on manual confirmation. |
| [`missions/audit-missions.example.yaml`](missions/audit-missions.example.yaml) | Two read-only review jobs using raw prompts: repo hygiene and dependency licenses. |

## Running an example

Add a single mission file to the queue:

```bash
eco scheduler add --file examples/missions/seed-jobs.example.yaml
```

Or import every mission file in a directory at once:

```bash
eco scheduler seed --dir examples/missions
```

Inspect what landed in the queue:

```bash
eco scheduler status
```

Dry-run one scheduler tick without calling any provider (no quota is spent, and
the prompt is omitted from logs):

```bash
ECO_DRY_RUN=1 eco scheduler run-once
```

## Notes

- `earliest_iso` may be empty (eligible immediately) or a future ISO-8601
  timestamp (the job waits until that time).
- `model_preference` is a ladder walked top to bottom; the first rung whose
  `meter` is available is used.
- `depends_on_jobs` holds job IDs that must be `completed` first, and
  `requires_confirm: true` holds a job until you approve it.
- See [`../docs/subsystems/scheduler.md`](../docs/subsystems/scheduler.md) for
  the full job schema and the list of supported templates and providers.
