#!/usr/bin/env bash
# scripts/setup-venv.sh — Automate Python virtual environment creation and dependency installation.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf "[setup-venv] %s\n" "$*"; }
die() { printf "[setup-venv] error: %s\n" "$*" >&2; exit 1; }

cd "$REPO_ROOT"

PYTHON_BIN="${PYTHON_BIN:-}"

if [ -z "$PYTHON_BIN" ]; then
  for py in python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$py" >/dev/null 2>&1; then
      if "$py" -c 'import sys; sys.exit(0 if (3,10) <= sys.version_info < (3,14) else 1)' >/dev/null 2>&1; then
        PYTHON_BIN="$py"
        break
      fi
    fi
  done
fi

if [ -z "$PYTHON_BIN" ]; then
  die "Could not find a Python version between 3.10 and 3.13. Current python3 is $(python3 --version 2>/dev/null || echo 'missing'). Set PYTHON_BIN to override."
fi

log "Using Python binary: $PYTHON_BIN ($("$PYTHON_BIN" --version))"

VENV_DIR="${VENV_DIR:-.venv}"

if [ ! -d "$VENV_DIR" ]; then
  log "Creating virtual environment in $VENV_DIR..."
  "$PYTHON_BIN" -m venv "$VENV_DIR"
else
  log "Virtual environment $VENV_DIR already exists."
fi

log "Activating virtual environment..."
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

log "Upgrading pip..."
pip install --upgrade pip

log "Installing dependencies from requirements.txt and requirements-dev.txt..."
if [ -f requirements.txt ]; then
  pip install -r requirements.txt
else
  log "Warning: requirements.txt not found."
fi

if [ -f requirements-dev.txt ]; then
  pip install -r requirements-dev.txt
else
  log "Warning: requirements-dev.txt not found."
fi

log "Virtual environment setup complete."
log "To activate manually, run: source $VENV_DIR/bin/activate"
