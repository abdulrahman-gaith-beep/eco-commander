#!/usr/bin/env bash
# Workspace-dependent devcontainer setup.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

export ECO_COMMANDER_REPO="${ECO_COMMANDER_REPO:-$REPO_ROOT}"
export ECO_HOME="${ECO_HOME:-$HOME/.eco}"
export VENV_DIR="${VENV_DIR:-$HOME/.venvs/eco-commander}"
export PYTHON_BIN="${PYTHON_BIN:-python3.13}"
export PATH="$REPO_ROOT/.devcontainer/bin:$VENV_DIR/bin:$ECO_HOME/bin:$HOME/go/bin:$PATH"

log() { printf "[devcontainer:post-create] %s\n" "$*"; }
warn() { printf "[devcontainer:post-create] warning: %s\n" "$*" >&2; }

log "installing devcontainer-only CLI tools"
bash .devcontainer/scripts/install-dev-tools.sh

log "creating Linux venv outside the bind-mounted workspace: $VENV_DIR"
VENV_DIR="$VENV_DIR" PYTHON_BIN="$PYTHON_BIN" bash scripts/setup-venv.sh

log "linking eco command surface into $ECO_HOME"
bash .devcontainer/scripts/link-eco-home.sh

if [ -x "$VENV_DIR/bin/pre-commit" ] && [ -d .git ]; then
  log "installing pre-commit hooks"
  "$VENV_DIR/bin/pre-commit" install --install-hooks || warn "pre-commit hook installation failed"
  "$VENV_DIR/bin/pre-commit" install --hook-type commit-msg || warn "commit-msg hook installation failed"
fi

log "running quick readiness checks"
bash .devcontainer/scripts/readiness.sh --quick
