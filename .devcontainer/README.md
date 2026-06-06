# eco-commander Dev Container

This folder defines a Linux contributor environment for VS Code Dev Containers
and GitHub Codespaces. It is for editing, linting, and most tests. The full
runtime remains macOS-only because SwiftBar, LaunchAgents, Keychain,
`osascript`, `qlmanage`, and `pbcopy` are platform surfaces.

## File Map

| Path | Purpose |
|---|---|
| `devcontainer.json` | Main Dev Containers configuration, lifecycle hooks, VS Code settings, extensions, cache mounts, and repo environment. |
| `Dockerfile` | Debian package layer for Brewfile-equivalent tools available through apt. |
| `scripts/post-create.sh` | Workspace setup: Go-installed CLIs, Linux venv, `ECO_HOME` links, pre-commit hooks, quick readiness. |
| `scripts/install-dev-tools.sh` | Installs `actionlint` and `gitleaks` via Go because CI gets them from Homebrew. |
| `scripts/link-eco-home.sh` | Creates a container-local `ECO_HOME` and links executable bins plus recipes. |
| `scripts/readiness.sh` | Read-only smoke checks for tool availability, manifest validation, Python value tests, and BATS smoke. |
| `scripts/doctor.sh` | Strict wrapper around readiness for manual verification. |
| `scripts/post-attach.sh` | Attach-time status and next-step hints. |
| `bin/date`, `bin/sed`, `bin/stat` | Small BSD-compatibility shims for macOS-shaped tests under Debian. |
| `bin/open`, `bin/osascript`, `bin/pbcopy`, `bin/launchctl`, `bin/vm_stat`, `bin/sysctl`, `bin/qlmanage` | Safe macOS command shims for contributor checks inside Linux. |

## Cross-References

- Toolchain contract: [`../Brewfile`](../Brewfile), [`../requirements-dev.txt`](../requirements-dev.txt)
- Make targets: [`../Makefile`](../Makefile)
- Python venv setup: [`../scripts/setup-venv.sh`](../scripts/setup-venv.sh)
- Script linting: [`../scripts/lint.sh`](../scripts/lint.sh)
- Manifest validation: [`../scripts/verify-manifest.sh`](../scripts/verify-manifest.sh)
- Test architecture: [`../docs/contributing/testing.md`](../docs/contributing/testing.md)
- Version support: [`../docs/reference/versioning-compatibility.md`](../docs/reference/versioning-compatibility.md)
- Mac install lifecycle: [`../docs/diagrams/install-lifecycle.md`](../docs/diagrams/install-lifecycle.md)

## Lifecycle

1. The Dev Containers runtime builds `Dockerfile`.
2. Official Features add common utilities, Node LTS, Go, and GitHub CLI.
3. `scripts/post-create.sh` creates the Linux venv at
   `/home/vscode/.venvs/eco-commander`, outside the bind-mounted workspace.
4. `scripts/link-eco-home.sh` links executable repo commands into
   `/home/vscode/.eco/bin` and recipes into `/home/vscode/.eco/recipes`.
5. `scripts/readiness.sh --quick` validates the minimum contributor surface.

The venv is intentionally not stored in workspace `.venv`; this avoids reusing
a macOS venv inside Debian. `devcontainer.json` sets `PYTHON` and VS Code's
interpreter path to the container venv.

## Commands

```bash
make test-python
make test-bats
make lint
bash .devcontainer/scripts/readiness.sh --strict
```

Full E2E is still macOS-shaped, but the devcontainer prepends compatibility
shims for the known BSD/macOS command usages. Treat Linux E2E failures as
compatibility findings until the test suite is made fully portable.

## Intentional Limits

- No host iCloud, Keychain, Mail, Messages, Safari, or `.ssh` mounts.
- No Docker socket mount by default. Add one only for a specific n8n/Docker
  task and remove it afterwards.
- No LaunchAgent or SwiftBar registration inside the Linux container.
- No live credential probing by default.

## Recovery

If setup fails after a network outage:

```bash
bash .devcontainer/scripts/install-dev-tools.sh
bash .devcontainer/scripts/post-create.sh
```

If the terminal looks stale after rebuild:

```bash
hash -r
bash .devcontainer/scripts/readiness.sh --quick
```
