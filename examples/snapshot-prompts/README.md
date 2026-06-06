# Snapshot Prompt Examples

This directory is a small public prompt library for `eco snapshot`. It lets the
snapshot recipe run from a fresh checkout without requiring an operator-private
audit prompt collection.

The example library contains two generic layers:

- `example-layer-a.md` asks for a neutral tool and runtime inventory summary.
- `example-layer-b.md` asks for a neutral workflow and documentation summary.

The prompts are intentionally generic. They do not name private projects,
subscription plans, account counts, credentials, emails, local usernames, or
machine-specific paths.

To use a private prompt library, keep it outside the repository and set
`ECO_AUDIT_ROOT` to a directory containing `prompts/`:

```bash
ECO_AUDIT_ROOT="$HOME/.eco/ecosystem-audit" eco snapshot
```

Custom prompt libraries may include `_SHARED.md`; the snapshot recipe prepends
it to each layer prompt when present.
