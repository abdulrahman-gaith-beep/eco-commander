#!/usr/bin/env bash
# Lightweight attach-time status for VS Code / Codespaces terminals.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ECO_HOME="${ECO_HOME:-$HOME/.eco}"
VENV_DIR="${VENV_DIR:-$HOME/.venvs/eco-commander}"

if [ "${ECO_DEVCONTAINER_QUIET:-0}" = "1" ]; then
  exit 0
fi

cat <<MSG
eco-commander devcontainer
  repo:     $REPO_ROOT
  ECO_HOME: $ECO_HOME
  venv:     $VENV_DIR

Useful commands:
  make test-python
  make test-bats
  make lint
  bash .devcontainer/scripts/readiness.sh --strict
MSG

if [ ! -x "$VENV_DIR/bin/python" ]; then
  printf "\nwarning: venv missing; run: bash .devcontainer/scripts/post-create.sh\n" >&2
fi
