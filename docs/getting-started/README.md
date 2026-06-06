# Getting Started

> Landing page for the eco-commander getting-started cluster. Read these three docs in order to go from zero to a working installation.

## Reading order

| Step | Doc | What you will accomplish |
|------|-----|--------------------------|
| 1 | [installation.md](./installation.md) | Clone, `make install`, wire the SwiftBar plugin, and optionally install LaunchAgents |
| 2 | [usage.md](./usage.md) | Learn every `eco` subcommand, recipe, and flag |
| 3 | [troubleshooting.md](./troubleshooting.md) | Resolve the most common failure modes |

## Five-minute quick start

```bash
# 1. Clone
git clone https://github.com/abdulrahman-gaith-beep/eco-commander.git \
  eco-commander

# 2. Install dependencies
brew install jq bats-core shellcheck
brew install --cask swiftbar   # optional menu-bar widget

# 3. Install eco-commander
cd eco-commander
make install

# 4. Add ~/.eco/bin to PATH for this shell and future shells
export PATH="$HOME/.eco/bin:$PATH"
echo 'export PATH="$HOME/.eco/bin:$PATH"' >> ~/.zshrc

# 5. Verify
eco status
eco doctor
```

`eco doctor` is the installation verification step. It reports optional LaunchAgents and runtime data, but only missing CLI wiring or failed Python imports make it exit non-zero.

Before running Gemini-backed recipes such as `eco do ask`, install and
authenticate the Gemini CLI (or configure `gem-smart`), then verify the backend:

```bash
gemini --version
gemini -p "Reply with: eco ready"
```

If you use `gem-smart` instead:

```bash
"${ECO_GEM_SMART_BIN:-$HOME/bin/gem-smart}" 3.5f \
  -p "Reply with: eco ready" \
  -y \
  --allowed-mcp-server-names none
```

## Related

- [../architecture.md](../architecture.md) — system design and component map
- [../subsystems/](../subsystems/) — scheduler, alerts, recipes, widget deep dives
- [../reference/](../reference/) — environment variables, data model, glossary
- [../operations/](../operations/) — runbook, security model
