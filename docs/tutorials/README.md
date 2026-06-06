# Tutorials

> **Diataxis type:** Tutorial cluster — learning-oriented content for people who are
> new to eco-commander and want a safe, guided path to their first working outcome.

Tutorials are distinct from how-to guides and reference material. A tutorial is:

- **Narrative**, not exhaustive — it picks one path, not all paths.
- **Outcome-focused** — you finish with something real working, not just knowledge.
- **Safe to fail** — failures are anticipated, named, and recovered from inside the text.

For task-oriented instructions once you already know the system, see the
[getting-started guides](../getting-started/README.md). For reference material, see the
[reference directory](../reference/README.md).

---

## Available tutorials

| Tutorial | What you build | Time |
|----------|----------------|------|
| [first-run.md](./first-run.md) | Working `eco` CLI + SwiftBar widget + first recipe run | ~20 min |

---

## Learning path

If this is your first time with eco-commander, read in this order:

1. **[first-run.md](./first-run.md)** — clone, bootstrap, install LaunchAgents, verify the
   widget, run `eco do ask`, run `eco doctor`, recover from `eco: command not found`.
2. **[../getting-started/usage.md](../getting-started/usage.md)** — complete CLI reference
   once the system is running.
3. **[../subsystems/recipes.md](../subsystems/recipes.md)** — how to run and write recipes.
4. **[../architecture.md](../architecture.md)** — the mental model behind the system.

---

## Contributing a tutorial

Tutorials live here as standalone Markdown files. Each one must:

- Follow the Diataxis tutorial form: narrative, single path, numbered steps, fenced code
  blocks with expected output, checkpoints, and a "where to go next" footer.
- Link only to documents that verifiably exist in the `docs/` tree.
- Be verified against the actual scripts in `src/` and `scripts/` before merging.

See [../contributing/CONTRIBUTING-DOCS.md](../contributing/CONTRIBUTING-DOCS.md) for the
full documentation contribution guide.
