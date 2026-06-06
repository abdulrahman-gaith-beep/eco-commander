# Runtime Config Templates

This directory contains tracked examples for files that live under `ECO_HOME`
at runtime. The default runtime root is `~/.eco`.

The repo does not keep live runtime config here. Installers and scripts read
from `ECO_HOME`, while these files give contributors and agents a stable source
for expected shapes.

| Template | Runtime path | Purpose |
|---|---|---|
| `config.example.json` | `$ECO_HOME/config.json` | Neutral local plan/account/server-truth override shape |
| `comments.example.json` | `$ECO_HOME/config/comments.json` | Optional burn-rate comment catalog override |

Use these templates as schema references when updating
[`docs/reference/configuration.md`](../docs/reference/configuration.md) or tests
that need a safe local runtime skeleton.
